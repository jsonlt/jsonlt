# Design rationale

This document explains the reasoning behind key design decisions in JSONLT. Understanding these rationales helps implementers make consistent choices, helps users understand what the format optimizes for, and provides context for future specification evolution.

## Core design philosophy

JSONLT optimizes for a specific set of properties, in roughly this priority order: meaningful version control diffs, human readability and editability, implementation simplicity across languages, and correctness and crash safety. Performance, storage efficiency, and query flexibility are explicitly deprioritized in favor of these goals.

## Append-only storage

JSONLT uses append-only writes rather than in-place updates. The system appends new records; updates append a new version; deletes append a tombstone. Replaying operations produces the logical state.

This choice optimizes for git diffs. When you change a file in place, git sees the entire file as changed, making diffs hard to review. With append-only, changes to different records appear as separate line additions, which git can display and merge cleanly. Append-only also simplifies crash recovery: a partial write at most corrupts the final line, and you can recover the file by truncating the incomplete line. There's no risk of corrupting existing records or leaving the file in an inconsistent state.

The tradeoff is file growth. Without compaction, files grow indefinitely as history accumulates. Compaction addresses this by periodically rewriting the file as a minimal snapshot, but this is an explicit maintenance operation rather than automatic.

## Keys extracted from records

JSONLT requires that keys be extractable from records via a key specifier, rather than storing keys separately or allowing arbitrary key-value pairs. A record with key specifier `"id"` needs an `id` field whose value is the key.

This makes records self-describing: given a record and the key specifier, you can determine its key without external context. Self-describing records are easier to work with in diffs (you can see what record changed), easier to edit manually (the key is visible in the record), and align with document-store conventions where the document contains its identifier.

The alternative (external keys with arbitrary values) would be more flexible but would lose these ergonomic benefits. Records would be harder to understand in isolation, and manual editing would be more error-prone.

## No secondary indexes

JSONLT provides only primary key lookup. The spec excludes secondary indexes, range queries on non-key fields, and query languages. Finding records by non-key fields requires a full scan.

This is a deliberate scope limitation. Secondary indexes add significant complexity to implementation (maintaining index consistency, handling index updates, storage overhead) and specification (index definition syntax, query semantics, consistency guarantees). For the target use cases (small datasets that need version control), full scans are acceptable, and apps needing richer queries can use the local-cache pattern with SQLite or similar.

Keeping the core format minimal also makes cross-language implementation practical. Every language has hash maps; not every language has convenient B-tree implementations.

## Deterministic serialization without full JCS

JSONLT requires deterministic serialization (sorted keys, no whitespace) but does not require full JSON Canonicalization Scheme (RFC 8785) conformance.

Full JCS specifies exact number formatting (no unnecessary trailing zeros, specific exponent notation) that varies across JSON libraries and languages. Requiring JCS would force implementers to either use JCS-specific libraries or build custom number formatting, creating barriers to adoption.

JSONLT's requirements (sorted keys and no whitespace) are achievable with standard JSON libraries in any language. The result is "deterministic enough" for the primary goal: files produced by different implementations will have identical logical content, and diffs will be meaningful. Byte-for-byte identity across implementations is nice-to-have but not essential.

Implementations that want stronger guarantees can conform to JCS; the spec makes this explicitly optional.

## Optimistic concurrency with write-write conflict detection

JSONLT transactions use optimistic concurrency: no locks during the transaction, conflict detection at commit time, and the system detects only write-write conflicts (not read-write).

This model is simpler to build than full serializability and matches the target use cases well. Most JSONLT usage involves single-user or low-contention scenarios where conflicts are rare. When conflicts do occur, detecting write-write conflicts catches the most important case (two processes trying to update the same record) while avoiding the complexity of tracking read sets.

The git-based sync model reinforces this: git itself uses optimistic concurrency with conflict detection at merge time. JSONLT's transaction model mirrors this, providing local atomicity while leaving cross-node conflict resolution to git.

Apps needing stronger isolation can add coordination at the app level, but the common case shouldn't pay for complexity it doesn't need.

## The $-prefix reservation

The specification reserves field names beginning with `$`. Records cannot contain `$`-prefixed fields; only spec-defined constructs like `$jsonlt` (header) and `$deleted` (tombstone) use this prefix.

This provides a clean extension mechanism for future specification versions. Future versions can add new metadata or control fields without conflicting with user data. The choice of `$` follows conventions from MongoDB and JSON Schema, where `$` indicates "special" or "meta" fields.

The spec requires parsers to preserve unrecognized `$`-prefixed fields for forward compatibility. A file written by a newer implementation with new `$`-prefixed fields passes through an older implementation without losing that data.

## Specific limits

The specification defines baseline limits that all implementations support: 1024-byte keys, 1 MiB records, 64 levels of nesting, and 16 tuple elements.

Research into comparable systems and practical sufficiency guided these values. The 1024-byte key limit aligns with common database index key limits (Oracle: 6398 bytes, SQL Server: 900 bytes, PostgreSQL: 2730 bytes). The 1 MiB record size accommodates most practical use cases while preventing memory exhaustion. The 64-level nesting depth exceeds typical JSON usage (most real-world JSON is under 10 levels deep) while remaining within capabilities of JSON parsers. The 16-element tuple limit aligns with database compound key practices (SQL Server: 16 columns, PostgreSQL: 32 columns).

Implementations may support larger limits, and the spec requires that exceeding limits produces clear errors rather than silent truncation or corruption.

## Tombstones rather than physical deletion

Tombstone records (`$deleted: true` plus the key fields) represent deletes rather than physically removing lines from the file.

This maintains the append-only property: deletes are just another operation appended to the log. It also makes deletes visible in diffs (you can see that a record went away, not just that a line disappeared). For sync scenarios, tombstones propagate delete operations to other nodes; without tombstones, a node receiving a sync wouldn't know whether a missing record got deleted or never existed.

Compaction removes tombstones, so they don't accumulate indefinitely in well-maintained files.

<!-- vale Google.Headings = NO -->
## UTF-8 without a BOM
<!-- vale Google.Headings = YES -->

JSONLT files are UTF-8 encoded without a byte order mark (BOM).

UTF-8 doesn't need a BOM (the encoding is self-describing), and BOMs cause problems: they break concatenation, confuse some tools, and add three bytes of noise at the start of every file. The spec requires generators to not produce BOMs but requires parsers to strip them, accommodating files from systems that add BOMs automatically.

## Linefeed-only line endings

JSONLT requires LF (Unix-style) line endings for output, not CRLF (Windows-style).

Consistent line endings ensure identical file hashes across platforms and prevent spurious diffs when editing files on different operating systems. Git's line-ending normalization can handle conversion, but requiring LF from generators avoids the issue entirely.

Parsers handle CRLF gracefully (stripping CR) for interoperability with files that somehow acquired Windows line endings.

## Empty string as valid key

The empty string `""` is explicitly a valid key value.

While perhaps unusual, there's no technical reason to prohibit it, and some use cases genuinely need a "default" or "unnamed" record. Prohibiting empty strings would add a special case without clear benefit.

## Integer key range

Integer keys cover the range −(2^53)+1 to (2^53)−1, the "interoperable" range from RFC 8259.

This range corresponds to integers that IEEE 754 double-precision floating-point can represent exactly. JavaScript (and JSON parsers that use doubles internally) cannot distinguish integers outside this range. Limiting to this range ensures integer keys work correctly across all JSON implementations.

The spec explicitly notes that numbers like `1`, `1.0`, and `1e0` are all the same integer key, requiring implementations to normalize numeric representations.
