#include <sqlite3.h>
#include <stdint.h>

/* SQLITE_TRANSIENT is a cast pointer constant, which a Linea declaration
 * cannot spell, so this shim passes it: SQLite copies the text before the call
 * returns. */
int32_t sqlite_shim_bind_text(sqlite3_stmt *statement, int32_t index, const char *text, int32_t length) {
    return sqlite3_bind_text(statement, index, text, length, SQLITE_TRANSIENT);
}
