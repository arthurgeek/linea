#ifndef LINEA_TLS_OPS_H
#define LINEA_TLS_OPS_H

/* What `tls.c`, the sessions, and `tls_config.c`, the configurations, share.
 *
 * A session reaches rustls only through the `tls_ops` table its
 * configuration hands it, never by naming a rustls function. So `tls.o`
 * holds no reference to rustls, and only `tls_config.o`, which a program
 * links only when it builds a configuration, pulls rustls's archive members
 * into the link: a program whose code merely could open a session, such as
 * a plain HTTP server, links no rustls code. */

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include <rustls.h>

struct tls_ops {
    rustls_result (*client_connection_new)(const struct rustls_client_config *, const char *, struct rustls_connection **);
    rustls_result (*server_connection_new)(const struct rustls_server_config *, struct rustls_connection **);
    void (*set_buffer_limit)(struct rustls_connection *, size_t);
    rustls_io_result (*read_tls)(struct rustls_connection *, rustls_read_callback, void *, size_t *);
    rustls_io_result (*write_tls)(struct rustls_connection *, rustls_write_callback, void *, size_t *);
    rustls_result (*process_new_packets)(struct rustls_connection *);
    bool (*wants_read)(const struct rustls_connection *);
    bool (*wants_write)(const struct rustls_connection *);
    bool (*is_handshaking)(const struct rustls_connection *);
    enum rustls_handshake_kind (*handshake_kind)(const struct rustls_connection *);
    rustls_result (*read)(struct rustls_connection *, uint8_t *, size_t, size_t *);
    rustls_result (*write)(struct rustls_connection *, const uint8_t *, size_t, size_t *);
    void (*send_close_notify)(struct rustls_connection *);
    void (*get_alpn_protocol)(const struct rustls_connection *, const uint8_t **, size_t *);
    void (*connection_free)(struct rustls_connection *);
};

/* The most distinct server names one client configuration keeps. */
#define LINEA_TLS_MAX_NAMES 1024

/* A client configuration and the server names its connections were opened
 * for. rustls-ffi 0.15 hands rustls the name a client connection is opened
 * with without copying it, and rustls keeps it as the key of the session it
 * caches in the configuration, so each name lives as long as the
 * configuration and every connection opened from it: the last of those to
 * be freed frees the names. A name is kept once, in a hash set, and only
 * once a connection opened with it; at most `LINEA_TLS_MAX_NAMES` are kept,
 * and an open naming a server past that is refused. */
struct client_config {
    const struct rustls_client_config *config;
    const struct tls_ops *ops;
    pthread_mutex_t lock;
    /* An open-addressed set of names, `cap` slots, a power of two. */
    char **names;
    size_t cap;
    size_t count;
    /* The configuration's own reference and one per open connection. */
    size_t refs;
};

struct server_config {
    const struct rustls_server_config *config;
    const struct tls_ops *ops;
};

/* Drop one reference to `held`, freeing the names and the record with the
 * last. The rustls configuration is freed apart, by its own free. */
static inline void tls_config_release(struct client_config *held) {
    pthread_mutex_lock(&held->lock);
    held->refs -= 1;
    const bool last = held->refs == 0;
    pthread_mutex_unlock(&held->lock);
    if (!last) return;
    for (size_t i = 0; i < held->cap; i += 1) free(held->names[i]);
    free(held->names);
    pthread_mutex_destroy(&held->lock);
    free(held);
}

#endif
