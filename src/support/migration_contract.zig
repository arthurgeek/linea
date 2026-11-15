const std = @import("std");
const testing = std.testing;

pub const Variant = enum { regular, checked };
pub const Sanitizer = enum { none, address, thread };
pub const Scope = enum { normal, candidate };
pub const Suspension = enum { clean_yield };
pub const Identity = struct {
    format: u32 = 1,
    runtime_abi: u32 = 1,
    archive_sha256: []const u8,
    registry_sha256: []const u8,
    implementation_sha256: []const u8,
    target: []const u8,
    variant: Variant,
    sanitizer: Sanitizer,
};
pub const BehaviorApproval = struct {
    id: []const u8,
    registry_sha256: []const u8,
    implementation_sha256: []const u8,
    scope: Scope,
    entries: []const []const u8,
    suspensions: []const Suspension,
};
pub const TargetValidation = struct {
    behavior: []const u8,
    identity: Identity,
    scope: Scope,
    entries: []const []const u8,
    suspensions: []const Suspension,
};
pub const DisableReason = enum {
    object_only,
    missing_metadata,
    malformed_metadata,
    unsupported_archive,
    archive_changed,
    registry_changed,
    unsupported_variant,
    missing_approval,
    missing_validation,
    candidate_scope,
    runtime_unavailable,
    snapshot_unavailable,
    operational_failure,
    unauthorized_scope,
};
/// The caller owns the immutable entry/path records for the entire emission.
pub const ApprovedScope = struct {
    entries: []const []const u8 = &.{},
    suspensions: []const Suspension = &.{},
};
pub const Availability = union(enum) {
    disabled: DisableReason,
    enabled: Approved,
};
pub const Request = struct {
    target: []const u8,
    variant: Variant,
    sanitizer: Sanitizer = .none,
    registry_sha256: []const u8,
    /// Only the matching runtime implementation may supply this capability.
    runtime_available: bool = false,
    entries: []const []const u8 = &.{},
    suspensions: []const Suspension = &.{},
};

pub fn sha256(bytes: []const u8) [64]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}

fn validDigest(digest: []const u8) bool {
    if (digest.len != 64) return false;
    for (digest) |c| if (!std.ascii.isDigit(c) and !(c >= 'a' and c <= 'f')) return false;
    return true;
}

fn sameIdentity(a: Identity, b: Identity) bool {
    return a.format == b.format and a.runtime_abi == b.runtime_abi and
        std.mem.eql(u8, a.archive_sha256, b.archive_sha256) and
        std.mem.eql(u8, a.registry_sha256, b.registry_sha256) and
        std.mem.eql(u8, a.implementation_sha256, b.implementation_sha256) and
        std.mem.eql(u8, a.target, b.target) and a.variant == b.variant and a.sanitizer == b.sanitizer;
}

/// Identity is derived by a build; approvals come from separately reviewed
/// compiler inputs. An archive or its sidecar cannot issue either approval.
pub const Approved = struct { archive_sha256: [64]u8, validation: usize, scope: ApprovedScope = .{} };
pub const Eligibility = union(enum) { disabled: DisableReason, eligible: Approved };

