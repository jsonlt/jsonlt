# Future directions

This document captures ideas the project considered but deferred from JSONLT 1.0, explicit non-goals, and thoughts on potential future evolution. This serves as a reference for managing feature requests and contributor expectations.

Nothing in this document commits to future features. These are possibilities to consider, not planned work.

## Explicitly out of scope for v1

These features were deliberately excluded from the initial specification.

### Secondary indexes

The ability to create indexes on non-key fields for efficient queries. The spec excludes this because it adds significant specification and implementation complexity, the local-cache pattern (JSONLT plus SQLite) addresses this need for apps requiring rich queries, and keeping the core format minimal enables cross-language implementation.

The suggested approach for apps needing indexed queries is to derive a SQLite database from JSONLT files and query the cache.

### Range queries on keys

Even for key-based queries, JSONLT only supports exact lookup. Range queries ("all keys between A and B") are not supported.

The spec excludes this because implementations store the logical state as a hash map (O(1) lookup), not a sorted structure. Supporting range queries would require either sorted storage (complicating the format) or O(n) scans (not better than find with a predicate).

Apps needing range queries can use compound keys that make the range dimension the first element, allowing exact prefix matching, or use a local cache with indexes on the range dimension.

### Query language

JSONLT provides only programmatic predicates for filtering (a function that takes a record and returns a boolean). There's no query language, no filter syntax, no MongoDB-style query objects.

The spec excludes this to keep the specification minimal and implementation-portable. A query language would require parsing, validation, and cross-language-consistent evaluation, which adds significant complexity for a format focused on version control integration.

Apps needing query capabilities can build them at the app layer or use a local cache with SQL.

### Streaming reads

JSONLT requires loading the entire logical state into memory. There's no streaming mode that yields records one at a time without full state reconstruction.

The spec excludes this because the logical state requires replaying all operations, including handling tombstones that delete earlier records. True streaming would require different semantics (yielding operations rather than current state) or would miss deletions.

For large files that don't fit in memory, JSONLT is not the right tool.

### Automatic compaction

Compaction is an explicit operation that apps invoke. There's no automatic compaction based on file size, operation count, or tombstone ratio.

The spec excludes this because automatic compaction has policy implications (when to compact? how to handle failures?) that are better left to apps. Different use cases have different compaction needs.

Apps can build compaction strategies suited to their write patterns.

### Schema enforcement

JSONLT supports optional schema validation via JSON Schema references in headers, but validation is not normatively mandatory. Parsers may ignore schemas; generators may skip validation.

The spec excluded strict schema enforcement because it would complicate implementations and limit flexibility during schema evolution. Apps can add validation at the app layer if needed.

### Encryption

JSONLT files are plain text with no encryption support. Sensitive data is visible to anyone with file access.

The spec excludes this because encryption is orthogonal to the format's goals and is better handled at other layers (filesystem encryption, encrypted git repositories, app-layer encryption before serialization).

Apps storing sensitive data need protections outside JSONLT.

## Extension points in the current design

The v1 specification includes deliberate extension points for future evolution.

### Reserved $-prefix fields

Field names beginning with `$` belong to the specification. Future versions can define new `$`-prefixed fields without conflicting with user data. Parsers preserve unrecognized `$`-prefixed fields for forward compatibility.

Potential future uses include metadata fields like `$created` and `$modified` timestamps, relationship fields linking records, or system fields for replication or versioning.

### Header meta field

The header's `meta` field accepts arbitrary JSON, providing a space for app-specific or experimental metadata without polluting the core specification.

Custom indexing hints, app versioning, or experimental features before standardization can use this field.

### Header schema field

The optional `schema` and `$schema` fields support JSON Schema validation. Future specification versions could define tighter integration, such as mandatory validation modes or schema evolution semantics.

### Forward-compatible field preservation

Parsers preserve unrecognized `$`-prefixed fields, allowing files from newer implementations to pass through older implementations without data loss.

This enables gradual rollout of new features. Implementations upgrade independently.

## Ideas considered for future versions

People have discussed these ideas but made no commitments. They may never happen.

### Append-only operation log mode

An alternative to current semantics where the file is purely an operation log, never compacted, with the logical state always computed by full replay. This would preserve complete history at the cost of unbounded file growth.

Use case: audit logs, event sourcing where history is the primary concern.

Consideration: this could be a header flag (`"mode": "log"`) rather than a separate format.

### Differential updates

Instead of full record replacement on upsert, the ability to express partial updates (set field X to Y, increment field Z). This would produce smaller diffs and reduce redundancy.

Challenges: update semantics are hard to define (what happens when updating a missing field?), cross-language consistency is harder, and merge conflict resolution becomes harder.

### Record-level timestamps

Automatic `$modified` timestamps on records, managed by generators. Would enable time-based queries and conflict resolution strategies.

Challenges: clock synchronization across machines, timestamp format (ISO 8601? Unix epoch?), whether timestamps are normative or advisory.

### Soft delete with retention

Instead of immediate tombstone semantics, a soft delete that marks records as deleted but retains them for a configurable period. Compaction would remove only tombstones older than the retention period.

Use case: undo features, grace periods before permanent deletion.

Challenges: retention policy specification, complexity in state computation.

### Multi-table files

Allowing many logical tables in a single file, with records tagged by table name.

Use case: reducing file proliferation for related small tables.

Challenges: complicates the mental model, may not provide big gains over many files.

### Binary variant

A binary serialization of JSONLT for applications prioritizing performance over human readability. Would sacrifice the version-control-friendly properties for efficiency.

Consideration: this would be a different format, not a JSONLT extension. Applications prioritizing performance typically want SQLite anyway.

<!-- vale Google.Headings = NO -->
### CRDT-based merge semantics
<!-- vale Google.Headings = YES -->

Instead of last-write-wins, conflict-free replicated data type (CRDT) semantics that can automatically merge concurrent changes. Would enable real-time sync without conflicts.

<!-- vale Google.Colons = NO -->
Challenges: CRDTs constrain data models, add high overhead, and this may work better at a different layer.
<!-- vale Google.Colons = YES -->

## Versioning philosophy

The specification uses a version field in headers, currently fixed at `1`. Future considerations around versioning include backward compatibility (where new versions are readable by old parsers where possible, using forward-compatible extension points rather than breaking changes), feature flags versus versions (whether minor features use version increments like 1.1, 1.2, or capability flags in headers), and a clear deprecation path for removing features (with deprecation periods and migration guidance).

The goal is stability: apps depending on JSONLT expect specification changes to not break their code.

## How to propose changes

For the specification repository, open an issue describing the use case, proposed solution, and alternatives considered. Discussion happens in issues before any specification changes.

Major changes need a design document in the proposals directory, implementation experience in at least one language, and analysis of impact on existing implementations.

The bar for adding features is intentionally high. JSONLT's value comes partly from simplicity; features that add complexity need to justify their cost.
