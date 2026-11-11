#define _GNU_SOURCE
#include "sim.h"

#include "clock.h"
#include "loop.h"
#include "pipe_signal.h"

#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/* The virtual monotonic clock starts at one second, so no virtual instant is
 * 0, which a deadline uses for none. The virtual wall clock starts at
 * 2026-01-01T00:00:00Z and moves with the monotonic one. */
static const unsigned long monotonic_start_ns = 1000000000UL;
static const long wall_start_seconds = 1767225600L;
static const unsigned long nanoseconds_per_second = 1000000000UL;

/* The ports a listener bound to port 0, and a connecting client, are given:
 * the dynamic range IANA reserves, counted up from its start. */
static const unsigned first_dynamic_port = 49152;

enum chunk_kind { chunk_data, chunk_end, chunk_reset };

/* Something one end of a connection receives at a virtual instant: bytes,
 * the peer's end of output, or a reset. */
struct chunk {
    struct chunk *next;
    unsigned long arrives;
    enum chunk_kind kind;
    size_t len;
    unsigned char bytes[];
};

struct sim;

/* One simulated descriptor: a listener or one end of a connection. */
struct entry {
    struct sim *sim;            /* the simulation that made it; null once it has ended */
    unsigned long number;       /* which descriptor of its simulation it is, for the trace */
    int listening;
    unsigned long address;      /* the bound address, or the end's own */

    /* A listener's handshakes, in the order they began: entry indices. */
    long *pending;
    size_t pending_count, pending_capacity;
    unsigned long backlog;

    /* One end of a connection. */
    unsigned long peer_address;
    long peer;                  /* the other end's entry index, -1 once it closed or was forgotten */
    long listener;              /* for a server end not yet accepted, its listener; otherwise -1 */
    unsigned long established;  /* the instant the handshake completes */
    struct chunk *inflight, *inflight_tail;
    unsigned long inflight_bytes;
    unsigned long last_arrival; /* the latest arrival scheduled to this end, which keeps chunks in order */
    unsigned char *received;
    size_t received_len, received_capacity;
    int ended, reset, write_shut, reset_scheduled;
    /* Released outside a run of its simulation, which is still open: no one
     * holds its number, and the simulation closes it at its next operation. */
    int forgotten;
};

struct sim {
    unsigned long identity;
    uint64_t rng;
    unsigned long now;
    unsigned long latency_ns, jitter_ns, chunk_bytes, buffer_bytes, reset_one_in;
    int short_writes;
    uint64_t trace;
    unsigned next_port;
    unsigned long made;
    /* Its descriptors' entry indices, in the order they were made, which is
     * the order deliveries are made in. */
    long *members;
    size_t member_count, member_capacity;
};

static pthread_mutex_t sim_lock = PTHREAD_MUTEX_INITIALIZER;
static struct entry **entries;
static size_t entry_count, entry_capacity;
static long *free_entries;
static size_t free_count, free_capacity;

static void fail(const char *message) {
    report_bytes(message, strlen(message));
    abort();
}

static void lock(void) {
    if (pthread_mutex_lock(&sim_lock) != 0) fail("linea: a simulation's lock failed\n");
}

static void unlock(void) {
    if (pthread_mutex_unlock(&sim_lock) != 0) fail("linea: a simulation's lock failed\n");
}

static void outside(void) {
    fail("linea: a simulated descriptor was used outside its simulation\n");
}

static unsigned long add_saturating(unsigned long a, unsigned long b) {
    return a > ULONG_MAX - b ? ULONG_MAX : a + b;
}

/* Grow `*items` to hold `needed` longs. Zero, or -ENOMEM. */
static int reserve(long **items, size_t *capacity, size_t needed) {
    if (needed <= *capacity) return 0;
    size_t next = *capacity == 0 ? 8 : *capacity * 2;
    while (next < needed) next *= 2;
    long *grown = realloc(*items, next * sizeof **items);
    if (grown == NULL) return -ENOMEM;
    *items = grown;
    *capacity = next;
    return 0;
}

