#include "tls.h"
#include "tls_ops.h"

#include <limits.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

int linea_io_byte_range(unsigned long at, unsigned long len);

/* The bytes a program handed over at `at`, or NULL for none. Checked like
 * every extent a runtime entry reads. */
static const uint8_t *bytes_at(unsigned long at, unsigned long len, long *failed) {
    if (len == 0) return NULL;
    if (linea_io_byte_range(at, len) != 0) {
        *failed = -LINEA_TLS_INVALID_INPUT;
        return NULL;
    }
    return (const uint8_t *)(uintptr_t)at;
}

static long failure(rustls_result result) {
    return -(long)result;
}

/* A session is the rustls connection, the table it is reached through and,
 * for a client connection, the configuration whose names it holds a
 * reference to. */
struct session {
    struct rustls_connection *conn;
    const struct tls_ops *ops;
    struct client_config *owner;
    /* A plaintext byte `linea_tls_pending` read ahead, which the next read
     * answers first. */
    uint8_t peeked;
    bool holds_peeked;
    /* The peer's close_notify has been processed, so every later byte is
     * ignored. */
    bool closed;
};

static struct session *held_session(unsigned long session) {
    return (struct session *)(uintptr_t)session;
}

static long adopt(struct rustls_connection *conn, const struct tls_ops *ops, struct client_config *owner, unsigned long *session) {
    struct session *held = malloc(sizeof *held);
    if (held == NULL) {
        ops->connection_free(conn);
        if (owner != NULL) tls_config_release(owner);
        return -LINEA_TLS_OUT_OF_MEMORY;
    }
    ops->set_buffer_limit(conn, LINEA_TLS_BUFFER_LIMIT);
    held->conn = conn;
    held->ops = ops;
    held->owner = owner;
    held->peeked = 0;
    held->holds_peeked = false;
    held->closed = false;
    *session = (unsigned long)(uintptr_t)held;
    return 0;
}

/* 32-bit FNV-1a, which spreads the bytes of a server name over a slot
 * index. Each product is taken in 64 bits and cut to 32, so no unsigned
 * arithmetic wraps, which the runtime's checks would trap. */
static size_t name_hash(const uint8_t *name, size_t len) {
    uint64_t hash = 2166136261U;
    for (size_t i = 0; i < len; i += 1) {
        hash ^= name[i];
        hash = (hash * 16777619U) & 0xffffffffU;
    }
    return (size_t)hash;
}

/* The slot of `name` in the set: the slot holding it, or the empty slot it
 * would go in. The set is never full, so the probe ends. */
static size_t name_slot(const struct client_config *held, const uint8_t *name, size_t len) {
    size_t slot = name_hash(name, len) & (held->cap - 1);
    while (held->names[slot] != NULL) {
        if (strlen(held->names[slot]) == len && memcmp(held->names[slot], name, len) == 0) break;
        slot = (slot + 1) & (held->cap - 1);
    }
    return slot;
}

/* Make room for one more name, keeping the set at most half full. */
static bool names_room(struct client_config *held) {
    if (held->cap != 0 && (held->count + 1) * 2 <= held->cap) return true;
    const size_t cap = held->cap == 0 ? 8 : held->cap * 2;
    char **grown = calloc(cap, sizeof *grown);
    if (grown == NULL) return false;
    char **old = held->names;
    const size_t old_cap = held->cap;
    held->names = grown;
    held->cap = cap;
    for (size_t i = 0; i < old_cap; i += 1) {
        if (old[i] == NULL) continue;
        const size_t slot = name_slot(held, (const uint8_t *)old[i], strlen(old[i]));
        held->names[slot] = old[i];
    }
    free(old);
    return true;
}

