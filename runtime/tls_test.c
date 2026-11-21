/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "tls.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ADDRESS(p) ((unsigned long)(uintptr_t)(p))

/* The directory of the PEM fixtures the standard library's tests use. */
#ifndef LINEA_TLS_FIXTURES
#error "LINEA_TLS_FIXTURES names the directory holding the PEM fixtures"
#endif

struct text {
    char *bytes;
    unsigned long len;
};

static struct text fixture(const char *name) {
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", LINEA_TLS_FIXTURES, name);
    FILE *file = fopen(path, "rb");
    assert(file != NULL);
    struct text text = {.bytes = malloc(16384), .len = 0};
    assert(text.bytes != NULL);
    text.len = (unsigned long)fread(text.bytes, 1, 16384, file);
    assert(text.len > 0 && text.len < 16384);
    fclose(file);
    return text;
}

static unsigned long server_config(const char *chain, const char *key, uint8_t client_auth, const char *alpn, unsigned long alpn_len) {
    struct text c = fixture(chain), k = fixture(key), roots = fixture("ca.pem");
    unsigned long config = 0;
    long answer = linea_tls_server_config(ADDRESS(c.bytes), c.len, ADDRESS(k.bytes), k.len, client_auth ? ADDRESS(roots.bytes) : 0, client_auth ? roots.len : 0, client_auth, ADDRESS(alpn), alpn_len, &config);
    assert(answer == 0);
    free(c.bytes);
    free(k.bytes);
    free(roots.bytes);
    return config;
}

static unsigned long client_config(const char *identity, const char *alpn, unsigned long alpn_len) {
    struct text roots = fixture("ca.pem");
    struct text chain = {0}, key = {0};
    if (identity != NULL) {
        char name[64];
        chain = fixture(identity);
        snprintf(name, sizeof name, "%.*s_key.pem", (int)(strlen(identity) - 4), identity);
        key = fixture(name);
    }
    unsigned long config = 0;
    long answer = linea_tls_client_config(ADDRESS(roots.bytes), roots.len, 0, ADDRESS(chain.bytes), chain.len, ADDRESS(key.bytes), key.len, ADDRESS(alpn), alpn_len, &config);
    assert(answer == 0);
    free(roots.bytes);
    free(chain.bytes);
    free(key.bytes);
    return config;
}

/* Carries ciphertext both ways until neither side has any to send. Answers 0,
 * or the first error either side's receive answered. */
static long exchange(unsigned long client, unsigned long server) {
    uint8_t flight[32768];
    for (int round = 0; round < 32; round += 1) {
        long moved = 0;
        long sent = linea_tls_transmit(client, ADDRESS(flight), sizeof flight);
        assert(sent >= 0);
        if (sent > 0) {
            moved += sent;
            long taken = linea_tls_receive(server, ADDRESS(flight), (unsigned long)sent);
            if (taken < 0) return taken;
        }
        sent = linea_tls_transmit(server, ADDRESS(flight), sizeof flight);
        assert(sent >= 0);
        if (sent > 0) {
            moved += sent;
            long taken = linea_tls_receive(client, ADDRESS(flight), (unsigned long)sent);
            if (taken < 0) return taken;
        }
        if (moved == 0) return 0;
    }
    return 0;
}

static unsigned long open_client(unsigned long config, const char *name) {
    unsigned long session = 0;
    assert(linea_tls_client_open(config, ADDRESS(name), strlen(name), &session) == 0);
    return session;
}

static unsigned long open_server(unsigned long config) {
    unsigned long session = 0;
    assert(linea_tls_server_open(config, &session) == 0);
    return session;
}