static void remove_index(long *items, size_t *count, long index) {
    for (size_t i = 0; i < *count; i++) {
        if (items[i] != index) continue;
        memmove(&items[i], &items[i + 1], (*count - i - 1) * sizeof *items);
        *count -= 1;
        return;
    }
}

/* Both the choice sequence and the trace digest are arithmetic modulo 2^64,
 * so their wrapping is the intended result and not an overflow to report. */
#define WRAPS_MODULO_2_64 __attribute__((no_sanitize("unsigned-integer-overflow")))

/* splitmix64: every choice the simulation makes is drawn from this one
 * sequence, so a seed decides them all. */
WRAPS_MODULO_2_64 static uint64_t draw(struct sim *s) {
    uint64_t z = (s->rng += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

/* A choice from 0 to `bound` inclusive. */
static unsigned long up_to(struct sim *s, unsigned long bound) {
    if (bound == 0) return 0;
    if (bound == ULONG_MAX) return (unsigned long)draw(s);
    return (unsigned long)(draw(s) % (bound + 1));
}

/* Fold one event into the trace, FNV-1a over its four words. */
WRAPS_MODULO_2_64 static void note(struct sim *s, unsigned long what, unsigned long number, unsigned long value) {
    const unsigned long words[4] = { what, number, s->now, value };
    for (int w = 0; w < 4; w++) {
        for (int b = 0; b < 8; b++) {
            s->trace ^= (words[w] >> (8 * b)) & 0xffUL;
            s->trace *= 0x100000001b3ULL;
        }
    }
}

enum event { event_data = 1, event_end, event_reset, event_op, event_wait, event_listen, event_close };

/* A wait set's wait, which the trace tells apart from an operation's by the
 * kind it records: one past every operation kind. */
enum { event_set_wait = 8 };

/* Fold the bytes a delivery carries into the trace, so two runs that
 * deliver different bytes of one length differ. */
WRAPS_MODULO_2_64 static void note_bytes(struct sim *s, const unsigned char *bytes, size_t len) {
    for (size_t i = 0; i < len; i++) {
        s->trace ^= bytes[i];
        s->trace *= 0x100000001b3ULL;
    }
}

/* An answer as the trace records it: a count as it is, and an error as its
 * place in this list rather than its errno, which differs between Linux
 * and macOS, so one seed gives one trace on both. */
static unsigned long traced_answer(long answer) {
    static const int errors[] = { EAGAIN, ETIMEDOUT, ECONNRESET, ECONNREFUSED, EPIPE,
                                  ENOTCONN, EINVAL, EADDRINUSE, ENOMEM, EMFILE, EBADF };
    if (answer >= 0) return (unsigned long)answer;
    for (size_t i = 0; i < sizeof errors / sizeof *errors; i++) {
        if (answer == -(long)errors[i]) return ULONG_MAX - i;
    }
    return ULONG_MAX - 64;
}

static int descriptor_of(long index) {
    return (int)(LINEA_SIM_FIRST_DESCRIPTOR + index);
}

static long index_of(int fd) {
    return (long)fd - LINEA_SIM_FIRST_DESCRIPTOR;
}

/* The entry `fd` numbers, or null. Called locked. */
static struct entry *entry_of(int fd) {
    if (fd < LINEA_SIM_FIRST_DESCRIPTOR) return NULL;
    const long index = index_of(fd);
    if ((size_t)index >= entry_count) return NULL;
    return entries[index];
}

static struct entry *at(long index) {
    return index < 0 ? NULL : entries[index];
}

/* A new entry of `s`, or -ENOMEM. Called locked. */
static long make_entry(struct sim *s, int listening, unsigned long address) {
    if (reserve(&s->members, &s->member_capacity, s->member_count + 1) != 0) return -ENOMEM;
    struct entry *e = calloc(1, sizeof *e);
    if (e == NULL) return -ENOMEM;
    long index;
    if (free_count > 0) {
        free_count -= 1;
        index = free_entries[free_count];
    } else {
        if (entry_count == entry_capacity) {
            const size_t next = entry_capacity == 0 ? 16 : entry_capacity * 2;
            struct entry **grown = realloc(entries, next * sizeof *grown);
            if (grown == NULL) { free(e); return -ENOMEM; }
            entries = grown;
            entry_capacity = next;
        }
        if (entry_count >= (size_t)(INT_MAX - LINEA_SIM_FIRST_DESCRIPTOR)) { free(e); return -EMFILE; }
        index = (long)entry_count;
        entry_count += 1;
    }
    e->sim = s;
    e->number = s->made++;
    e->listening = listening;
    e->address = address;
    e->peer = -1;
    e->listener = -1;
    entries[index] = e;
    s->members[s->member_count++] = index;
    return index;
}

static void free_contents(struct entry *e) {
    struct chunk *c = e->inflight;
    while (c != NULL) {
        struct chunk *next = c->next;
        free(c);
        c = next;
    }
    e->inflight = e->inflight_tail = NULL;
    e->inflight_bytes = 0;
    free(e->received);
    e->received = NULL;
    e->received_len = e->received_capacity = 0;
    free(e->pending);
    e->pending = NULL;
    e->pending_count = e->pending_capacity = 0;
}

/* Free the entry `index` and its number. Called locked. */
static void drop_entry(long index) {
    struct entry *e = entries[index];
    if (e->sim != NULL) remove_index(e->sim->members, &e->sim->member_count, index);
    free_contents(e);
    free(e);
    entries[index] = NULL;
    if (reserve(&free_entries, &free_capacity, free_count + 1) == 0) free_entries[free_count++] = index;
}

/* The delay of one delivery: the latency and a chosen part of the jitter. */
static unsigned long delay(struct sim *s) {
    return add_saturating(s->latency_ns, up_to(s, s->jitter_ns));
}

/* Send `to` a chunk arriving after one delivery's delay, and after every
 * chunk already on its way. Zero, or -ENOMEM. */
static long schedule(struct sim *s, struct entry *to, enum chunk_kind kind, const unsigned char *bytes, size_t len) {
    struct chunk *c = malloc(sizeof *c + len);
    if (c == NULL) return -ENOMEM;
    unsigned long arrives = add_saturating(s->now, delay(s));
    if (arrives < to->last_arrival) arrives = to->last_arrival;
    c->next = NULL;
    c->arrives = arrives;
    c->kind = kind;
    c->len = len;
    if (len > 0) memcpy(c->bytes, bytes, len);
    if (to->inflight_tail == NULL) to->inflight = c; else to->inflight_tail->next = c;
    to->inflight_tail = c;
    to->inflight_bytes += len;
    to->last_arrival = arrives;
    return 0;
}

static long append_received(struct entry *e, const unsigned char *bytes, size_t len) {
    if (e->received_len + len > e->received_capacity) {
        size_t next = e->received_capacity == 0 ? 64 : e->received_capacity;
        while (next < e->received_len + len) next *= 2;
        unsigned char *grown = realloc(e->received, next);
        if (grown == NULL) return -ENOMEM;
        e->received = grown;
        e->received_capacity = next;
    }
    memcpy(e->received + e->received_len, bytes, len);
    e->received_len += len;
    return 0;
}

/* Move the clock to `t` and deliver everything that has arrived by then, one
 * descriptor at a time in the order they were made. A reset discards what
 * its end had received and not read, as a kernel does, and bytes arriving
 * after it are dropped. */
static void deliver(struct sim *s, unsigned long t) {
    if (t > s->now) s->now = t;
    for (size_t m = 0; m < s->member_count; m++) {
        struct entry *e = entries[s->members[m]];
        while (e->inflight != NULL && e->inflight->arrives <= s->now) {
            struct chunk *c = e->inflight;
            e->inflight = c->next;
            if (e->inflight == NULL) e->inflight_tail = NULL;
            e->inflight_bytes -= c->len;
            if (c->kind == chunk_reset) {
                e->reset = 1;
                e->received_len = 0;
                note(s, event_reset, e->number, 0);
            } else if (c->kind == chunk_end) {
                e->ended = 1;
                note(s, event_end, e->number, 0);
            } else if (!e->reset) {
                /* A failed allocation drops the bytes: the reader then sees a
                 * reset, since the stream can no longer be trusted. */
                if (append_received(e, c->bytes, c->len) != 0) {
                    e->reset = 1;
                    e->received_len = 0;
                }
                note(s, event_data, e->number, c->len);
                note_bytes(s, c->bytes, c->len);
            }
            free(c);
        }
    }
}

/* The earliest instant after now at which something changes: a chunk's
 * arrival or a handshake's completion; 0 when nothing ever will. */
static unsigned long next_event(struct sim *s) {
    unsigned long next = 0;
    for (size_t m = 0; m < s->member_count; m++) {
        struct entry *e = entries[s->members[m]];
        if (e->inflight != NULL && (next == 0 || e->inflight->arrives < next)) next = e->inflight->arrives;
        if (!e->listening && e->established > s->now && (next == 0 || e->established < next)) next = e->established;
    }
    return next;
}

static unsigned port_of(unsigned long address) {
    return (unsigned)(address & 0xffffUL);
}

static unsigned long host_of(unsigned long address) {
    return address >> 16;
}

/* Whether a descriptor of `s` is bound to `port`: any of them when
 * `listeners_only` is 0, a listener when it is 1. */
static int port_in_use(struct sim *s, unsigned port, int listeners_only) {
    for (size_t m = 0; m < s->member_count; m++) {
        struct entry *e = entries[s->members[m]];
        if (port_of(e->address) == port && (e->listening || !listeners_only)) return 1;
    }
    return 0;
}

static unsigned long free_port(struct sim *s) {
    while (port_in_use(s, s->next_port, 0) && s->next_port < 65535) s->next_port += 1;
    const unsigned port = s->next_port;
    if (s->next_port < 65535) s->next_port += 1;
    return port;
}

/* The listener of `s` a connection to `address` reaches: one bound to its
 * port, on its host or on every host. */
static long listener_for(struct sim *s, unsigned long address) {
    for (size_t m = 0; m < s->member_count; m++) {
        struct entry *e = entries[s->members[m]];
        if (!e->listening || port_of(e->address) != port_of(address)) continue;
        if (host_of(e->address) == 0 || host_of(e->address) == host_of(address)) return s->members[m];
    }
    return -1;
}

/* Close the end `index` as a socket closes: the peer receives the end of
 * input, or a reset where bytes sent here were never read. A client closed
 * before its handshake completed takes the server's end out of the
 * listener's queue, as a kernel drops a half-open connection. Called
 * locked. */
static void close_end(struct sim *s, long index, int reset) {
    struct entry *e = entries[index];
    struct entry *peer = at(e->peer);
    if (peer != NULL) {
        const int unread = e->received_len > 0 || e->inflight_bytes > 0;
        if (reset || unread) {
            (void)schedule(s, peer, chunk_reset, NULL, 0);
        } else if (!e->write_shut) {
            (void)schedule(s, peer, chunk_end, NULL, 0);
        }
        peer->peer = -1;
        if (e->established > s->now && peer->listener >= 0) {
            remove_index(at(peer->listener)->pending, &at(peer->listener)->pending_count, e->peer);
            drop_entry(e->peer);
        }
    }
    note(s, event_close, e->number, (unsigned long)reset);
    drop_entry(index);
}

/* Close a listener: every connection in its queue is reset. */
static void close_listener(struct sim *s, long index) {
    struct entry *l = entries[index];
    while (l->pending_count > 0) {
        const long queued = l->pending[0];
        remove_index(l->pending, &l->pending_count, queued);
        at(queued)->listener = -1;
        close_end(s, queued, 1);
    }
    note(s, event_close, l->number, 0);
    drop_entry(index);
}

/* Close, as a socket closes, every entry of `s` that was released outside a
 * run. A release between runs is ordered by the program, so doing it here,
 * at the simulation's next operation and in the order the descriptors were
 * made, leaves the run as repeatable as a close made inside it. Called
 * locked, at the start of every operation. */
static void settle(struct sim *s) {
    size_t m = 0;
    while (m < s->member_count) {
        const long index = s->members[m];
        struct entry *e = entries[index];
        if (!e->forgotten) {
            m += 1;
            continue;
        }
        if (e->listening) close_listener(s, index); else close_end(s, index, 0);
        m = 0;
    }
}

static long attempt_accept(struct sim *s, struct entry *l) {
    if (!l->listening) return -(long)EINVAL;
    for (size_t i = 0; i < l->pending_count; i++) {
        const long queued = l->pending[i];
        if (at(queued)->established > s->now) continue;
        remove_index(l->pending, &l->pending_count, queued);
        at(queued)->listener = -1;
        return descriptor_of(queued);
    }
    return -(long)EAGAIN;
}

/* The first attempt starts the handshake; a later one checks whether it has
 * completed. */
static long attempt_connect(struct sim *s, struct linea_op *op) {
    if (op->fd == -1) {
        const long listener = listener_for(s, op->address);
        if (listener < 0 || at(listener)->pending_count >= at(listener)->backlog) return -(long)ECONNREFUSED;
        const unsigned long host = host_of(op->address) == 0 ? 0x7f000001UL : host_of(op->address);
        const long client = make_entry(s, 0, (host << 16) | free_port(s));
        if (client < 0) return client;
        const long server = make_entry(s, 0, (host << 16) | port_of(op->address));
        if (server < 0) { drop_entry(client); return server; }
        if (reserve(&at(listener)->pending, &at(listener)->pending_capacity, at(listener)->pending_count + 1) != 0) {
            drop_entry(server);
            drop_entry(client);
            return -(long)ENOMEM;
        }
        struct entry *c = at(client), *v = at(server);
        c->peer = server;
        v->peer = client;
        c->peer_address = v->address;
        v->peer_address = c->address;
        /* The client is connected once its SYN has arrived and the SYN-ACK
         * come back; the server's end is ready to accept once the client's
         * ACK arrives, one delivery after that. */
        const unsigned long syn = add_saturating(s->now, delay(s));
        c->established = add_saturating(syn, delay(s));
        v->established = add_saturating(c->established, delay(s));
        v->last_arrival = c->established;
        v->listener = listener;
        at(listener)->pending[at(listener)->pending_count++] = server;
        op->fd = descriptor_of(client);
    }
    struct entry *c = entry_of(op->fd);
    if (c->reset) return -(long)ECONNREFUSED;
    return c->established <= s->now ? op->fd : -(long)EAGAIN;
}

static long attempt_read(struct entry *e, struct linea_op *op) {
    if (e->listening) return -(long)ENOTCONN;
    if (e->received_len > 0) {
        const size_t count = e->received_len < op->len ? e->received_len : (size_t)op->len;
        memcpy((void *)(uintptr_t)op->at, e->received, count);
        memmove(e->received, e->received + count, e->received_len - count);
        e->received_len -= count;
        return (long)count;
    }
    if (e->reset) return -(long)ECONNRESET;
    if (e->ended) return 0;
    return -(long)EAGAIN;
}

/* A write takes what fits in the peer's share of the network, or a chosen
 * prefix of it, and cuts it into chunks. A peer that has closed answers the
 * first write with a reset, as a kernel does. */
static long attempt_write(struct sim *s, struct entry *e, struct linea_op *op) {
    if (e->listening) return -(long)ENOTCONN;
    if (e->reset) return -(long)ECONNRESET;
    if (e->write_shut) return -(long)EPIPE;
    struct entry *peer = at(e->peer);
    if (peer == NULL) {
        if (!e->reset_scheduled) {
            e->reset_scheduled = 1;
            if (schedule(s, e, chunk_reset, NULL, 0) != 0) return -(long)ENOMEM;
        }
        return (long)op->len;
    }
    const unsigned long capacity = s->buffer_bytes == 0 ? 1 : s->buffer_bytes;
    const unsigned long used = peer->received_len + peer->inflight_bytes;
    if (used >= capacity) return -(long)EAGAIN;
    unsigned long count = capacity - used < op->len ? capacity - used : op->len;
    if (s->short_writes && count > 1) count = 1 + up_to(s, count - 1);
    const unsigned char *bytes = (const unsigned char *)(uintptr_t)op->at;
    unsigned long sent = 0;
    while (sent < count) {
        unsigned long piece = count - sent;
        if (s->chunk_bytes != 0) piece = 1 + up_to(s, (piece < s->chunk_bytes ? piece : s->chunk_bytes) - 1);
        if (s->reset_one_in != 0 && up_to(s, s->reset_one_in - 1) == 0) {
            if (schedule(s, peer, chunk_reset, NULL, 0) != 0 || schedule(s, e, chunk_reset, NULL, 0) != 0) return -(long)ENOMEM;
            break;
        }
        if (schedule(s, peer, chunk_data, bytes + sent, piece) != 0) return sent > 0 ? (long)sent : -(long)ENOMEM;
        sent += piece;
    }
    return (long)count;
}

static long attempt(struct sim *s, struct linea_op *op) {
    if (op->kind == LINEA_OP_SLEEP) return -(long)EAGAIN;
    if (op->kind == LINEA_OP_CONNECT) return attempt_connect(s, op);
    struct entry *e = entry_of(op->fd);
    if (op->kind == LINEA_OP_ACCEPT) return attempt_accept(s, e);
    if (op->kind == LINEA_OP_READ) return attempt_read(e, op);
    return attempt_write(s, e, op);
}

/* Perform `op` on `s`, as the in-place backend does on the kernel: the
 * deadline is checked once on entry; an attempt that would wait jumps the
 * clock to the next event or to the deadline, whichever is first; and an
 * attempt made as the deadline arrives is the last and decides the result
 * by the operation's own rule, so progress observed at the deadline wins.
 * With no deadline and nothing left to happen, the one task would wait
 * forever, which traps. Called locked. */
static long perform(struct sim *s, struct linea_op *op) {
    long answer;
    if (op->deadline_ns != 0 && s->now >= op->deadline_ns) {
        answer = -(long)ETIMEDOUT;
    } else {
        for (;;) {
            answer = attempt(s, op);
            if (answer != -(long)EAGAIN) break;
            if (op->deadline_ns != 0 && s->now >= op->deadline_ns) { answer = -(long)ETIMEDOUT; break; }
            unsigned long next = next_event(s);
            if (op->deadline_ns != 0 && (next == 0 || next > op->deadline_ns)) next = op->deadline_ns;
            if (next == 0) fail("linea: a simulation's one task waits forever\n");
            note(s, event_wait, (unsigned long)op->kind, next);
            deliver(s, next);
        }
    }
    if (op->kind == LINEA_OP_CONNECT && answer < 0 && op->fd != -1) {
        close_end(s, index_of(op->fd), 0);
        op->fd = -1;
    }
    if (op->kind == LINEA_OP_SLEEP) answer = 0;
    /* A descriptor's number depends on what other simulations hold, so the
     * trace names a descriptor by its place in this one: the one operated
     * on, and the one an accept or a connect made. */
    const struct entry *operand = op->kind == LINEA_OP_CONNECT ? NULL : entry_of(op->fd);
    const int made = (op->kind == LINEA_OP_ACCEPT || op->kind == LINEA_OP_CONNECT) && answer >= 0;
    note(s, event_op * 8 + (unsigned long)op->kind, operand == NULL ? ULONG_MAX : operand->number,
         made ? entries[index_of((int)answer)]->number : traced_answer(answer));
    return answer;
}

unsigned long linea_sim_open(unsigned long seed, unsigned long latency_ns, unsigned long jitter_ns,
                             unsigned long chunk_bytes, unsigned long buffer_bytes, uint8_t short_writes,
                             unsigned long reset_one_in) {
    struct sim *s = calloc(1, sizeof *s);
    if (s == NULL) return 0;
    s->rng = seed;
    s->now = monotonic_start_ns;
    s->latency_ns = latency_ns;
    s->jitter_ns = jitter_ns;
    s->chunk_bytes = chunk_bytes;
    s->buffer_bytes = buffer_bytes;
    s->short_writes = short_writes != 0;
    s->reset_one_in = reset_one_in;
    s->trace = 0xcbf29ce484222325ULL;
    s->next_port = first_dynamic_port;
    lock();
    s->identity = linea_loop_claim(s);
    unlock();
    if (s->identity == 0) { free(s); return 0; }
    return s->identity;
}

void linea_sim_advance(unsigned long identity, unsigned long nanoseconds) {
    struct sim *s = linea_loop_find(identity);
    if (s != linea_loop_running()) fail("linea: a simulation's world was used outside its run\n");
    struct linea_op op = { LINEA_OP_SLEEP, -1, 0, 0, 0, 0 };
    lock();
    settle(s);
    if (nanoseconds != 0) {
        op.deadline_ns = add_saturating(s->now, nanoseconds);
        (void)perform(s, &op);
    }
    unlock();
}

unsigned long linea_sim_fingerprint(unsigned long identity) {
    struct sim *s = linea_loop_find(identity);
    lock();
    const unsigned long trace = (unsigned long)s->trace;
    unlock();
    return trace;
}

/* Free what the simulation's network holds. A server end still in a
 * listener's queue and a forgotten entry are held by nothing and go; every
 * other entry stays, as
 * a descriptor outside every simulation, until what owns it releases it. */
void linea_sim_close(unsigned long identity) {
    struct sim *s = linea_loop_find(identity);
    lock();
    size_t m = 0;
    while (m < s->member_count) {
        const long index = s->members[m];
        struct entry *e = entries[index];
        if (e->listener >= 0 || e->forgotten) {
            drop_entry(index);
            continue;
        }
        m += 1;
    }
    for (m = 0; m < s->member_count; m++) {
        struct entry *e = entries[s->members[m]];
        free_contents(e);
        e->sim = NULL;
        e->peer = -1;
    }
    free(s->members);
    unlock();
    linea_loop_retire(identity);
    free(s);
}

int linea_sim_takes(int fd) {
    struct sim *running = linea_loop_running();
    if (fd >= LINEA_SIM_FIRST_DESCRIPTOR) {
        lock();
        const struct entry *e = entry_of(fd);
        const int inside = e != NULL && running != NULL && e->sim == running;
        unlock();
        if (!inside) outside();
        return 1;
    }
    if (running != NULL) fail("linea: a real socket was used inside a simulation\n");
    return 0;
}

static struct sim *running_sim(void) {
    struct sim *s = linea_loop_running();
    if (s == NULL) outside();
    return s;
}

long linea_sim_perform(struct linea_op *op) {
    struct sim *s = running_sim();
    lock();
    settle(s);
    const long answer = perform(s, op);
    unlock();
    return answer;
}

long linea_sim_listen(unsigned long address, unsigned long backlog) {
    struct sim *s = running_sim();
    if (backlog > 4096) return -(long)EINVAL;
    lock();
    settle(s);
    unsigned long bound = address;
    long answer;
    if (port_of(address) == 0) {
        bound = (host_of(address) << 16) | free_port(s);
    }
    if (port_of(address) != 0 && port_in_use(s, port_of(address), 1)) {
        answer = -(long)EADDRINUSE;
    } else {
        const long index = make_entry(s, 1, bound);
        if (index >= 0) entries[index]->backlog = backlog == 0 ? 1 : backlog;
        answer = index < 0 ? index : descriptor_of(index);
    }
    note(s, event_listen, (unsigned long)bound, answer < 0 ? traced_answer(answer) : entries[index_of((int)answer)]->number);
    unlock();
    return answer;
}

long linea_sim_local_address(int fd) {
    lock();
    const long answer = (long)entry_of(fd)->address;
    unlock();
    return answer;
}

long linea_sim_peer_address(int fd) {
    lock();
    const struct entry *e = entry_of(fd);
    long answer;
    if (e->listening) answer = -(long)ENOTCONN;
    else if (e->reset) answer = -(long)ECONNRESET;
    else answer = (long)e->peer_address;
    unlock();
    return answer;
}

long linea_sim_shutdown_write(int fd) {
    struct sim *s = running_sim();
    lock();
    settle(s);
    struct entry *e = entry_of(fd);
    long answer = 0;
    if (e->listening || e->reset) {
        answer = -(long)ENOTCONN;
    } else if (!e->write_shut) {
        e->write_shut = 1;
        struct entry *peer = at(e->peer);
        if (peer != NULL && schedule(s, peer, chunk_end, NULL, 0) != 0) answer = -(long)ENOMEM;
    }
    unlock();
    return answer;
}

long linea_sim_reset(int fd) {
    struct sim *s = running_sim();
    lock();
    settle(s);
    const long index = index_of(fd);
    if (entries[index]->listening) close_listener(s, index); else close_end(s, index, 1);
    unlock();
    return 0;
}

long linea_sim_release(int fd) {
    struct sim *running = linea_loop_running();
    lock();
    struct entry *e = entry_of(fd);
    if (e == NULL) { unlock(); return -(long)EBADF; }
    const long index = index_of(fd);
    /* A release from another thread while the simulation runs would land
     * at a moment the kernel picks; between runs, the program orders it. */
    if (e->sim != NULL && e->sim != running && linea_loop_runs(e->sim->identity) > 0) {
        unlock();
        outside();
    }
    if (e->sim != NULL && e->sim == running) {
        settle(running);
        if (e->listening) close_listener(running, index); else close_end(running, index, 0);
    } else {
        /* Outside its simulation the entry is forgotten: a simulation that
         * has ended has already cut its links, and one still open closes it
         * at its next operation (`settle`). */
        if (e->sim == NULL) drop_entry(index); else e->forgotten = 1;
    }
    unlock();
    return 0;
}

long linea_sim_clock_read(uint8_t clock, long *seconds, unsigned long *nanoseconds) {
    struct sim *s = running_sim();
    lock();
    const unsigned long now = s->now;
    unlock();
    if (clock == LINEA_CLOCK_MONOTONIC) {
        *seconds = (long)(now / nanoseconds_per_second);
        *nanoseconds = now % nanoseconds_per_second;
        return 0;
    }
    if (clock == LINEA_CLOCK_WALL) {
        const unsigned long since = now - monotonic_start_ns;
        *seconds = wall_start_seconds + (long)(since / nanoseconds_per_second);
        *nanoseconds = since % nanoseconds_per_second;
        return 0;
    }
    return -(long)EINVAL;
}

unsigned long linea_sim_now(void) {
    struct sim *s = running_sim();
    lock();
    const unsigned long now = s->now;
    unlock();
    return now;
}

int linea_sim_ready(int fd, uint8_t writable) {
    struct sim *s = running_sim();
    lock();
    settle(s);
    const struct entry *e = entry_of(fd);
    int ready = 0;
    if (e == NULL) {
        ready = 1;
    } else if (e->listening) {
        for (size_t i = 0; i < e->pending_count && !ready; i++) ready = at(e->pending[i])->established <= s->now;
    } else if (writable) {
        const struct entry *peer = at(e->peer);
        const unsigned long capacity = s->buffer_bytes == 0 ? 1 : s->buffer_bytes;
        ready = e->reset || e->write_shut || peer == NULL || peer->received_len + peer->inflight_bytes < capacity;
    } else {
        ready = e->received_len > 0 || e->ended || e->reset;
    }
    unlock();
    return ready;
}

unsigned long linea_sim_next_event(void) {
    struct sim *s = running_sim();
    lock();
    settle(s);
    const unsigned long next = next_event(s);
    unlock();
    return next;
}

void linea_sim_jump(unsigned long instant) {
    struct sim *s = running_sim();
    lock();
    note(s, event_wait, event_set_wait, instant);
    deliver(s, instant);
    unlock();
}

long linea_sim_sleep(unsigned long nanoseconds) {
    struct sim *s = running_sim();
    linea_sim_advance(s->identity, nanoseconds);
    return 0;
}