long linea_tls_client_open(unsigned long config, unsigned long name_at, unsigned long name_len, unsigned long *session) {
    long invalid = 0;
    const uint8_t *name = bytes_at(name_at, name_len, &invalid);
    if (invalid != 0 || name_len == 0 || memchr(name, 0, name_len) != NULL) return -LINEA_TLS_INVALID_INPUT;
    struct client_config *owner = (struct client_config *)(uintptr_t)config;
    /* The lock is held across the open, so a name is added once, and only
     * after rustls accepted a connection for it. */
    pthread_mutex_lock(&owner->lock);
    long answer = 0;
    const char *kept = NULL;
    char *copy = NULL;
    if (owner->cap != 0) {
        const size_t slot = name_slot(owner, name, name_len);
        kept = owner->names[slot];
    }
    if (kept == NULL) {
        if (owner->count >= LINEA_TLS_MAX_NAMES) answer = -LINEA_TLS_TOO_MANY_NAMES;
        else if (!names_room(owner) || (copy = malloc(name_len + 1)) == NULL) answer = -LINEA_TLS_OUT_OF_MEMORY;
        else {
            memcpy(copy, name, name_len);
            copy[name_len] = 0;
            kept = copy;
        }
    }
    struct rustls_connection *opened = NULL;
    if (answer == 0) {
        const rustls_result result = owner->ops->client_connection_new(owner->config, kept, &opened);
        if (result != RUSTLS_RESULT_OK) answer = failure(result);
    }
    if (answer == 0) {
        if (copy != NULL) {
            owner->names[name_slot(owner, name, name_len)] = copy;
            owner->count += 1;
        }
        owner->refs += 1;
    } else {
        free(copy);
    }
    pthread_mutex_unlock(&owner->lock);
    if (answer != 0) return answer;
    return adopt(opened, owner->ops, owner, session);
}

long linea_tls_server_open(unsigned long config, unsigned long *session) {
    const struct server_config *held = (const struct server_config *)(uintptr_t)config;
    struct rustls_connection *opened = NULL;
    const rustls_result result = held->ops->server_connection_new(held->config, &opened);
    if (result != RUSTLS_RESULT_OK) return failure(result);
    return adopt(opened, held->ops, NULL, session);
}

/* The bytes not yet handed to rustls. */
struct pending {
    const uint8_t *bytes;
    size_t len;
};

static rustls_io_result give(void *userdata, uint8_t *buf, size_t n, size_t *out_n) {
    struct pending *pending = userdata;
    const size_t count = n < pending->len ? n : pending->len;
    memcpy(buf, pending->bytes, count);
    pending->bytes += count;
    pending->len -= count;
    *out_n = count;
    return 0;
}

long linea_tls_receive(unsigned long session, unsigned long at, unsigned long len) {
    long invalid = 0;
    const uint8_t *bytes = bytes_at(at, len, &invalid);
    if (invalid != 0) return invalid;
    struct session *held = held_session(session);
    /* TLS ends at close_notify; what follows it is not part of the stream. */
    if (held->closed) return (long)len;
    struct pending pending = {.bytes = bytes, .len = len};
    while (pending.len > 0) {
        size_t taken = 0;
        const rustls_io_result read = held->ops->read_tls(held->conn, give, &pending, &taken);
        /* rustls reads nothing more once it has processed the peer's
         * close_notify, and reads at most its own buffer at a time. It
         * refuses more while its plaintext buffer is full, and then what was
         * taken so far is answered, so the caller reads plaintext before
         * handing over the rest. */
        if (read == 0 && taken == 0) {
            held->closed = true;
            return (long)len;
        }
        if (read != 0) break;
        const rustls_result processed = held->ops->process_new_packets(held->conn);
        if (processed != RUSTLS_RESULT_OK) return failure(processed);
    }
    return (long)(len - pending.len);
}

struct output {
    uint8_t *bytes;
    size_t cap;
    size_t len;
};

static rustls_io_result take(void *userdata, const uint8_t *buf, size_t n, size_t *out_n) {
    struct output *output = userdata;
    const size_t room = output->cap - output->len;
    const size_t count = n < room ? n : room;
    memcpy(output->bytes + output->len, buf, count);
    output->len += count;
    *out_n = count;
    return 0;
}

