// Every socket and process belongs to this acceptance run on loopback.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import net from "node:net";
import path from "node:path";

const executable = path.resolve(process.argv[2]);
const deadlineMs = 10000;
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(test, description, server) {
  const deadline = Date.now() + deadlineMs;
  while (!test()) {
    if (Date.now() >= deadline) throw new Error(`timed out: ${description}\n${server.stdout}${server.stderr}`);
    await delay(5);
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
  constructor(mode) {
    this.child = spawn(executable, [mode], { stdio: ["ignore", "pipe", "pipe"] });
    this.stdout = "";
    this.stderr = "";
    this.clients = [];
    this.exited = false;
    this.child.stdout.on("data", (bytes) => { this.stdout += bytes; });
    this.child.stderr.on("data", (bytes) => { this.stderr += bytes; });
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
  }
  async connect() {
    const client = await Client.connect(this.port);
    this.clients.push(client);
    return client;
  }
  entered(path) {
    return this.stdout.split("\n").filter((line) => line === `entered ${path}`).length;
  }
  async finished() {
    await until(() => this.exited, "server exit", this);
    assert.deepEqual(await this.exit, { code: 0, signal: null }, this.stderr);
    assert.equal(this.stderr, "", "the server reported a failure");
  }
  async cleanup() {
    for (const client of this.clients) client.destroy();
    if (!this.exited) this.child.kill("SIGKILL");
    await this.exit;
  }
}

const request = (method, target, { length, close = false } = {}) =>
  `${method} ${target} HTTP/1.1\r\nHost: loopback\r\n${length === undefined ? "" : `Content-Length: ${length}\r\n`}${close ? "Connection: close\r\n" : ""}\r\n`;

async function run(mode, test) {
  const server = new Server(mode);
  try {
    await server.ready();
    await test(server);
    await server.finished();
  } finally {
    await server.cleanup();
  }
}

await run("partial", async (server) => {
  const client = await server.connect();
  client.write(request("POST", "/prefix", { length: 6 }) + "abcdef" + request("GET", "/close", { close: true }));
  const first = await client.response(server);
  const second = await client.response(server);
  assert.equal(first.status, "HTTP/1.1 200 OK");
  assert.equal(first.headers["content-length"], "2");
  assert.equal(first.body, "ab");
  assert.equal(second.status, "HTTP/1.1 200 OK");
  assert.equal(second.headers.connection, "close");
  assert.equal(second.body, "ok");
  assert.equal(client.bytes, "", "body bytes leaked past the two framed responses");
});
console.log("unread body bytes are drained before the next pipelined request: ok");

const residualCapacities = [];
for (const length of [100000, 131072]) {
  await run("streaming", async (server) => {
    const client = await server.connect();
    client.write(request("POST", "/whole", { length, close: true }));
    await until(() => server.entered("/whole") === 1 || server.exited, "streaming handler entering before body data", server);
    assert(!server.exited, "the server tried to collect the upload before its handler ran");
    const chunk = Buffer.alloc(4096, 97);
    for (let sent = 0; sent < length; sent += chunk.length) {
      await new Promise((resolve, reject) => {
        client.socket.write(chunk.subarray(0, Math.min(chunk.length, length - sent)), (error) => error ? reject(error) : resolve());
      });
    }
    const response = await client.response(server);
    assert.equal(response.status, "HTTP/1.1 200 OK");
    assert.equal(response.headers.connection, "close");
    assert.equal(response.body, `read ${length}`);
    await until(() => /arena remaining \d+\n/.test(server.stdout) || server.exited, "arena residual capacity", server);
    const remaining = /arena remaining (\d+)\n/.exec(server.stdout);
    assert(remaining, "streaming handler did not report its remaining arena capacity");
    residualCapacities.push(Number(remaining[1]));
  });
}
assert(residualCapacities.every((remaining) => remaining > 0), "streaming exhausted the request arena");
assert.equal(residualCapacities[0], residualCapacities[1], "a larger streamed body consumed more arena storage");
console.log("100000- and 131072-byte network bodies leave identical positive arena capacity: ok");

for (const target of ["/ignore", "/whole"]) {
  await run("oversized", async (server) => {
    const client = await server.connect();
    client.write(request("POST", target, { length: 9 }) + "abcdefghi");
    const response = await client.response(server);
    assert.equal(response.status, "HTTP/1.1 413 Content Too Large");
    assert.equal(response.headers.connection, "close");
    assert.equal(server.entered(target), 0, "an oversized body reached its handler");
  });
}
console.log("oversized bodies are refused for ignoring and consuming handlers: ok");

await run("deadline", async (server) => {
  const client = await server.connect();
  client.write(request("POST", "/whole", { length: 6 }) + "ab");
  await until(() => server.entered("/whole") === 1 || server.exited, "body reader entering", server);
  // Each byte arrives within the per-read bound, but finishing all six bytes
  // would exceed the request's original deadline.
  const trickle = setInterval(() => { if (!client.closed) client.write("x"); }, 25);
  try {
    const response = await client.response(server);
    assert.equal(response.status, "HTTP/1.1 408 Request Timeout");
    assert.equal(response.headers.connection, "close");
  } finally {
    clearInterval(trickle);
  }
});
console.log("a stalled partial body reaches its request deadline: ok");

await run("queued_deadline", async (server) => {
  const active = await server.connect();
  active.write(request("GET", "/hold", { close: true }));
  await until(() => server.entered("/hold") === 1, "the only worker entering its held handler", server);
  const queued = await server.connect();
  queued.write(request("POST", "/ignore", { length: 1 }) + "x");
  // The dispatcher can observe this reader while its only worker is occupied.
  // Waiting beyond the read deadline must not turn queued data into silence.
  await delay(120);
  assert.equal(active.bytes, "", "the held handler ended before its queued peer expired");
  assert.equal(server.entered("/ignore"), 0, "the queued request bypassed the occupied worker");
  const first = await active.response(server);
  assert.equal(first.status, "HTTP/1.1 200 OK");
  assert.equal(first.body, "ok");
  const second = await queued.response(server);
  assert.equal(second.status, "HTTP/1.1 408 Request Timeout");
  assert.equal(second.headers.connection, "close");
  await until(() => queued.closed, "the expired queued reader closing after its refusal", server);
  assert.equal(queued.error, null, "the queued refusal reset its connection");
  assert.equal(queued.bytes, "", "an expired queued request produced another response");
  assert.equal(server.entered("/ignore"), 0, "an expired request reached its handler");
});
console.log("a request expiring in the worker queue receives 408 before closing: ok");

await run("eviction", async (server) => {
  const oldest = await server.connect();
  oldest.write(request("GET", "/keep"));
  const first = await oldest.response(server);
  assert.equal(first.body, "ok");
  assert.notEqual(first.headers.connection, "close");
  const newer = await server.connect();
  newer.write(request("GET", "/keep"));
  assert.equal((await newer.response(server)).body, "ok");
  const newcomer = await server.connect();
  newcomer.write(request("GET", "/close", { close: true }));
  assert.equal((await newcomer.response(server)).body, "ok");
  await until(() => oldest.closed, "oldest idle connection eviction", server);
  assert.equal(oldest.error, null, "eviction reset a fully consumed connection");
  assert(!newer.closed, "the newer idle reader was evicted");
  newer.write(request("GET", "/close", { close: true }));
  assert.equal((await newer.response(server)).body, "ok");
});
console.log("a newcomer evicts the oldest idle connection: ok");

await run("backpressure", async (server) => {
  const first = await server.connect();
  first.write(request("POST", "/block", { length: 1, close: true }));
  await until(() => server.entered("/block") === 1, "first active request", server);
  const second = await server.connect();
  second.write(request("POST", "/block", { length: 1, close: true }));
  await until(() => server.entered("/block") === 2, "second active request", server);
  const queued = await server.connect();
  queued.write(request("GET", "/close", { close: true }));
  // Three workers are available but only two open connections are permitted.
  // A spare worker could answer this immediately if the budget were ignored.
  await delay(120);
  assert.equal(server.entered("/close"), 0, "a newcomer exceeded the connection budget");
  assert.equal(queued.bytes, "", "a backpressured newcomer was answered early");
  assert(!first.closed && !second.closed, "an active request was evicted");
  first.write("x");
  assert.equal((await first.response(server)).body, "read 1");
  assert.equal((await queued.response(server)).body, "ok");
  assert(!second.closed, "making room abandoned the other active request");
  second.write("y");
  assert.equal((await second.response(server)).body, "read 1");
});
console.log("active connections enforce backpressure without eviction: ok");

async function http10Closes() {
  await run("http10", async (server) => {
    const client = await server.connect();
    client.write("GET /keep HTTP/1.0\r\nHost: loopback\r\nConnection: keep-alive\r\n\r\n" + request("GET", "/close", { close: true }));
    const response = await client.response(server);
    assert.equal(response.status, "HTTP/1.1 200 OK");
    assert.equal(response.headers.connection, "close");
    assert.equal(response.body, "ok");
    await until(() => client.closed, "HTTP/1.0 connection close", server);
    assert.equal(client.bytes, "", "HTTP/1.0 produced a second pipelined response");
    assert.equal(server.entered("/keep"), 1);
    assert.equal(server.entered("/close"), 0, "HTTP/1.0 served a pipelined request");
  });
  console.log("HTTP/1.0 closes even when keep-alive is requested: ok");
}

async function refusedFraming(headers, status = "400 Bad Request", line = "POST /ignore HTTP/1.1", host = "Host: loopback\r\n") {
  await run("framing", async (server) => {
    const client = await server.connect();
    client.write(line + "\r\n" + host + headers + "\r\nabc" + request("GET", "/close", { close: true }));
    // End only the client's write half: the refusal must still arrive before
    // the server closes, without waiting for an artificial linger timeout.
    client.socket.end();
    await until(() => client.closed, "refused connection closing", server);
    const responseCount = (client.bytes.match(/HTTP\/1\.[01] /g) ?? []).length;
    const response = await client.response(server);
    assert.equal(response.status, `HTTP/1.1 ${status}`);
    assert.equal(response.headers.connection, "close");
    assert.equal(responseCount, 1, "a refusal answered a second pipelined request");
    assert.equal(client.bytes, "");
    assert.equal(server.entered("/ignore"), 0, "invalid framing reached a handler");
    assert.equal(server.entered("/close"), 0, "a refusal reused its connection");
  });
}

async function lengthHeaders() {
  await run("agreeing-lengths", async (server) => {
    const client = await server.connect();
    client.write("POST /ignore HTTP/1.1\r\nHost: loopback\r\nContent-Length: 3\r\nContent-Length: 03\r\n\r\nabc" + request("GET", "/close", { close: true }));
    const first = await client.response(server);
    const second = await client.response(server);
    assert.equal(first.status, "HTTP/1.1 200 OK");
    assert.equal(first.headers["content-length"], "2");
    assert.equal(first.body, "ok");
    assert.equal(second.status, "HTTP/1.1 200 OK");
    assert.equal(second.headers.connection, "close");
    assert.equal(second.body, "ok");
    assert.equal(client.bytes, "");
    assert.equal(server.entered("/ignore"), 1);
    assert.equal(server.entered("/close"), 1);
  });
  for (const headers of [
    "Content-Length: 3\r\nContent-Length: 4\r\n",
    "Content-Length: 3x\r\n",
    "Content-Length: 3, 3\r\n",
    "Content-Length: \r\n",
  ]) {
    await refusedFraming(headers);
  }
  console.log("agreeing lengths preserve boundaries; malformed and disagreeing lengths close with 400: ok");
}

async function transferEncodingConflict() {
  await refusedFraming("Content-Length: 3\r\nTransfer-Encoding: chunked\r\n");
  console.log("Transfer-Encoding beside Content-Length closes with 400 and no pipeline reuse: ok");
}

async function foldedHeader() {
  await refusedFraming("Content-Length: 3\r\nX-Test: value\r\n continuation: value\r\n");
  console.log("a folded header closes with 400 and no pipeline reuse: ok");
}

await http10Closes();
await lengthHeaders();
await transferEncodingConflict();
await foldedHeader();

for (const [headers, status, line, host] of [
  ["", "414 URI Too Long", `GET /${"a".repeat(1024)} HTTP/1.1`],
  [`X-Long: ${"a".repeat(1024)}\r\n`, "431 Request Header Fields Too Large"],
  ["X: a\r\n".repeat(8), "431 Request Header Fields Too Large"],
  ["", "505 HTTP Version Not Supported", "GET /ignore HTTP/2.0"],
  ["Transfer-Encoding: chunked\r\n", "501 Not Implemented"],
  ["", "400 Bad Request", "GET  /ignore HTTP/1.1"],
  ["", "400 Bad Request", "GET /ignore HTTP/no"],
  ["X : value\r\n", "400 Bad Request"],
  ["No-Colon\r\n", "400 Bad Request"],
  [": empty\r\n", "400 Bad Request"],
  ["X: bare\rcarriage\r\n", "400 Bad Request"],
  ["\vX: value\r\n", "400 Bad Request"],
  ["", "400 Bad Request", "GET /ignore HTTP/1.1", ""],
  ["Host: other\r\n", "400 Bad Request"],
  ["", "400 Bad Request", "GET /ignore HTTP/1.1", "Host: \r\n"],
  ["", "400 Bad Request", "GET /ignore HTTP/1.1", "Host: example/path\r\n"],
  ["", "400 Bad Request", "GET /ignore HTTP/1.1", "Host: user@example\r\n"],
  ["", "400 Bad Request", "GET /ignore HTTP/1.1", "Host: example:65536\r\n"],
  ["", "400 Bad Request", "GET /ignore HTTP/1.1", "Host: [1:2:3]\r\n"],
  ["Content-Length: 18446744073709551616\r\n", "413 Content Too Large"],
]) {
  await refusedFraming(headers, status, line, host);
}
console.log("request-line, header, Host, version, length and transfer-coding refusals close without pipeline reuse: ok");