static void handshakes_and_carries_bytes(void) {
    unsigned long server_settings = server_config("server.pem", "server_key.pem", 0, NULL, 0);
    unsigned long client_settings = client_config(NULL, NULL, 0);
    unsigned long client = open_client(client_settings, "localhost");
    unsigned long server = open_server(server_settings);
    assert((linea_tls_state(client) & LINEA_TLS_HANDSHAKING) != 0);
    assert(exchange(client, server) == 0);
    assert((linea_tls_state(client) & LINEA_TLS_HANDSHAKING) == 0);
    assert((linea_tls_state(server) & LINEA_TLS_HANDSHAKING) == 0);

    uint8_t plain[64];
    assert(linea_tls_read(server, ADDRESS(plain), sizeof plain) == -LINEA_TLS_EMPTY);
    assert(linea_tls_pending(server) == 0);
    assert(linea_tls_write(client, ADDRESS("ping"), 4) == 4);
    assert(exchange(client, server) == 0);
    /* Finding the plaintext waiting reads its first byte ahead, which the
     * next read answers first. */
    assert(linea_tls_pending(server) == 1);
    assert(linea_tls_pending(server) == 1);
    assert(linea_tls_read(server, ADDRESS(plain), 1) == 1);
    assert(plain[0] == 'p');
    assert(linea_tls_read(server, ADDRESS(plain), sizeof plain) == 3);
    assert(memcmp(plain, "ing", 3) == 0);

    linea_tls_close_notify(client);
    assert(exchange(client, server) == 0);
    assert(linea_tls_read(server, ADDRESS(plain), sizeof plain) == 0);

    linea_tls_free(client);
    linea_tls_free(server);
    linea_tls_client_config_free(client_settings);
    linea_tls_server_config_free(server_settings);
}

static void refuses_a_certificate_for_another_name(void) {
    unsigned long server_settings = server_config("server.pem", "server_key.pem", 0, NULL, 0);
    unsigned long client_settings = client_config(NULL, NULL, 0);
    unsigned long client = open_client(client_settings, "example.test");
    unsigned long server = open_server(server_settings);
    const long failed = exchange(client, server);
    assert(failed < 0);
    assert(linea_tls_reason(failed) == LINEA_TLS_REASON_WRONG_NAME);
    linea_tls_free(client);
    linea_tls_free(server);
    linea_tls_client_config_free(client_settings);
    linea_tls_server_config_free(server_settings);
}

static void agrees_a_protocol_and_resumes(void) {
    static const char offered[] = "h2,http/1.1";
    static const char served[] = "http/1.1";
    unsigned long server_settings = server_config("server.pem", "server_key.pem", 0, served, sizeof served - 1);
    unsigned long client_settings = client_config(NULL, offered, sizeof offered - 1);
    for (int attempt = 0; attempt < 2; attempt += 1) {
        unsigned long client = open_client(client_settings, "localhost");
        unsigned long server = open_server(server_settings);
        assert(exchange(client, server) == 0);
        /* A TLS 1.3 server sends its tickets after the handshake, and the
         * client takes them when it next reads. */
        uint8_t plain[16];
        assert(linea_tls_read(client, ADDRESS(plain), sizeof plain) == -LINEA_TLS_EMPTY);
        char protocol[16];
        assert(linea_tls_alpn(client, ADDRESS(protocol), sizeof protocol) == 8);
        assert(memcmp(protocol, "http/1.1", 8) == 0);
        const int resumed = (linea_tls_state(client) & LINEA_TLS_RESUMED) != 0;
        assert(resumed == (attempt == 1));
        linea_tls_free(client);
        linea_tls_free(server);
    }
    linea_tls_client_config_free(client_settings);
    linea_tls_server_config_free(server_settings);
}

/* A connection opened after the one before it was freed, and after the
 * configuration was freed too, still finds the name it was opened for. */
static void keeps_server_names_while_connections_live(void) {
    unsigned long server_settings = server_config("server.pem", "server_key.pem", 0, NULL, 0);
    unsigned long client_settings = client_config(NULL, NULL, 0);
    char name[] = "localhost";
    unsigned long first = 0;
    assert(linea_tls_client_open(client_settings, ADDRESS(name), strlen(name), &first) == 0);
    unsigned long server = open_server(server_settings);
    assert(exchange(first, server) == 0);
    uint8_t plain[16];
    assert(linea_tls_read(first, ADDRESS(plain), sizeof plain) == -LINEA_TLS_EMPTY);
    linea_tls_free(first);
    linea_tls_free(server);
    /* The caller's copy of the name changes; the configuration kept its own. */
    memset(name, 'x', strlen(name));
    unsigned long second = open_client(client_settings, "localhost");
    linea_tls_client_config_free(client_settings);
    server = open_server(server_settings);
    assert(exchange(second, server) == 0);
    assert((linea_tls_state(second) & LINEA_TLS_RESUMED) != 0);
    linea_tls_free(second);
    linea_tls_free(server);
    linea_tls_server_config_free(server_settings);
}