/// Checks cheap evidence and requested scope before loading archive bytes.
pub fn eligibility(identity: Identity, request: Request, approvals: []const BehaviorApproval, validations: []const TargetValidation) Eligibility {
    if (!request.runtime_available) return .{ .disabled = .runtime_unavailable };
    if (identity.format != 1 or identity.runtime_abi != 1 or
        !validDigest(identity.archive_sha256) or !validDigest(identity.registry_sha256) or
        !validDigest(identity.implementation_sha256)) return .{ .disabled = .malformed_metadata };
    if (!std.mem.eql(u8, identity.registry_sha256, request.registry_sha256)) return .{ .disabled = .registry_changed };
    if (!std.mem.eql(u8, identity.target, request.target) or identity.variant != request.variant or
        identity.sanitizer != request.sanitizer) return .{ .disabled = .unsupported_variant };
    var candidate = false;
    var approved_behavior = false;
    var scope_refused = false;
    for (approvals) |approval| {
        if (approval.id.len == 0 or !std.mem.eql(u8, approval.registry_sha256, identity.registry_sha256) or
            !std.mem.eql(u8, approval.implementation_sha256, identity.implementation_sha256)) continue;
        if (approval.scope != .normal) {
            candidate = true;
            continue;
        }
        approved_behavior = true;
        for (validations, 0..) |validation, index| {
            if (!std.mem.eql(u8, validation.behavior, approval.id) or !sameIdentity(validation.identity, identity)) continue;
            if (validation.scope != .normal) {
                candidate = true;
                continue;
            }
            if (validation.entries.len == 0 or validation.suspensions.len == 0) continue;
            var entries_valid = true;
            for (validation.entries) |entry| {
                var covered = false;
                for (approval.entries) |reviewed| covered = covered or std.mem.eql(u8, entry, reviewed);
                if (entry.len == 0 or !covered) entries_valid = false;
            }
            for (validation.suspensions) |path| {
                var covered = false;
                for (approval.suspensions) |reviewed| covered = covered or path == reviewed;
                if (!covered) entries_valid = false;
            }
            if (!entries_valid) continue;
            if (request.entries.len == 0 or request.suspensions.len == 0) return .{ .disabled = .unauthorized_scope };
            var requested = true;
            for (request.entries) |entry| {
                var covered = false;
                for (validation.entries) |allowed| covered = covered or std.mem.eql(u8, entry, allowed);
                if (!covered) requested = false;
            }
            for (request.suspensions) |path| {
                var covered = false;
                for (validation.suspensions) |allowed| covered = covered or path == allowed;
                if (!covered) requested = false;
            }
            if (!requested) {
                scope_refused = true;
                continue;
            }
            return .{ .eligible = .{
                .archive_sha256 = identity.archive_sha256[0..64].*,
                .validation = index,
                .scope = .{ .entries = request.entries, .suspensions = request.suspensions },
            } };
        }
    }
    return .{ .disabled = if (scope_refused) .unauthorized_scope else if (candidate) .candidate_scope else if (approved_behavior) .missing_validation else .missing_approval };
}

pub fn validateArchive(archive: []const u8, approved: Approved) Availability {
    if (!std.mem.startsWith(u8, archive, "!<arch>\n")) return .{ .disabled = .unsupported_archive };
    const hash = sha256(archive);
    if (!std.mem.eql(u8, &hash, &approved.archive_sha256)) return .{ .disabled = .archive_changed };
    return .{ .enabled = approved };
}

pub fn assess(archive: []const u8, identity: Identity, request: Request, approvals: []const BehaviorApproval, validations: []const TargetValidation) Availability {
    return switch (eligibility(identity, request, approvals, validations)) {
        .disabled => |reason| .{ .disabled = reason },
        .eligible => |approved| validateArchive(archive, approved),
    };
}

const fixture_archive = "!<arch>\nfixture";
const fixture_identity: Identity = .{
    .archive_sha256 = "d05e51c47e252b596c0d3716e23dba96a2473b37b7e562703789e510b7ccb202",
    .registry_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    .implementation_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    .target = "aarch64-macos",
    .variant = .regular,
    .sanitizer = .none,
};
const fixture_request: Request = .{ .target = "aarch64-macos", .variant = .regular, .registry_sha256 = fixture_identity.registry_sha256, .runtime_available = true, .entries = &.{"entry-manifest-1"}, .suspensions = &.{.clean_yield} };
const fixture_behavior = [_]BehaviorApproval{.{ .id = "review-1", .registry_sha256 = fixture_identity.registry_sha256, .implementation_sha256 = fixture_identity.implementation_sha256, .scope = .normal, .entries = &.{"entry-manifest-1"}, .suspensions = &.{.clean_yield} }};
const fixture_validation = [_]TargetValidation{.{ .behavior = "review-1", .identity = fixture_identity, .scope = .normal, .entries = &.{"entry-manifest-1"}, .suspensions = &.{.clean_yield} }};

