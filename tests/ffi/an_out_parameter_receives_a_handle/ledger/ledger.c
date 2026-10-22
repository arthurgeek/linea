#include <stdint.h>
#include <stdlib.h>

struct ledger {
    int64_t opening;
};

/* Like sqlite3_open, this writes a ledger through `out` even when it reports
 * a failure, and the caller must close it either way. */
int32_t ledger_open(struct ledger **out, int64_t opening) {
    *out = malloc(sizeof(struct ledger));
    if (*out == NULL) return 2;
    (*out)->opening = opening;
    return opening < 0 ? 1 : 0;
}

int64_t ledger_opening(const struct ledger *ledger) { return ledger->opening; }

void ledger_close(struct ledger *ledger) { free(ledger); }
