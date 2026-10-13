# 108. An internal name stops at its root

Status: Accepted - 2026-09-02

## Context

A module-private name is too narrow for an invariant established across several
modules of one library. A public name is too broad: using it for cooperation
inside that library also publishes it to every importing root. The standard
library needs this distinction both for constructing argument strings and for
passing opaque text to its I/O implementation without exposing raw storage to
programs.

A compilation is not the boundary. It contains the primary root and the
standard library, and will contain independently loaded dependency libraries.
Filesystem ancestry is not the boundary either: import resolution, manifests
and in-memory programs already make source roots a loader decision.

## Decision

**A declaration written `internal` may be named by modules in the same loaded
root and by no module in another root.** The loader assigns every module a typed
`RootId`. The primary root, standard-library root and each independently loaded
dependency root have distinct identities.

Root identity is independent of standard-library authority. Existing privileges
for trusted runtime declarations continue to use the module's library identity;
sharing a root grants no such privilege.

The resolver records one reach for each binding: declaring module, loaded root
or public. Private declarations have module reach, `internal` declarations have
root reach, and `pub` and `opaque` declarations have public reach. Every route
that names a declaration uses the same reach relation.

A re-export may preserve or narrow its source's reach and may not widen it. An
internal declaration can therefore be carried across its root with `internal
use`, but `pub use` of one is refused. Internal declarations remain subject to
unused-declaration checking because every possible caller in their root is
present. Public and opaque declarations retain their external-caller exemption.

Opacity remains module-relative and separate from naming reach. Another module
in the same root may call an internal operation involving an opaque type, but it
may not inspect or construct that type's representation.

## Consequences

Libraries can share narrow implementation operations without publishing them as
API. Programs and unrelated dependencies cannot acquire that access merely by
being compiled together or placed under a related directory.

An access check is one module comparison or one `RootId` comparison. Reach is
stored per binding and sized by the binding domain; no access scans modules or
filesystem paths.

The loader must preserve root identity anywhere it constructs a `Program`, and
tools that list module members or workspace exports must filter with the same
requester-relative reach as semantic lookup.

## Alternatives considered

**Add `pub(root)`.** Rejected because Linea has no visibility argument syntax,
and a distinct word makes the three naming reaches exhaustive without turning a
source-root identity into a source expression.

**Treat every module in one compilation as internal.** Rejected because a
program and its dependencies share a compilation while remaining separate
publication boundaries.

**Infer roots from filesystem ancestry.** Rejected because the loader already
resolves manifests, reserved roots and in-memory sources; paths are inputs to
that decision rather than stable semantic identity.

**Use the standard-library bit as root identity.** Rejected because authority to
declare trusted runtime operations and permission to name sibling declarations
are separate questions, and future dependency libraries need the latter without
the former.
