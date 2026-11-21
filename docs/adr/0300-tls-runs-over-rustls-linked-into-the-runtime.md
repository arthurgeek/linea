# 300. TLS runs over rustls, linked into the runtime, and drives any transport from Linea

Status: Accepted — 2026-11-20. Extends
[0154](0154-sockets-and-http-follow-go.md), and
[0299](0299-a-deadline-is-an-absolute-moment-passed-explicitly.md), whose
deadline bounds a handshake.

## Context

The standard library had sockets and an HTTP server and no way to encrypt
either. A program serving HTTPS, calling an HTTPS API or authenticating a peer
by certificate had nowhere to start. Writing TLS is not an option: the
protocol and the X.509 path validation under it are where most of the
security bugs of the field live, and a language whose promise is that an
accepted program has no undefined behaviour cannot rest that promise on a TLS
stack of its own.

rustls is a TLS 1.2 and 1.3 implementation in safe Rust, with its X.509
verification in webpki, and `rustls-ffi` exposes it to C. It is the stack
curl and Apache's `mod_tls` link. Choosing it leaves six questions: how the
library is pinned and built on every machine CI and a developer use, how the
operating system's trusted roots are read, what Linea code is allowed to
touch, what the API says, how a failure is reported, and how the HTTP server
serves over it.

## Decision

### 1. rustls-ffi is pinned through `flake.lock` and appended to the runtime archive

The development shell names nixpkgs' `rustls-ffi` (0.15.3, with rustls 0.23.39
and the aws-lc-rs crypto provider) in `LINEA_RUSTLS`. nixpkgs pins its source
by tag and hash and its vendored crates by hash, and `flake.lock` pins
nixpkgs, so the archive a machine links is fixed by the lock file. The binary
cache serves that build for `aarch64-darwin`, `x86_64-linux` and
`aarch64-linux`, so neither CI nor a developer compiles Rust.

`build.zig` compiles `runtime/tls.c` and `runtime/tls_config.c` against the
package's `rustls.h`, adds their objects to both runtime archives, and
appends the members of `librustls.a` to each with `ar qL`. A program links
one runtime archive as before, and the linker takes an archive member only
when something the program links calls it. `tls_config.o` builds
configurations and is the one object that names rustls functions; it hands
each configuration a table of the rustls connection functions
(`runtime/tls_ops.h`), and `tls.o`, the sessions, calls rustls only through
that table. So only a program that builds a configuration links rustls: a
plain HTTP server, whose serving code could open a TLS session, links
`tls.o` and none of rustls (a transcript holds it to naming no rustls
symbol), and a program that never mentions `std.tls` links neither. The driver's link names the system libraries
rustls needs after the runtime: on macOS the Security and CoreFoundation
frameworks and iconv, behind `-dead_strip_dylibs`; on Linux the unwinder,
`libdl`, `librt` and `libutil`, behind `--as-needed`. Both flags drop a
library no linked object uses, so a program without TLS loads none of them.

`build.zig` refuses to configure without `LINEA_RUSTLS`, naming the shell.
`zig build test-native-tls` links `runtime/tls.c`, `runtime/tls_config.c`,
the runtime's byte-range check and `runtime/tls_test.c` against the archive
with the C toolchain and runs a handshake, a refused name, ALPN, resumption,
client certificates and bytes after close_notify in memory; the unfiltered
test runs it with the other native suites.

### 2. The operating system's roots are read by rustls-platform-verifier

A client configured with `verify: .System` and no `roots` verifies with
`rustls_platform_server_cert_verifier`, rustls-platform-verifier's verifier.
On macOS it asks the Security framework (`SecTrust`), so the keychains, the
user's trust and distrust settings, constrained roots and the system's
revocation policy all apply, and the link needs the Security and
CoreFoundation frameworks. On Linux it reads the distribution's bundle
through rustls-native-certs (the file `SSL_CERT_FILE` names, else the bundle
paths of the common distributions and the directory `SSL_CERT_DIR` names)
and verifies with webpki; it needs nothing beyond a bundle, which every
distribution's `ca-certificates` package and the Nix shell's
`SSL_CERT_FILE` provide.

A client given `roots` trusts those PEM roots alone, verified with webpki: a
program talking to servers under a private certificate authority names that
authority, and nothing the system trusts can stand in for it. Roots are not
added to the system's: rustls-ffi 0.15 offers no way to add roots to the
platform verifier, and the alternative, webpki over the system's PEM bundle
and the extra roots, would quietly lower trust below `.System` on macOS
(dropping the keychain, distrust settings, constrained roots and
revocation) and let an environment variable alone pick what is trusted.
Running both verifiers and accepting what either accepts needs a callback
that can call a rustls verifier, which rustls-ffi does not offer either.