test "migration certification: approved exact combination and changed archive" {
    try testing.expect(assess(fixture_archive, fixture_identity, fixture_request, &fixture_behavior, &fixture_validation) == .enabled);
    try testing.expectEqual(DisableReason.archive_changed, assess("!<arch>\nmutated", fixture_identity, fixture_request, &fixture_behavior, &fixture_validation).disabled);
}

test "migration certification: identity cannot mint approval or platform validation" {
    try testing.expectEqual(DisableReason.missing_approval, assess(fixture_archive, fixture_identity, fixture_request, &.{}, &fixture_validation).disabled);
    try testing.expectEqual(DisableReason.missing_validation, assess(fixture_archive, fixture_identity, fixture_request, &fixture_behavior, &.{}).disabled);
    var changed = fixture_identity;
    changed.implementation_sha256 = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    try testing.expectEqual(DisableReason.missing_approval, assess(fixture_archive, changed, fixture_request, &fixture_behavior, &fixture_validation).disabled);
}

test "migration certification: candidate and wrong archive variants remain pinned" {
    var candidate = fixture_behavior;
    candidate[0].scope = .candidate;
    try testing.expectEqual(DisableReason.candidate_scope, assess(fixture_archive, fixture_identity, fixture_request, &candidate, &fixture_validation).disabled);
    var request = fixture_request;
    request.variant = .checked;
    try testing.expectEqual(DisableReason.unsupported_variant, assess(fixture_archive, fixture_identity, request, &fixture_behavior, &fixture_validation).disabled);
    request = fixture_request;
    request.sanitizer = .address;
    try testing.expectEqual(DisableReason.unsupported_variant, assess(fixture_archive, fixture_identity, request, &fixture_behavior, &fixture_validation).disabled);
}

test "migration certification: missing runtime ABI and unsupported container stay pinned" {
    var request = fixture_request;
    request.runtime_available = false;
    try testing.expectEqual(DisableReason.runtime_unavailable, assess(fixture_archive, fixture_identity, request, &fixture_behavior, &fixture_validation).disabled);
    try testing.expectEqual(DisableReason.unsupported_archive, assess("!<thin>\nfixture", fixture_identity, fixture_request, &fixture_behavior, &fixture_validation).disabled);
}

pub fn fromMetadata(gpa: std.mem.Allocator, archive: []const u8, metadata: ?[]const u8, request: Request, approvals: []const BehaviorApproval, validations: []const TargetValidation) error{OutOfMemory}!Availability {
    const bytes = metadata orelse return .{ .disabled = .missing_metadata };
    const parsed = std.json.parseFromSlice(Identity, gpa, bytes, .{}) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .disabled = .malformed_metadata },
    };
    defer parsed.deinit();
    return assess(archive, parsed.value, request, approvals, validations);
}

test "migration certification: absent malformed or forged sidecar cannot activate" {
    try testing.expectEqual(DisableReason.missing_metadata, (try fromMetadata(testing.allocator, fixture_archive, null, fixture_request, &fixture_behavior, &fixture_validation)).disabled);
    try testing.expectEqual(DisableReason.malformed_metadata, (try fromMetadata(testing.allocator, fixture_archive, "{", fixture_request, &fixture_behavior, &fixture_validation)).disabled);
    const metadata = try std.json.Stringify.valueAlloc(testing.allocator, fixture_identity, .{});
    defer testing.allocator.free(metadata);
    try testing.expect((try fromMetadata(testing.allocator, fixture_archive, metadata, fixture_request, &fixture_behavior, &fixture_validation)) == .enabled);
    try testing.expectEqual(DisableReason.missing_approval, (try fromMetadata(testing.allocator, fixture_archive, metadata, fixture_request, &.{}, &.{})).disabled);
}

