#ifndef LINEA_NET_H
#define LINEA_NET_H

/* Every result is a non-negative value or a negated errno, captured
 * immediately, matching io.h's scalar ABI. An IPv4 address crosses the
 * boundary packed into one integer: host-order address in the high bits,
 * port in the low 16, so no socket extern takes a memory address. */
long linea_net_listen(unsigned long address, unsigned long backlog);
long linea_net_accept(int listener);
long linea_net_connect(unsigned long address);
long linea_net_local_address(int fd);
/* -ECONNRESET when the connection was torn down and has no peer left. */
long linea_net_peer_address(int fd);
/* Milliseconds; 0 means no timeout. */
long linea_net_set_timeouts(int fd, unsigned long read_ms, unsigned long write_ms);
long linea_net_shutdown_write(int fd);
/* Close with SO_LINGER {on, 0}, so the peer receives a reset rather than an
 * orderly end of input. The descriptor is closed even when lingering cannot
 * be configured, and that failure is the one reported. */
long linea_net_reset(int fd);

#endif