`verify: .Insecure_AcceptAnyCertificate` installs a verifier that accepts
every certificate; the handshake's signatures are still checked, so the peer
holds the key of the certificate it presents, whoever issued it. The name
says what it costs.

### 3. Linea reaches rustls only through `std.mem`'s linear handles

A rustls configuration and a rustls connection are addresses the runtime
answers. `std.mem` keeps each in a linear `TlsConfig` or `TlsSession`, as it
keeps a directory stream in `DirStream`: only `mem` builds one or reads its
field, and the runtime's table marks the parameter that takes one as held
(`Held.tls`), so [T-ExternRuntime] refuses a declaration of any of the
`linea_tls_*` symbols outside `mem`. Every symbol that takes bytes takes them
as `address.raw` of a slice or a buffer, from the free functions the
compiler's table names as passing an extent ([T-RawAddress]).

The runtime never reads or writes a transport. `linea_tls_receive` hands a
session ciphertext and `linea_tls_transmit` writes the ciphertext waiting to
be sent into a buffer; Linea code moves both over whatever stream the
connection runs on. Every call computes over the session and returns, so each
is migration-neutral, and a session works the same in a simulation, over a
socket, or over memory in a test.

rustls-ffi 0.15 hands rustls the server name a client connection is opened
with without copying it, and rustls keeps that name as the key of the
session it caches, so the runtime keeps each name a client configuration's
connections were opened for until the configuration and every connection
opened from it are freed. A name freed with its connection would leave the
cache keyed by freed memory: a later connection would miss its ticket, or
read what replaced the name. The names are a hash set, a name is kept only
once a connection opened with it, and a configuration keeps at most 1024: an
open naming a 1025th server is refused as `InvalidInput`.

TLS ends at the peer's close_notify, so the runtime takes every byte that
follows it and ignores them; before it, a session whose plaintext buffer is
full takes part of a flight, and the stream keeps the rest for its next
take. A flight is never refused for being long.

### 4. The API

```linea
pub enum Verify { System, Insecure_AcceptAnyCertificate }
pub enum ClientAuth { Unrequested, Optional, Required }

ClientConfig.open(verify: Verify = .System, roots: Str = "",
    certificate_chain: Str = "", private_key: Str = "", alpn: Str = "")
    -> Result[ClientConfig, Refusal]
ServerConfig.open(certificate_chain: Str, private_key: Str,
    client_auth: ClientAuth = .Unrequested, client_roots: Str = "", alpn: Str = "")
    -> Result[ServerConfig, Refusal]
```

Certificates and keys are PEM text: what a file holds, and what `embed`
answers. `ClientConfig.open_files` and `ServerConfig.open_files` read the same
from paths, each file at most `max_pem_bytes` (1 MiB), and fail with a
`ConfigFileError` naming the unread file or the refusal. A client presents a
certificate for mutual TLS by naming its chain and key; a server asks for
one with `client_auth` and verifies it against `client_roots`. ALPN protocols
are one comma-separated list in preference order (`"h2,http/1.1"`): a
protocol name of the IANA registry holds no comma, and one string needs no
allocation and is a constant default. Both configurations are linear, since
each owns what the runtime built, and `close` frees it; a stream keeps what it
needs of its configuration, so a configuration may be closed while streams it
opened live.

Session resumption is on and cannot be turned off: rustls keeps up to 256
sessions in each client configuration, keyed by server name, and up to 256 in
each server configuration, forgetting the oldest past that. A server's
tickets name a session in its configuration's cache, valid for a day, so a
client resumes only with the server configuration that issued its ticket.
`Stream.resumed()` says whether a handshake resumed.

```linea
pub trait Transport {
    fn receive[A: Allocator](inout self: Self, inout buffer: mem.Buffer[A],
        offset: UInt64, count: UInt64, deadline: time.Deadline)
        -> Result[UInt64, io.IoError]
    fn send(inout self: Self, bytes: mem.Slice[UInt8], deadline: time.Deadline)
        -> Result[UInt64, io.IoError]
}

Stream[S: Transport, A: Allocator = mem.SystemAllocator]
Stream.connect(config, transport, server_name: Str, deadline: time.Deadline = time.never)
    -> Result[Stream[S], OpenFailure[S]]
Stream.accept(config, transport, deadline: time.Deadline = time.never)
    -> Result[Stream[S], OpenFailure[S]]
```

