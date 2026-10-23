#include <sqlite3.h>
#include <stdint.h>

/* `SQLITE_TRANSIENT` is `(sqlite3_destructor_type)-1`, a function pointer C
 * spells with a cast, which asks SQLite to copy the text before returning. */
int32_t sqlite_shim_bind_text(sqlite3_stmt *statement, int32_t index, const char *text, int32_t length) {
    return sqlite3_bind_text(statement, index, text, length, SQLITE_TRANSIENT);
}

/* `sqlite3_prepare_v2` compiles the first statement and sets `tail` to the
 * text after it. Returning the unused byte count lets Linea refuse a string
 * that holds a second statement without subtracting two C addresses. */
int32_t sqlite_shim_prepare(sqlite3 *database, const char *sql, int32_t length, sqlite3_stmt **statement, int32_t *unused) {
    const char *tail = sql + length;
    int32_t code = sqlite3_prepare_v2(database, sql, length, statement, &tail);
    *unused = (int32_t)(sql + length - tail);
    return code;
}

/* A statement's last failure sentence lives on its connection. Reading it here
 * avoids minting a second linear `DatabaseHandle` from `sqlite3_db_handle`. */
const char *sqlite_shim_statement_message(sqlite3_stmt *statement) {
    return sqlite3_errmsg(sqlite3_db_handle(statement));
}
