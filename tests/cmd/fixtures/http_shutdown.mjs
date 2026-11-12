// Drive only the child server started here. Every signal targets its own PID.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import net from "node:net";
import path from "node:path";

const executable = path.resolve(process.argv[2]);
const deadlineMs = 15000;
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(test, description, server) {
  const deadline = Date.now() + deadlineMs;
  while (!test()) {
    if (Date.now() >= deadline) {
      throw new Error(`timed out: ${description}\n${server?.stdout ?? ""}${server?.stderr ?? ""}`);
    }
    await delay(10);
  }
}

class Client {
  constructor(socket) {
    this.socket = socket;
    this.bytes = "";
    this.closed = false;
    this.ended = false;
    this.error = null;
    socket.setEncoding("latin1");
    socket.on("data", (bytes) => { this.bytes += bytes; });
    socket.on("end", () => { this.ended = true; });
    socket.on("close", () => { this.closed = true; });
    socket.on("error", (error) => { this.error = error; });
  }

  static async connect(port) {
    const socket = net.createConnection({ host: "127.0.0.1", port });
    const client = new Client(socket);
    await new Promise((resolve, reject) => {
      socket.once("connect", resolve);
      socket.once("error", reject);
    });
    return client;
  }

  write(bytes) {
    this.socket.write(bytes);
  }

  async response(server) {
    await until(() => this.bytes.includes("\r\n\r\n") || this.closed, "response head", server);
    const end = this.bytes.indexOf("\r\n\r\n");
    assert.notEqual(end, -1, `connection closed without a response\n${server.stderr}`);
    const [status, ...lines] = this.bytes.slice(0, end).split("\r\n");
    const headers = Object.fromEntries(lines.map((line) => {
      const colon = line.indexOf(":");
      return [line.slice(0, colon).toLowerCase(), line.slice(colon + 1).trim()];
    }));
    const start = end + 4;
    let length;
    if (headers["content-length"] !== undefined) {
      length = Number(headers["content-length"]);
      await until(() => this.bytes.length >= start + length || this.closed, "response body", server);
      assert(this.bytes.length >= start + length, "truncated response");
    } else {
      assert.equal(headers.connection?.toLowerCase(), "close", "a response needs a length or a close");
      await until(() => this.closed, "close-framed response", server);
      length = this.bytes.length - start;
    }
    const body = this.bytes.slice(start, start + length);
    this.bytes = this.bytes.slice(start + length);
    return { status, headers, body };
  }

  destroy() {
    this.socket.destroy();
  }
}