A stream runs over a `Transport`, which `net.Connection` implements, and
which a test implements over memory. A transport bound by both `io.Reader`
and `io.ByteWriter` was the first choice, but each of those traits declares an
`Error`, and a type parameter bound by both can name neither ([N-Ambiguous]),
so the stream could not say what its transport's failures are. `Transport`
fixes one error, `io.IoError`, which every byte stream of the standard
library already reports. `connect` and `accept` run the handshake before they
answer, so a stream in hand has a verified peer; a failure hands the
transport back in `OpenFailure` to be closed. `accept_later_in` opens a server
stream whose handshake runs at its first read or write (§6). `_in` forms take the allocator
of the stream's two buffers, kept as byte vectors so a stream is `Owned` and
moves between tasks: one flight of ciphertext (18 KiB, a full record and what
TLS adds to it) and the agreed ALPN protocol's name (255 bytes).

A handshake is bounded by a `time.Deadline` ([ADR 0299](0299-a-deadline-is-an-absolute-moment-passed-explicitly.md)),
the one budget a program passes through a whole piece of work: `connect`
and `accept` take `deadline:`, `time.never` by default, and a stream opened
with `accept_later_in` takes one through `set_handshake_deadline` before its
first read. A deadline already passed fails as `TimedOut` before any byte is
sent; a peer that stops answering fails the read or write waiting on it as
`TimedOut` once the deadline passes. The deadline reaches the transport as an
argument of each `receive` and `send`, not as a setting on it: a connection
bounds that one operation by the earlier of the argument and its own
timeouts and deadlines and keeps those for what follows, so a handshake
bounds its writes without changing the read deadline a server gave the
connection, and generic code bounds any transport without knowing it holds
one. Once the handshake ends the stream passes `time.never`, and its reads
and writes are bounded by the transport's own settings, which
`update_transport` changes.

A stream is linear and owns its transport. `close` sends close_notify, so the
peer can tell a whole stream from one cut short, and closes the transport;
`finish` sends close_notify and hands the transport back open,
`notify_close` sends it and keeps reading, and `abandon` frees the session
without it and hands the transport back, as a peer that fails would. The
stream
implements `io.Reader`, `io.ByteWriter` and `io.Close`, so a buffered reader,
`io.write_all` or an HTTP exchange runs over it unchanged. `alpn_protocol()`
answers the agreed protocol.

### 5. A failure is a `Refusal`, and becomes an I/O error by category

```linea
pub enum Reason { Expired, UnknownIssuer, WrongName, BadCertificate,
    PeerRefused, NoCertificate, NoProtocol, Truncated, InvalidInput,
    Protocol }
pub struct Refusal { operation: io.IoOperation, reason: Reason, code: UInt64 }
pub enum TlsError { Tls(Refusal), Transport(io.IoError), Memory(mem.Oom) }
```

The runtime classifies rustls's result code (`linea_tls_reason`), and the
`Refusal` keeps the code beside the reason for whoever needs rustls's own
distinction. Opening and reading a stream answer `TlsError`. Through
`io.Reader` and `io.ByteWriter` a stream reports `TlsError.io_error()`: a
refused certificate (`Expired`, `UnknownIssuer`, `WrongName`,
`BadCertificate`, `PeerRefused`, `NoCertificate`) is `PermissionDenied`,
`Truncated` is `ConnectionReset`, `Protocol` and `InvalidInput` are
`InvalidInput`, `NoProtocol` is `Unsupported`,
refused memory is `ResourceExhausted`, and a transport failure is itself. The
rustls code is not an errno, so the I/O error's `code` is `None`. A stream
that ends without the peer's close_notify is `Truncated` and not an end of
input, since what arrived may be cut short.

### 6. `http.serve` and `listen_and_serve` take `tls:`

`http.serve`, `serve_in`, `listen_and_serve` and their `_in` and `_with`
forms take `tls: Option[borrow tls.ServerConfig] = .None`. Serving lends the
configuration: the program opens it, passes `.Some(borrow config)`, and closes
it once serving returns, which it can do only then, since every serving task
is joined before. A linear `Option[tls.ServerConfig]` could not be the
parameter, because a default of a type that must be settled is refused
([T-Default]), and no HTTPS option is worth making every plain server write
`tls: .None`.

With a configuration, the task that accepts a connection opens a server
stream over it with `Stream.accept_later_in`, which creates the session and
runs no handshake: the handshake runs at the stream's first read, on the
serving task that answers the connection, bounded by the request's read
deadline, which `ServerLink.set_read_deadline` also gives the stream's
handshake so its writes end by it too, so a slow or hostile client holds one
serving task until then and never the acceptor. A handshake that fails fails that read, and the
connection is closed as a request that could not be read. Inside serving a
connection is a `ServerLink`, the plain connection or the TLS stream over
it, so
the request parser, request bodies and response writers are the same code
over both; a response writer borrows the stream as `tls.StreamWriter`, which
writes only once the handshake has run, so no answer goes out before a
required client certificate is verified, and encrypts each write and sends its ciphertext through the connection's
writer, as `net.ConnectionWriter` borrows a connection. A stream is readable
for an idle connection's wait while rustls holds plaintext it has not
answered (`linea_tls_pending` reads one byte ahead to find out), so a
pipelined request already decrypted is not left waiting for the socket. The
default stays no TLS, and the default policy stays `.Threads(128)`.