long linea_tls_transmit(unsigned long session, unsigned long at, unsigned long cap) {
    long invalid = 0;
    uint8_t *bytes = (uint8_t *)bytes_at(at, cap, &invalid);
    if (invalid != 0) return invalid;
    struct output output = {.bytes = bytes, .cap = cap, .len = 0};
    struct session *held = held_session(session);
    while (output.len < output.cap && held->ops->wants_write(held->conn)) {
        size_t written = 0;
        if (held->ops->write_tls(held->conn, take, &output, &written) != 0 || written == 0) break;
    }
    return (long)output.len;
}

uint8_t linea_tls_state(unsigned long session) {
    const struct session *held = held_session(session);
    uint8_t state = 0;
    if (held->ops->is_handshaking(held->conn)) state |= LINEA_TLS_HANDSHAKING;
    if (held->ops->wants_read(held->conn)) state |= LINEA_TLS_WANTS_READ;
    if (held->ops->wants_write(held->conn)) state |= LINEA_TLS_WANTS_WRITE;
    if (held->ops->handshake_kind(held->conn) == RUSTLS_HANDSHAKE_KIND_RESUMED) state |= LINEA_TLS_RESUMED;
    return state;
}

long linea_tls_read(unsigned long session, unsigned long at, unsigned long cap) {
    long invalid = 0;
    uint8_t *bytes = (uint8_t *)bytes_at(at, cap, &invalid);
    if (invalid != 0) return invalid;
    if (cap == 0) return 0;
    struct session *held = held_session(session);
    size_t first = 0;
    if (held->holds_peeked) {
        bytes[0] = held->peeked;
        held->holds_peeked = false;
        first = 1;
        if (cap == 1) return 1;
    }
    size_t count = 0;
    const rustls_result result = held->ops->read(held->conn, bytes + first, cap - first, &count);
    if (first == 1 && result != RUSTLS_RESULT_OK) return 1;
    if (result == RUSTLS_RESULT_PLAINTEXT_EMPTY) return -LINEA_TLS_EMPTY;
    if (result != RUSTLS_RESULT_OK) return failure(result);
    return (long)(first + count);
}

uint8_t linea_tls_pending(unsigned long session) {
    struct session *held = held_session(session);
    if (held->holds_peeked) return 1;
    size_t count = 0;
    const rustls_result result = held->ops->read(held->conn, &held->peeked, 1, &count);
    if (result == RUSTLS_RESULT_PLAINTEXT_EMPTY) return 0;
    /* A byte, the peer's close_notify or an error: the next read answers
     * without waiting for the transport. */
    if (result == RUSTLS_RESULT_OK && count == 1) held->holds_peeked = true;
    return 1;
}

long linea_tls_write(unsigned long session, unsigned long at, unsigned long len) {
    long invalid = 0;
    const uint8_t *bytes = bytes_at(at, len, &invalid);
    if (invalid != 0) return invalid;
    if (len == 0) return 0;
    struct session *held = held_session(session);
    size_t count = 0;
    const rustls_result result = held->ops->write(held->conn, bytes, len, &count);
    if (result != RUSTLS_RESULT_OK) return failure(result);
    return (long)count;
}

void linea_tls_close_notify(unsigned long session) {
    struct session *held = held_session(session);
    held->ops->send_close_notify(held->conn);
}

long linea_tls_alpn(unsigned long session, unsigned long at, unsigned long cap) {
    long invalid = 0;
    uint8_t *bytes = (uint8_t *)bytes_at(at, cap, &invalid);
    if (invalid != 0) return invalid;
    const struct session *held = held_session(session);
    const uint8_t *protocol = NULL;
    size_t len = 0;
    held->ops->get_alpn_protocol(held->conn, &protocol, &len);
    if (protocol == NULL) return 0;
    if (len > cap) return -LINEA_TLS_INVALID_INPUT;
    memcpy(bytes, protocol, len);
    return (long)len;
}