/* Bytes after the peer's close_notify are ignored: a receive takes all it
 * is handed, and reads answer the plaintext before it and then the end. */
static void ignores_bytes_after_close_notify(void) {
    unsigned long server_settings = server_config("server.pem", "server_key.pem", 0, NULL, 0);
    unsigned long client_settings = client_config(NULL, NULL, 0);
    unsigned long client = open_client(client_settings, "localhost");
    unsigned long server = open_server(server_settings);
    assert(exchange(client, server) == 0);
    static uint8_t flight[16384];
    assert(linea_tls_write(client, ADDRESS("GET"), 3) == 3);
    linea_tls_close_notify(client);
    long sent = linea_tls_transmit(client, ADDRESS(flight), sizeof flight);
    assert(sent > 0);
    memset(flight + sent, 0x17, 6000);
    assert(linea_tls_receive(server, ADDRESS(flight), (unsigned long)sent + 6000) == sent + 6000);
    uint8_t plain[16];
    assert(linea_tls_read(server, ADDRESS(plain), sizeof plain) == 3);
    assert(linea_tls_read(server, ADDRESS(plain), sizeof plain) == 0);
    linea_tls_free(client);
    linea_tls_free(server);
    linea_tls_client_config_free(client_settings);
    linea_tls_server_config_free(server_settings);
}

static void requires_a_client_certificate(void) {
    unsigned long server_settings = server_config("server.pem", "server_key.pem", 2, NULL, 0);
    unsigned long anonymous = client_config(NULL, NULL, 0);
    unsigned long known = client_config("client.pem", NULL, 0);

    unsigned long client = open_client(known, "localhost");
    unsigned long server = open_server(server_settings);
    assert(exchange(client, server) == 0);
    assert((linea_tls_state(server) & LINEA_TLS_HANDSHAKING) == 0);
    linea_tls_free(client);
    linea_tls_free(server);

    client = open_client(anonymous, "localhost");
    server = open_server(server_settings);
    const long failed = exchange(client, server);
    assert(failed < 0);
    assert(linea_tls_reason(failed) == LINEA_TLS_REASON_NO_CERTIFICATE);
    linea_tls_free(client);
    linea_tls_free(server);

    linea_tls_client_config_free(anonymous);
    linea_tls_client_config_free(known);
    linea_tls_server_config_free(server_settings);
}

static void refuses_invalid_configuration(void) {
    unsigned long config = 0;
    assert(linea_tls_server_config(ADDRESS("x"), 1, ADDRESS("y"), 1, 0, 0, 0, 0, 0, &config) < 0);
    assert(linea_tls_server_config(0, 0, 0, 0, 0, 0, 0, 0, 0, &config) == -LINEA_TLS_INVALID_INPUT);
    /* A protocol list naming an empty protocol. */
    assert(linea_tls_client_config(0, 0, 1, 0, 0, 0, 0, ADDRESS("h2,,x"), 5, &config) == -LINEA_TLS_INVALID_INPUT);
    assert(linea_tls_reason(-LINEA_TLS_INVALID_INPUT) == LINEA_TLS_REASON_INVALID_INPUT);
}

int main(void) {
    handshakes_and_carries_bytes();
    refuses_a_certificate_for_another_name();
    agrees_a_protocol_and_resumes();
    keeps_server_names_while_connections_live();
    ignores_bytes_after_close_notify();
    requires_a_client_certificate();
    refuses_invalid_configuration();
    puts("tls: ok");
    return 0;
}