## Consequences

- Both runtime archives grow by rustls's 17 MiB, which the build directory,
  the outcome cache's hash of the archive and an installed toolchain carry. A
  linked program grows only when it calls `std.tls`.
- `zig build` needs the development shell, or `LINEA_RUSTLS` naming a
  rustls-ffi 0.15 install; outside it the build stops at configuration with a
  message naming the shell.
- rustls's code is not instrumented by a sanitizer. The address sanitizer
  still sees every allocation rustls makes through `malloc`; the thread
  sanitizer cannot see rustls's atomics, so a race inside rustls is outside
  what the `sanitize` lane checks.
- Every HTTP server compiles the TLS branch of serving, about 5600 more
  lines of MLIR in `http-json-echo`, though it links no rustls; serving is
  not made generic over the connection, because a request body is part of
  every handler's signature, and a body typed by its connection would keep a
  handler written for plain serving from serving HTTPS.
- An upgrade of rustls-ffi is a `flake.lock` update; the runtime's table and
  the native test hold the C to the header it compiles against.

## Alternatives considered

- **OpenSSL or the platform's TLS (Secure Transport, Network.framework).**
  OpenSSL is C, and its history is the history of the bugs this choice
  avoids; the platform stacks differ per system, so one program would accept
  on macOS what it refuses on Linux.
- **rustls built from source in the flake** (a Rust toolchain in the shell
  and `cargo cbuild` on every machine). It would let the build add roots to
  the platform verifier, but every CI lane and developer would compile Rust,
  and the cache already serves the pinned build.
- **The archive beside the runtime, named at the link.** Every link site
  (`linea build`, `linea run`, the object driver, the conformance runner and
  the build's own proof programs) would have to find and name a second
  archive; appending its members to the runtime archive costs nothing at link
  time, since unreferenced members are not linked.
- **The runtime reading and writing the socket.** C would own a descriptor
  loop beside the one the standard library already has, a simulation could
  not run TLS, and a test would need a socket.
- **`Stream[S: io.Reader + io.ByteWriter]`.** Refused by [N-Ambiguous], as §4
  says.
- **ALPN as a list of `Str`.** A slice has no constant default and the
  runtime would need the list's layout; the comma-separated text costs a
  protocol name a comma, which none has.
- **`tls: Option[tls.ServerConfig]`, taken by serving.** Refused by
  [T-Default], as §6 says.
- **Serving generic over its connection type**, so a plain server never
  compiles the TLS branch. A request body is in every handler's signature,
  and typed by its connection it would split handlers into plain ones and
  TLS ones; the link-time split of §1 keeps rustls out of plain servers.
- **The acceptor running the handshake.** One client that sends its hello
  slowly would stop every other connection from being accepted.
- **A switch to turn resumption off.** rustls-ffi 0.15 exposes none for a
  client, and resumption only spares work; no request asked for a switch.

## Fixtures

The tests' certificates are in `std/tls/testdata`, made once with OpenSSL 3.6
as ECDSA P-256 keys:

```sh
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ca.key
openssl req -x509 -new -key ca.key -subj "/CN=Linea Test CA" \
  -not_before 20260101000000Z -not_after 21251231235959Z \
  -addext basicConstraints=critical,CA:TRUE \
  -addext keyUsage=critical,keyCertSign,cRLSign -out ca.pem
# each leaf: a key, a request, and a certificate the root signs
openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca.key -set_serial 0x… \
  -not_before … -not_after … -extfile <(printf 'subjectAltName=…\nextendedKeyUsage=…\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n')
```

`ca.pem` (Linea Test CA) and `other_ca.pem` (Linea Other Test CA) are valid
from 2026-01-01 to 2125-12-31. `ca.pem` issued `server.pem` (`localhost`,
`127.0.0.1`, server authentication) and `client.pem` (client
authentication), both valid as long as the root, and `expired.pem`
(`localhost`), valid from 2000-01-01 to 2001-01-01. `other_ca.pem` issued
`stranger.pem` (`localhost`) and `outsider.pem` (client authentication). Each
leaf's key is beside it as `NAME_key.pem`, in PKCS#8. The roots' keys were
deleted, so no further certificate can be signed by them; a change to the
fixtures makes a new set.
