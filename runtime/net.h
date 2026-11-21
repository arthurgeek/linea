#ifndef LINEA_NET_H
#define LINEA_NET_H

/* Every result is a non-negative value or a negated errno, captured
 * immediately, matching io.h's scalar ABI. An IPv4 address crosses the
 * boundary packed into one integer: host-order address in the high bits,
 * port in the low 16, so no socket extern takes a memory address. */
long linea_net_listen(unsigned long address, unsigned long backlog);
/* Inside a simulation (`sim.h`) every operation is answered by the
 * simulation; otherwise every socket is nonblocking and waits through its
 * execution backend. A deadline
 * is the monotonic clock's reading in nanoseconds, 0 for none. A deadline that
 * has passed answers -ETIMEDOUT without attempting the operation. */
long linea_net_accept(int listener, unsigned long deadline_ns);
long linea_net_connect(unsigned long address, unsigned long deadline_ns);
/* A read answers its count, 0 at the peer's end of input; a write answers how
 * many bytes it sent, which may be fewer than `len`. */
long linea_net_read(int fd, unsigned long at, unsigned long len, unsigned long deadline_ns);
long linea_net_write(int fd, unsigned long at, unsigned long len, unsigned long deadline_ns);
long linea_net_local_address(int fd);
/* -ECONNRESET when the connection was torn down and has no peer left. */
long linea_net_peer_address(int fd);
long linea_net_shutdown_write(int fd);
/* Close with SO_LINGER {on, 0}, so the peer receives a reset rather than an
 * orderly end of input. The descriptor is closed even when lingering cannot
 * be configured, and that failure is the one reported. */
long linea_net_reset(int fd);
/* The first IPv4 address the system's resolver gives for the `len` bytes of
 * a host name at `at`, packed with port 0, or a negated errno: -ENOENT when
 * the name has no IPv4 address, -ENAMETOOLONG past 253 bytes, -EINVAL for a
 * name holding a NUL, and -EIO when the resolver failed for another reason.
 * The lookup blocks the calling thread. Inside a simulation only a dotted
 * IPv4 literal resolves, so a simulated run never consults the network. */
long linea_net_resolve(unsigned long at, unsigned long len);
/* Close a socket, or a simulated descriptor (`sim.h`). */
long linea_net_close(int fd);

#endif
