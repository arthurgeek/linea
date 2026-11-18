#ifndef LINEA_COMPLETION_H
#define LINEA_COMPLETION_H

struct linea_completion;
struct linea_op;

struct linea_completion_result {
    void *pending;
    long result;
    int expired;
    int cancel_submitted;
};

/* One carrier drives submissions and completions. Setup and teardown require
 * no concurrent owner. NULL preserves readiness execution.
 * A nonzero submission cookie retains pending and its bytes until next
 * returns that pending record. Cancel alone never relinquishes that lease. */
struct linea_completion *linea_completion_open(int eventfd);
void linea_completion_close(struct linea_completion *queue);
unsigned long linea_completion_submit(struct linea_completion *queue, struct linea_op *operation, void *pending);
void linea_completion_cancel(struct linea_completion *queue, unsigned long cookie);
int linea_completion_next(struct linea_completion *queue, struct linea_completion_result *result);
void linea_completion_flush(struct linea_completion *queue);
int linea_completion_retry(struct linea_completion *queue);
int linea_completion_replay_stale(struct linea_completion *queue, unsigned long cookie);

#endif
