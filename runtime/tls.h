#ifndef LINEA_TLS_H
#define LINEA_TLS_H

#include <stdint.h>

/* TLS through rustls. The runtime never touches a socket here: a session
 * takes the ciphertext its peer sent through `linea_tls_receive` and hands
 * out the ciphertext to send through `linea_tls_transmit`, so the standard
 * library carries both over whatever byte stream it was given.
 *
 * A configuration and a session are the addresses of rustls objects, written
 * to `*config` or `*session`. Every call answering `long` answers a
 * non-negative value, or a negated rustls result code (7000 and up) or a
 * negated `linea_tls_*` code below.
 *
 * `roots_at` holds the PEM certificates a client trusts instead of the
 * operating system's roots, or none to trust the system's, `chain_at`
 * a PEM certificate chain and `key_at` its PEM private key; an extent of 0
 * means none. `alpn_at` holds the protocols in preference order, separated by
 * commas. */
long linea_tls_client_config(unsigned long roots_at, unsigned long roots_len, uint8_t verify, unsigned long chain_at, unsigned long chain_len, unsigned long key_at, unsigned long key_len, unsigned long alpn_at, unsigned long alpn_len, unsigned long *config);
/* `client_auth` is 0 to ask no client for a certificate, 1 to verify one a
 * client offers against the PEM roots `clients_at` and accept a client with
 * none, and 2 to require one. */
long linea_tls_server_config(unsigned long chain_at, unsigned long chain_len, unsigned long key_at, unsigned long key_len, unsigned long clients_at, unsigned long clients_len, uint8_t client_auth, unsigned long alpn_at, unsigned long alpn_len, unsigned long *config);
void linea_tls_client_config_free(unsigned long config);
void linea_tls_server_config_free(unsigned long config);

/* A session holds what it needs of its configuration, so the configuration
 * may be freed while the session lives. `name_at` is the server's name as
 * the certificate must state it, a DNS name or an IP address, not
 * NUL-terminated. */
long linea_tls_client_open(unsigned long config, unsigned long name_at, unsigned long name_len, unsigned long *session);
long linea_tls_server_open(unsigned long config, unsigned long *session);

/* Hands the session the `len` bytes of ciphertext at `at` and processes
 * them; answers how many it took, which is all of them unless an error is
 * answered. An error leaves any alert to the peer waiting for
 * `linea_tls_transmit`. */
long linea_tls_receive(unsigned long session, unsigned long at, unsigned long len);
/* Writes up to `cap` bytes of ciphertext waiting to be sent to `at` and
 * answers how many. */
long linea_tls_transmit(unsigned long session, unsigned long at, unsigned long cap);
/* The session's state, a set of `linea_tls_state` bits. */
uint8_t linea_tls_state(unsigned long session);
/* Reads up to `cap` bytes of plaintext the peer sent. Answers how many, 0
 * once the peer ended the stream with close_notify, or -LINEA_TLS_EMPTY when
 * nothing is waiting yet. */
long linea_tls_read(unsigned long session, unsigned long at, unsigned long cap);
/* Whether a read would answer without more ciphertext: 1 when plaintext is
 * waiting, the peer sent close_notify or the session failed, else 0. A byte
 * it reads to find out is answered by the next read. */
uint8_t linea_tls_pending(unsigned long session);
/* Takes up to `len` bytes of plaintext to send and answers how many; fewer
 * once the session's buffer holds `linea_tls_buffer_limit` bytes unsent. */
long linea_tls_write(unsigned long session, unsigned long at, unsigned long len);
/* Queues the close_notify alert. */
void linea_tls_close_notify(unsigned long session);
/* Writes the protocol the handshake agreed on to `at` and answers its
 * length, 0 for none. */
long linea_tls_alpn(unsigned long session, unsigned long at, unsigned long cap);
void linea_tls_free(unsigned long session);

/* What a result code means, one of `linea_tls_reason`. */
uint8_t linea_tls_reason(long code);

enum linea_tls_state {
    LINEA_TLS_HANDSHAKING = 1,
    LINEA_TLS_WANTS_READ = 2,
    LINEA_TLS_WANTS_WRITE = 4,
    LINEA_TLS_RESUMED = 8,
};

enum linea_tls_reason {
    LINEA_TLS_REASON_PROTOCOL = 0,
    LINEA_TLS_REASON_EXPIRED = 1,
    LINEA_TLS_REASON_UNKNOWN_ISSUER = 2,
    LINEA_TLS_REASON_WRONG_NAME = 3,
    LINEA_TLS_REASON_BAD_CERTIFICATE = 4,
    LINEA_TLS_REASON_PEER_REFUSED = 5,
    LINEA_TLS_REASON_NO_CERTIFICATE = 6,
    LINEA_TLS_REASON_NO_PROTOCOL = 7,
    LINEA_TLS_REASON_TRUNCATED = 8,
    LINEA_TLS_REASON_INVALID_INPUT = 9,
};

/* Codes of the runtime's own, outside rustls's range. */
enum linea_tls_code {
    LINEA_TLS_EMPTY = 1,
    LINEA_TLS_INVALID_INPUT = 2,
    LINEA_TLS_TOO_MANY_NAMES = 3,
    LINEA_TLS_OUT_OF_MEMORY = 4,
};

/* The most plaintext and ciphertext a session holds unsent, in bytes. */
#define LINEA_TLS_BUFFER_LIMIT 65536

#endif
