import Foundation

/// Lenient decoder for `claude agents --json --all` output.
///
/// Contract (docs/HARNESS.md, CLAUDE.md "Boundary parsing, lenient"):
/// - Top level must be a JSON array. Anything else → one top-level issue,
///   zero sessions.
/// - Each element is decoded as a `JSONValue` object first; known fields are
///   pulled out by name and type-checked; every remaining key lands in
///   `extra` untouched.
/// - `cwd` (string), `kind` (string), `startedAt` (number, epoch ms) are
///   required. A missing or mistyped one is an issue for that element; the
///   element is still emitted when `cwd` is present (with `kind`
///   defaulting to `.background` and `startedAt` to distantPast) so the
///   roster never goes empty because one row changed shape.
/// - Unknown enum strings (`kind`, `state`, `status`) are an issue and
///   decode as nil (or `.background` for kind), with the raw string kept in
///   `extra["<field>"]`.
/// - `id` falls back to `sessionId`, then to `cwd@startedAt`.
/// - Element order is preserved. No sorting here; presentation sorts.
public enum RosterDecoder {
    public static func decode(_ data: Data) -> RosterDecodeResult {
        fatalError("TODO: RosterDecoder.decode — spawn-owned")
    }
}
