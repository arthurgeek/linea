#define _GNU_SOURCE
/* Assertions execute test setup, checks, and cleanup in every build mode. */
#undef NDEBUG
#include "io.h"
#include "net.h"

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define ADDRESS(p) ((unsigned long)(uintptr_t)(p))

static unsigned long loopback(unsigned port) { return (0x7f000001UL << 16) | port; }

static void round_trip(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0 && (bound >> 16) == 0x7f000001 && (bound & 0xffff) != 0);
    long client = linea_net_connect((unsigned long)bound);   /* before accept: kernel queues it */
    assert(client >= 0);
    long server = linea_net_accept((int)listener);
    assert(server >= 0);
    assert(write((int)client, "ping", 4) == 4);
    char got[4];
    assert(read((int)server, got, 4) == 4 && memcmp(got, "ping", 4) == 0);
    long peer = linea_net_peer_address((int)server);
    assert((peer >> 16) == 0x7f000001);
    close((int)client); close((int)server); close((int)listener);
}

static void read_timeout(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound);
    assert(client >= 0);
    long server = linea_net_accept((int)listener);
    assert(server >= 0);
    assert(linea_net_set_timeouts((int)server, 50, 50) == 0);
    char got[4];
    const long result = linea_read_some((int)server, ADDRESS(got), sizeof got);
    assert(result == -EAGAIN || result == -EWOULDBLOCK);
    close((int)client); close((int)server); close((int)listener);
}

static void broken_pipe_without_signal(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound);
    assert(client >= 0);
    long server = linea_net_accept((int)listener);
    assert(server >= 0);
    close((int)client);

    char bytes[64];
    memset(bytes, 'x', sizeof bytes);
    /* The kernel notices the closed peer once the writing process is the
     * only reference left to the half-closed connection; earlier writes can
     * still succeed, and one may even report -ECONNRESET before the socket
     * settles into reporting -EPIPE on every later write. */
    long result;
    int attempts = 0;
    do {
        result = linea_write_some((int)server, ADDRESS(bytes), sizeof bytes);
        attempts += 1;
    } while (result != -EPIPE && attempts < 100000);
    assert(result == -EPIPE);
    close((int)server); close((int)listener);
}

static void address_in_use(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long second = linea_net_listen((unsigned long)bound, 4);
    assert(second == -EADDRINUSE);
    close((int)listener);
}

static void refused(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    close((int)listener);
    long client = linea_net_connect((unsigned long)bound);
    assert(client == -ECONNREFUSED);
}

static void reset(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound);
    assert(client >= 0);
    long server = linea_net_accept((int)listener);
    assert(server >= 0);
    assert(write((int)client, "GET", 3) == 3);
    assert(linea_net_reset((int)client) == 0);
    /* The reset discards the connection, so the peer's read reports it
     * rather than an orderly end of input. */
    char got[8];
    long result = linea_read_some((int)server, ADDRESS(got), sizeof got);
    while (result > 0) result = linea_read_some((int)server, ADDRESS(got), sizeof got);
    assert(result == -ECONNRESET);
    close((int)server); close((int)listener);
}

static void accepted_after_reset(void) {
    long listener = linea_net_listen(loopback(0), 4);
    assert(listener >= 0);
    long bound = linea_net_local_address((int)listener);
    assert(bound >= 0);
    long client = linea_net_connect((unsigned long)bound);
    assert(client >= 0);
    assert(linea_net_reset((int)client) == 0);
    /* The reset reaches the listener before or after the queued connection
     * is handed out: accepting it fails, it is accepted with no peer left to
     * name, or it is accepted intact and its first read reports the reset.
     * Which of the three happens is the kernel's timing, not the runtime's
     * contract. */
    long server = linea_net_accept((int)listener);
    if (server < 0) {
        assert(server == -ECONNABORTED || server == -ECONNRESET);
    } else {
        long peer = linea_net_peer_address((int)server);
        if (peer >= 0) {
            char got[8];
            assert(linea_read_some((int)server, ADDRESS(got), sizeof got) == -ECONNRESET);
        } else {
            assert(peer == -ECONNRESET);
        }
        close((int)server);
    }
    /* Whichever way the reset showed, the listener still serves the next
     * client. */
    long next = linea_net_connect((unsigned long)bound);
    assert(next >= 0);
    long served = linea_net_accept((int)listener);
    assert(served >= 0);
    assert(linea_net_peer_address((int)served) >= 0);
    close((int)next); close((int)served); close((int)listener);
}

int main(void) {
    round_trip();
    read_timeout();
    broken_pipe_without_signal();
    address_in_use();
    refused();
    reset();
    accepted_after_reset();
    puts("native net: loopback round trips, timeouts, connection errors and resets passed");
    return 0;
}