void linea_tls_free(unsigned long session) {
    struct session *held = held_session(session);
    held->ops->connection_free(held->conn);
    if (held->owner != NULL) tls_config_release(held->owner);
    free(held);
}

uint8_t linea_tls_reason(long code) {
    const long value = code < 0 ? -code : code;
    switch (value) {
    case LINEA_TLS_INVALID_INPUT:
    case LINEA_TLS_TOO_MANY_NAMES:
        return LINEA_TLS_REASON_INVALID_INPUT;
    case RUSTLS_RESULT_CERT_EXPIRED:
    case RUSTLS_RESULT_CERT_NOT_YET_VALID:
        return LINEA_TLS_REASON_EXPIRED;
    case RUSTLS_RESULT_CERT_UNKNOWN_ISSUER:
        return LINEA_TLS_REASON_UNKNOWN_ISSUER;
    case RUSTLS_RESULT_CERT_NOT_VALID_FOR_NAME:
        return LINEA_TLS_REASON_WRONG_NAME;
    case RUSTLS_RESULT_CERT_REVOKED:
    case RUSTLS_RESULT_CERT_UNHANDLED_CRITICAL_EXTENSION:
    case RUSTLS_RESULT_CERT_BAD_SIGNATURE:
    case RUSTLS_RESULT_CERT_INVALID_PURPOSE:
    case RUSTLS_RESULT_CERT_APPLICATION_VERIFICATION_FAILURE:
    case RUSTLS_RESULT_CERT_OTHER_ERROR:
    case RUSTLS_RESULT_CERT_UNKNOWN_REVOCATION_STATUS:
    case RUSTLS_RESULT_CERT_EXPIRED_REVOCATION_LIST:
    case RUSTLS_RESULT_CERT_UNSUPPORTED_SIGNATURE_ALGORITHM:
        return LINEA_TLS_REASON_BAD_CERTIFICATE;
    case RUSTLS_RESULT_NO_CERTIFICATES_PRESENTED:
        return LINEA_TLS_REASON_NO_CERTIFICATE;
    case RUSTLS_RESULT_ALERT_NO_APPLICATION_PROTOCOL:
    case RUSTLS_RESULT_NO_APPLICATION_PROTOCOL:
        return LINEA_TLS_REASON_NO_PROTOCOL;
    case RUSTLS_RESULT_UNEXPECTED_EOF:
        return LINEA_TLS_REASON_TRUNCATED;
    case RUSTLS_RESULT_ALERT_BAD_CERTIFICATE:
    case RUSTLS_RESULT_ALERT_UNSUPPORTED_CERTIFICATE:
    case RUSTLS_RESULT_ALERT_CERTIFICATE_REVOKED:
    case RUSTLS_RESULT_ALERT_CERTIFICATE_EXPIRED:
    case RUSTLS_RESULT_ALERT_CERTIFICATE_UNKNOWN:
    case RUSTLS_RESULT_ALERT_UNKNOWN_CA:
    case RUSTLS_RESULT_ALERT_ACCESS_DENIED:
    case RUSTLS_RESULT_ALERT_CERTIFICATE_REQUIRED:
        return LINEA_TLS_REASON_PEER_REFUSED;
    case RUSTLS_RESULT_CERT_ENCODING_BAD:
    case RUSTLS_RESULT_CERTIFICATE_PARSE_ERROR:
    case RUSTLS_RESULT_PRIVATE_KEY_PARSE_ERROR:
    case RUSTLS_RESULT_INSUFFICIENT_SIZE:
    case RUSTLS_RESULT_NULL_PARAMETER:
    case RUSTLS_RESULT_INVALID_PARAMETER:
    case RUSTLS_RESULT_INVALID_DNS_NAME_ERROR:
        return LINEA_TLS_REASON_INVALID_INPUT;
    default:
        return LINEA_TLS_REASON_PROTOCOL;
    }
}
