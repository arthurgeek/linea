#include "tls.h"
#include "tls_ops.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include <rustls.h>

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

/* Splits a protocol list, the protocols separated by commas in preference
 * order, into the slices rustls takes. Answers how many, -1 when a protocol
 * is empty or longer than the 255 bytes TLS allows, or -2 when the slices
 * cannot be allocated. */
static long alpn_slices(const uint8_t *list, size_t len, rustls_slice_bytes **out) {
    *out = NULL;
    if (len == 0) return 0;
    size_t count = 1;
    for (size_t i = 0; i < len; i += 1) count += list[i] == ',';
    rustls_slice_bytes *slices = calloc(count, sizeof *slices);
    if (slices == NULL) return -2;
    size_t n = 0, start = 0;
    for (size_t i = 0; i <= len; i += 1) {
        if (i < len && list[i] != ',') continue;
        const size_t length = i - start;
        if (length == 0 || length > 255) {
            free(slices);
            return -1;
        }
        slices[n].data = list + start;
        slices[n].len = length;
        n += 1;
        start = i + 1;
    }
    *out = slices;
    return (long)count;
}

/* A root store holding the PEM certificates at `pem`. */
static long root_store(const uint8_t *pem, size_t len, const rustls_root_cert_store **store) {
    struct rustls_root_cert_store_builder *builder = rustls_root_cert_store_builder_new();
    if (builder == NULL) return -LINEA_TLS_OUT_OF_MEMORY;
    rustls_result result = rustls_root_cert_store_builder_add_pem(builder, pem, len, true);
    if (result == RUSTLS_RESULT_OK) result = rustls_root_cert_store_builder_build(builder, store);
    rustls_root_cert_store_builder_free(builder);
    return result == RUSTLS_RESULT_OK ? 0 : failure(result);
}

static uint32_t accept_any_certificate(void *userdata, const struct rustls_verify_server_cert_params *params) {
    (void)userdata;
    (void)params;
    return RUSTLS_RESULT_OK;
}

/* The certified key of a PEM chain and private key, or none when both are
 * empty. One without the other is invalid input. */
static long certified_key(const uint8_t *chain, size_t chain_len, const uint8_t *key, size_t key_len, const struct rustls_certified_key **out) {
    *out = NULL;
    if (chain_len == 0 && key_len == 0) return 0;
    if (chain_len == 0 || key_len == 0) return -LINEA_TLS_INVALID_INPUT;
    rustls_result result = rustls_certified_key_build(chain, chain_len, key, key_len, out);
    return result == RUSTLS_RESULT_OK ? 0 : failure(result);
}

/* Every rustls connection function a session calls, handed to it through
 * its configuration so that the session's object names none of them. */
static const struct tls_ops ops = {
    .client_connection_new = rustls_client_connection_new,
    .server_connection_new = rustls_server_connection_new,
    .set_buffer_limit = rustls_connection_set_buffer_limit,
    .read_tls = rustls_connection_read_tls,
    .write_tls = rustls_connection_write_tls,
    .process_new_packets = rustls_connection_process_new_packets,
    .wants_read = rustls_connection_wants_read,
    .wants_write = rustls_connection_wants_write,
    .is_handshaking = rustls_connection_is_handshaking,
    .handshake_kind = rustls_connection_handshake_kind,
    .read = rustls_connection_read,
    .write = rustls_connection_write,
    .send_close_notify = rustls_connection_send_close_notify,
    .get_alpn_protocol = rustls_connection_get_alpn_protocol,
    .connection_free = rustls_connection_free,
};

long linea_tls_client_config(unsigned long roots_at, unsigned long roots_len, uint8_t verify, unsigned long chain_at, unsigned long chain_len, unsigned long key_at, unsigned long key_len, unsigned long alpn_at, unsigned long alpn_len, unsigned long *config) {
    long invalid = 0;
    const uint8_t *roots = bytes_at(roots_at, roots_len, &invalid);
    const uint8_t *chain = bytes_at(chain_at, chain_len, &invalid);
    const uint8_t *key = bytes_at(key_at, key_len, &invalid);
    const uint8_t *alpn = bytes_at(alpn_at, alpn_len, &invalid);
    if (invalid != 0 || verify > 1) return -LINEA_TLS_INVALID_INPUT;

    rustls_slice_bytes *protocols = NULL;
    const long protocol_count = alpn_slices(alpn, alpn_len, &protocols);
    if (protocol_count == -1) return -LINEA_TLS_INVALID_INPUT;
    if (protocol_count < 0) return -LINEA_TLS_OUT_OF_MEMORY;

    const struct rustls_certified_key *identity = NULL;
    long answer = certified_key(chain, chain_len, key, key_len, &identity);
    if (answer < 0) {
        free(protocols);
        return answer;
    }

    struct rustls_client_config_builder *builder = rustls_client_config_builder_new();
    rustls_result result = RUSTLS_RESULT_OK;
    struct rustls_server_cert_verifier *verifier = NULL;
    if (verify == 1) {
        result = rustls_client_config_builder_dangerous_set_certificate_verifier(builder, accept_any_certificate);
    } else if (roots_len == 0) {
        result = rustls_platform_server_cert_verifier(&verifier);
    } else {
        const rustls_root_cert_store *store = NULL;
        answer = root_store(roots, roots_len, &store);
        if (answer == 0) {
            struct rustls_web_pki_server_cert_verifier_builder *verifying = rustls_web_pki_server_cert_verifier_builder_new(store);
            result = rustls_web_pki_server_cert_verifier_builder_build(verifying, &verifier);
            rustls_web_pki_server_cert_verifier_builder_free(verifying);
            rustls_root_cert_store_free(store);
        }
    }
    if (answer == 0 && result == RUSTLS_RESULT_OK && verifier != NULL) rustls_client_config_builder_set_server_verifier(builder, verifier);
    if (answer == 0 && result == RUSTLS_RESULT_OK && protocol_count > 0) result = rustls_client_config_builder_set_alpn_protocols(builder, protocols, (size_t)protocol_count);
    if (answer == 0 && result == RUSTLS_RESULT_OK && identity != NULL) result = rustls_client_config_builder_set_certified_key(builder, &identity, 1);
    if (answer == 0 && result == RUSTLS_RESULT_OK) {
        const struct rustls_client_config *built = NULL;
        result = rustls_client_config_builder_build(builder, &built);
        struct client_config *held = result == RUSTLS_RESULT_OK ? calloc(1, sizeof *held) : NULL;
        if (result == RUSTLS_RESULT_OK && (held == NULL || pthread_mutex_init(&held->lock, NULL) != 0)) {
            free(held);
            rustls_client_config_free(built);
            answer = -LINEA_TLS_OUT_OF_MEMORY;
        } else if (held != NULL) {
            held->config = built;
            held->ops = &ops;
            held->refs = 1;
            *config = (unsigned long)(uintptr_t)held;
        }
    } else {
        rustls_client_config_builder_free(builder);
    }
    rustls_server_cert_verifier_free(verifier);
    rustls_certified_key_free(identity);
    free(protocols);
    if (answer != 0) return answer;
    return result == RUSTLS_RESULT_OK ? 0 : failure(result);
}