class Server {
  constructor(mode = "threaded", ignoreTerm = false) {
    const setup = `trap - TERM INT; ${ignoreTerm ? 'trap "" TERM; ' : ''}exec "$1" "$2"`;
    this.child = spawn("sh", ["-c", setup, "http-shutdown-child", executable, mode], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    this.stdout = "";
    this.stderr = "";
    this.clients = [];
    this.child.stdout.on("data", (bytes) => { this.stdout += bytes; });
    this.child.stderr.on("data", (bytes) => { this.stderr += bytes; });
    this.exited = false;
    this.exit = new Promise((resolve, reject) => {
      this.child.once("error", reject);
      this.child.once("exit", (code, signal) => {
        this.exited = true;
        resolve({ code, signal });
      });
    });
  }

  async ready() {
    await until(() => /^ready 127\.0\.0\.1:\d+$/m.test(this.stdout) || this.exited, "server readiness", this);
    const address = /^ready 127\.0\.0\.1:(\d+)$/m.exec(this.stdout);
    assert(address, `server exited before readiness\n${this.stderr}`);
    this.port = Number(address[1]);
    this.idle = await this.connect();
    this.idle.write("GET /health HTTP/1.1\r\nHost: loopback\r\n\r\n");
    const response = await this.idle.response(this);
    assert.equal(response.status, "HTTP/1.1 200 OK");
    assert.equal(response.body, "ok");
    assert.notEqual(response.headers.connection?.toLowerCase(), "close", "health must leave an idle connection");
    return this;
  }

  async connect() {
    const client = await Client.connect(this.port);
    this.clients.push(client);
    return client;
  }

  async hold(close = false) {
    const active = await this.connect();
    active.write(`POST /hold HTTP/1.1\r\nHost: loopback\r\nContent-Length: 1\r\n${close ? "Connection: close\r\n" : ""}\r\n`);
    await until(() => this.stdout.includes("entered /hold\n") || this.exited, "in-flight request", this);
    assert(!this.exited, `server stopped before entering its handler\n${this.stderr}`);
    return active;
  }

  signal(signal) {
    assert(!this.exited, "signal must target a live child");
    this.child.kill(signal);
  }

  async finished() {
    await until(() => this.exited, "server exit", this);
    const exit = await this.exit;
    assert.deepEqual(exit, { code: 0, signal: null }, this.stderr);
    assert(this.stdout.includes("finished\n"), "serve did not return success");
  }

  async cleanup() {
    for (const client of this.clients) client.destroy();
    if (!this.exited) this.child.kill("SIGKILL");
    await this.exit;
  }
}

async function draining(signal) {
  const server = new Server();
  try {
    await server.ready();
    const active = await server.hold();
    server.signal(signal);
    await until(() => server.idle.closed, "idle connection closing during drain", server);
    assert(!server.exited, "shutdown abandoned the in-flight body");
    let newcomer = null;
    try {
      newcomer = await server.connect();
      newcomer.write("GET /new HTTP/1.1\r\nHost: loopback\r\n\r\n");
    } catch (error) {
      assert(["ECONNREFUSED", "ECONNRESET"].includes(error.code), String(error));
    }
    active.write("x");
    const response = await active.response(server);
    assert.equal(response.status, "HTTP/1.1 200 OK");
    assert.equal(response.body, "ok");
    assert.equal(response.headers.connection?.toLowerCase(), "close");
    await server.finished();
    assert(!server.stdout.includes("entered /new\n"), "accepted a new request while draining");
    if (newcomer) {
      await until(() => newcomer.closed, "new connection closing", server);
      assert.equal(newcomer.bytes, "", "answered a new connection while draining");
    }
    console.log(`${signal} drains in-flight, closes idle and refuses newcomers: ok`);
  } finally {
    await server.cleanup();
  }
}

async function queuedReady() {
  const server = new Server("queued");
  try {
    await server.ready();
    // Register a second idle connection before occupying the only worker, so
    // the next request is readiness on an existing reader, not a new accept.
    const queued = await server.connect();
    queued.write("GET /health HTTP/1.1\r\nHost: loopback\r\n\r\n");
    assert.equal((await queued.response(server)).body, "ok");
    const active = await server.hold();
    queued.write("GET /queued HTTP/1.1\r\nHost: loopback\r\n\r\n");
    await delay(50);
    assert(!server.stdout.includes("entered /queued\n"), "the queued request bypassed the occupied worker");
    assert.equal(queued.bytes, "", "the queued request was answered before shutdown");
    server.signal("SIGTERM");
    await until(() => server.idle.closed, "idle reader closing beside queued work", server);
    assert(!server.exited, "shutdown abandoned the current and queued requests");
    active.write("x");
    const first = await active.response(server);
    const second = await queued.response(server);
    for (const response of [first, second]) {
      assert.equal(response.status, "HTTP/1.1 200 OK");
      assert.equal(response.headers.connection?.toLowerCase(), "close");
      assert.equal(response.body, "ok");
    }
    await server.finished();
    assert.equal(server.stdout.split("\n").filter((line) => line === "entered /queued").length, 1);
    console.log("queued-ready requests finish beside the in-flight request during shutdown: ok");
  } finally {
    await server.cleanup();
  }
}

async function secondSignal() {
  const server = new Server();
  try {
    await server.ready();
    await server.hold();
    server.signal("SIGTERM");
    await until(() => server.idle.closed, "first-signal drain", server);
    assert(!server.exited, "first signal abandoned the request");
    server.signal("SIGTERM");
    await until(() => server.exited, "default second-signal action", server);
    assert.deepEqual(await server.exit, { code: null, signal: "SIGTERM" });
    assert(!server.stdout.includes("finished\n"));
    console.log("second SIGTERM uses the restored termination action: ok");
  } finally {
    await server.cleanup();
  }
}

async function manual() {
  const server = new Server("manual");
  try {
    await server.ready();
    server.signal("SIGTERM");
    await until(() => server.exited, "manual signal action", server);
    assert.deepEqual(await server.exit, { code: null, signal: "SIGTERM" });
    assert(!server.stdout.includes("finished\n"));
    console.log("Manual leaves the default signal action unchanged: ok");
  } finally {
    await server.cleanup();
  }
}

async function ignored() {
  const server = new Server("threaded", true);
  try {
    await server.ready();
    server.signal("SIGTERM");
    server.idle.write("GET /health HTTP/1.1\r\nHost: loopback\r\n\r\n");
    const response = await server.idle.response(server);
    assert.equal(response.status, "HTTP/1.1 200 OK");
    assert.equal(response.body, "ok");
    assert(!server.exited, "an ignored signal stopped serving");
    server.signal("SIGINT");
    await server.finished();
    console.log("an inherited ignored SIGTERM keeps serving: ok");
  } finally {
    await server.cleanup();
  }
}

async function ownRegistration() {
  const server = new Server("own");
  try {
    await server.ready();
    server.signal("SIGTERM");
    await server.finished();
    assert(server.stdout.includes("own-signal true\n"), "the application's own registration did not wake");
    console.log("the application's own signal registration wakes beside the server's: ok");
  } finally {
    await server.cleanup();
  }
}

async function sequential() {
  const server = new Server("sequential");
  try {
    await server.ready();
    const active = await server.hold();
    server.signal("SIGTERM");
    await delay(50);
    assert(!server.exited, "sequential shutdown abandoned its current handler");
    assert.equal(active.bytes, "", "answered before the request body arrived");
    active.write("x");
    const response = await active.response(server);
    assert.equal(response.status, "HTTP/1.1 200 OK");
    assert.equal(response.body, "ok");
    assert.equal(response.headers["content-length"], "2");
    assert.notEqual(response.headers.connection?.toLowerCase(), "close");
    await server.finished();
    await until(() => active.closed, "sequential active close", server);
    await until(() => server.idle.closed, "sequential idle close", server);
    console.log("Sequential finishes its current request before stopping: ok");
  } finally {
    await server.cleanup();
  }
}

try {
  await draining("SIGTERM");
  await draining("SIGINT");
  await queuedReady();
  await secondSignal();
  await manual();
  await ignored();
  await ownRegistration();
  await sequential();
} catch (error) {
  console.error(error.stack ?? error);
  process.exitCode = 1;
}
