# 128. Qualified enum constructors are contextual callables

Status: Accepted — 2026-09-10; extends 0105 and 0123.

## Context

Error wrapping repeats noncapturing closures such as
`map_err(|sink error| Failure.Parse(error))`. A constructor already specifies the
payload transfer; the expected callback supplies its callable shape.

## Decision

A qualified enum constructor with one payload can convert to an expected
structural callable with one sink parameter and no default or stable-address
requirement. The payload has no declared parameter name, so it adopts the
contextual name. Payload and result context settle every generic enum argument;
ordinary bound validation still applies. Inferred `.Variant` conversion and
multi-payload callable construction are outside this decision.

Checking validates the actual payload-owner transfer against the promised
callable carries contract, using the selected variant's payload path. It may
not manufacture an independence promise for a borrowed payload. The exact
selected signature is recorded as an ordinary function value.

The existing body-origin representation gains a constructor identity for the
new executable body, keyed in its enclosing generic context. Instantiation
records its specialized body; MIR uses ordinary enum construction, function
addresses and calls. No new callable type, runtime representation, pass, implicit
copy, or cleanup operation is introduced.

## Consequences

Simple wrappers become `map_err(Failure.Parse)`. Closures remain appropriate
when conversion logs, releases an owner, extracts fields, or otherwise computes
an error. Callable parameter naming is contextual for constructors, while named
functions retain their declared exact signatures.