long linea_tls_server_config(unsigned long chain_at, unsigned long chain_len, unsigned long key_at, unsigned long key_len, unsigned long clients_at, unsigned long clients_len, uint8_t client_auth, unsigned long alpn_at, unsigned long alpn_len, unsigned long *config) {
    long invalid = 0;
    const uint8_t *chain = bytes_at(chain_at, chain_len, &invalid);
    const uint8_t *key = bytes_at(key_at, key_len, &invalid);
    const uint8_t *clients = bytes_at(clients_at, clients_len, &invalid);
    const uint8_t *alpn = bytes_at(alpn_at, alpn_len, &invalid);
    if (invalid != 0 || client_auth > 2 || chain_len == 0 || key_len == 0) return -LINEA_TLS_INVALID_INPUT;
    if (client_auth != 0 && clients_len == 0) return -LINEA_TLS_INVALID_INPUT;

    rustls_slice_bytes *protocols = NULL;
    const long protocol_count = alpn_slices(alpn, alpn_len, &protocols);
    if (protocol_count == -1) return -LINEA_TLS_INVALID_INPUT;
    if (protocol_count < 0) return -LINEA_TLS_OUT_OF_MEMORY;

    const struct rustls_certified_key *identity = NULL;
    long answer = certified_key(chain, chain_len, key, key_len, &identity);
    if (answer < 0) {
        free(protocols);
        return answer;
    }

    struct rustls_server_config_builder *builder = rustls_server_config_builder_new();
    rustls_result result = rustls_server_config_builder_set_certified_keys(builder, &identity, 1);
    struct rustls_client_cert_verifier *verifier = NULL;
    if (result == RUSTLS_RESULT_OK && client_auth != 0) {
        const rustls_root_cert_store *store = NULL;
        answer = root_store(clients, clients_len, &store);
        if (answer == 0) {
            struct rustls_web_pki_client_cert_verifier_builder *verifying = rustls_web_pki_client_cert_verifier_builder_new(store);
            if (client_auth == 1) result = rustls_web_pki_client_cert_verifier_builder_allow_unauthenticated(verifying);
            if (result == RUSTLS_RESULT_OK) result = rustls_web_pki_client_cert_verifier_builder_build(verifying, &verifier);
            rustls_web_pki_client_cert_verifier_builder_free(verifying);
            rustls_root_cert_store_free(store);
        }
    }
    if (answer == 0 && result == RUSTLS_RESULT_OK && verifier != NULL) rustls_server_config_builder_set_client_verifier(builder, verifier);
    if (answer == 0 && result == RUSTLS_RESULT_OK && protocol_count > 0) result = rustls_server_config_builder_set_alpn_protocols(builder, protocols, (size_t)protocol_count);
    if (answer == 0 && result == RUSTLS_RESULT_OK) {
        const struct rustls_server_config *built = NULL;
        result = rustls_server_config_builder_build(builder, &built);
        struct server_config *held = result == RUSTLS_RESULT_OK ? malloc(sizeof *held) : NULL;
        if (result == RUSTLS_RESULT_OK && held == NULL) {
            rustls_server_config_free(built);
            answer = -LINEA_TLS_OUT_OF_MEMORY;
        } else if (held != NULL) {
            held->config = built;
            held->ops = &ops;
            *config = (unsigned long)(uintptr_t)held;
        }
    } else {
        rustls_server_config_builder_free(builder);
    }
    rustls_client_cert_verifier_free(verifier);
    rustls_certified_key_free(identity);
    free(protocols);
    if (answer != 0) return answer;
    return result == RUSTLS_RESULT_OK ? 0 : failure(result);
}


void linea_tls_client_config_free(unsigned long config) {
    struct client_config *held = (struct client_config *)(uintptr_t)config;
    rustls_client_config_free(held->config);
    tls_config_release(held);
}

void linea_tls_server_config_free(unsigned long config) {
    struct server_config *held = (struct server_config *)(uintptr_t)config;
    rustls_server_config_free(held->config);
    free(held);
}