test "migration certification: new registry and uncertified entry manifests stay pinned" {
    var request = fixture_request;
    request.registry_sha256 = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    try testing.expectEqual(DisableReason.registry_changed, assess(fixture_archive, fixture_identity, request, &fixture_behavior, &fixture_validation).disabled);
    var validations = fixture_validation;
    validations[0].entries = &.{};
    try testing.expectEqual(DisableReason.missing_validation, assess(fixture_archive, fixture_identity, fixture_request, &fixture_behavior, &validations).disabled);
    validations = fixture_validation;
    validations[0].suspensions = &.{};
    try testing.expectEqual(DisableReason.missing_validation, assess(fixture_archive, fixture_identity, fixture_request, &fixture_behavior, &validations).disabled);
    validations = fixture_validation;
    validations[0].scope = .candidate;
    try testing.expectEqual(DisableReason.candidate_scope, assess(fixture_archive, fixture_identity, fixture_request, &fixture_behavior, &validations).disabled);
}

pub const Input = struct { name: []const u8, bytes: []const u8 };
pub fn implementationDigest(config: []const u8, inputs: []const Input) [64]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hashPart(&hash, config);
    for (inputs) |input| {
        hashPart(&hash, input.name);
        hashPart(&hash, input.bytes);
    }
    return std.fmt.bytesToHex(hash.finalResult(), .lower);
}

fn hashPart(hash: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    var size: [8]u8 = undefined;
    std.mem.writeInt(u64, &size, @intCast(bytes.len), .little);
    hash.update(&size);
    hash.update(bytes);
}

test "migration certification: changed native input or build configuration invalidates approval" {
    const before = implementationDigest("aarch64-macos regular no-asan-tsan", &.{.{ .name = "foreign.c", .bytes = "audited implementation" }});
    const changed = implementationDigest("aarch64-macos regular no-asan-tsan", &.{.{ .name = "foreign.c", .bytes = "changed implementation" }});
    const checked = implementationDigest("aarch64-macos checked no-asan-tsan", &.{.{ .name = "foreign.c", .bytes = "audited implementation" }});
    try testing.expect(!std.mem.eql(u8, &before, &changed));
    try testing.expect(!std.mem.eql(u8, &before, &checked));
    var identity = fixture_identity;
    identity.implementation_sha256 = &changed;
    var approvals = fixture_behavior;
    approvals[0].implementation_sha256 = &before;
    try testing.expectEqual(DisableReason.missing_approval, assess(fixture_archive, identity, fixture_request, &approvals, &fixture_validation).disabled);
}

pub const Audit = struct { format: u32, approvals: []const BehaviorApproval };
pub const Validation = struct { format: u32, validations: []const TargetValidation };

test "migration certification: target evidence cannot widen reviewed entry scope" {
    var validations = fixture_validation;
    validations[0].entries = &.{"unaudited-entry"};
    try testing.expectEqual(DisableReason.missing_validation, assess(fixture_archive, fixture_identity, fixture_request, &fixture_behavior, &validations).disabled);
}

test "migration certification: enablement binds requested entry and suspension scope" {
    var request = fixture_request;
    request.entries = &.{"entry-2"};
    try testing.expectEqual(DisableReason.unauthorized_scope, assess(fixture_archive, fixture_identity, request, &fixture_behavior, &fixture_validation).disabled);
    request = fixture_request;
    request.entries = &.{};
    try testing.expectEqual(DisableReason.unauthorized_scope, assess(fixture_archive, fixture_identity, request, &fixture_behavior, &fixture_validation).disabled);
    request = fixture_request;
    request.suspensions = &.{};
    try testing.expectEqual(DisableReason.unauthorized_scope, assess(fixture_archive, fixture_identity, request, &fixture_behavior, &fixture_validation).disabled);
    const approved = assess(fixture_archive, fixture_identity, fixture_request, &fixture_behavior, &fixture_validation).enabled;
    try testing.expectEqualStrings("entry-manifest-1", approved.scope.entries[0]);
    try testing.expectEqual(Suspension.clean_yield, approved.scope.suspensions[0]);
}

test "migration certification: metadata parser preserves allocation failures" {
    const metadata = try std.json.Stringify.valueAlloc(testing.allocator, fixture_identity, .{});
    defer testing.allocator.free(metadata);
    try testing.expectError(error.OutOfMemory, fromMetadata(testing.failing_allocator, fixture_archive, metadata, fixture_request, &fixture_behavior, &fixture_validation));
}
