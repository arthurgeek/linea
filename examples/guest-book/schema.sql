-- One row per signature. SQLite numbers the rows, and stamps each with the
-- time it was signed as a 64-bit Unix timestamp, in UTC.
CREATE TABLE IF NOT EXISTS entries (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    message TEXT NOT NULL,
    signed_at INTEGER NOT NULL DEFAULT (unixepoch())
);
