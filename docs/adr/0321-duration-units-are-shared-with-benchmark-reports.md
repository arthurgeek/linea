# 321. Duration units are shared with benchmark reports

Status: Accepted — 2026-11-27. Supersedes the seconds-only duration display
clause of [0174](0174-logging-is-a-leveled-structured-logger-and-http-logs-through-middleware.md).

## Context

A multi-millisecond benchmark printed millions of nanoseconds per iteration.
Duration already selected readable units, but the benchmark reporter bypassed
that choice. An average can be a fraction of one nanosecond, so constructing
an integer Duration from a truncated average loses information.

## Decision

Keep one unit-selection function in std.time, shared by Duration display and
benchmark reports: ns, µs, ms, s, min. Duration remains an exact UInt64 count of
nanoseconds. Default display writes whole minutes and any exact remaining
Duration, such as 1min30.125s or 1min1ns.

Benchmark reports choose a unit from the median per-iteration duration and use
it consistently for median, minimum and p90. Compute each average from the raw
batch duration and actual repetition count before formatting three decimal
places. Raw samples and statistics stay in nanoseconds per batch.

## Consequences

Long reports are readable without changing clock arithmetic, measurements,
calibration or workload boundaries. Fractional nanosecond averages remain
visible. Rounded benchmark text is presentation, not a replacement for raw data.

## Alternatives considered

- Fixed nanoseconds: requires readers to decode large values.
- Independent benchmark unit rules: duplicates std.time behavior.
- Truncate the average into Duration: loses fractional nanoseconds.
- Round default Duration values: needlessly discards exact remainders.
