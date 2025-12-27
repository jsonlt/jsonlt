# Database classification and comparable systems

This document characterizes JSONLT from a database design perspective, situating it within established taxonomy and identifying comparable systems. Understanding where JSONLT fits among data storage systems helps clarify its intended use cases and design tradeoffs.

## Classification

JSONLT occupies an interesting niche that doesn't fit neatly into standard database taxonomy categories. At its core, it's a log-structured key-value store with JSON documents as values, but specific design choices give it a distinctive profile.

### Data model

JSONLT is a key-value store where values are JSON objects. Keys can be scalar (strings or integers) or compound (tuples of up to 16 elements). The specification describes the computed state as a "map from keys to records," which is exactly a key-value abstraction. Unlike pure key-value stores, JSONLT requires that keys be extractable from the value itself via a key specifier, which gives it a slight document-store flavor (the key is part of the document rather than an external identifier).

### Storage architecture

The storage architecture is append-only and log-structured. The system appends all mutations as operations (upserts or tombstone deletes); replaying these operations in order produces the logical state. This is fundamentally an operation log that happens to be the primary storage format rather than a write-ahead log backing a separate data structure. Compaction periodically rewrites the log as a minimal snapshot.

The physical format is deliberately text-based (UTF-8 JSON Lines) rather than binary. This is unusual for database systems and reflects the optimization for version control diffs and human readability. Most log-structured stores use binary formats for efficiency.

### Query capabilities

The query model is intentionally minimal: single-key lookup, existence check, full scan, and predicate-filtered scan. The spec excludes secondary indexes, range queries on keys, and joins. Everything beyond single-key access requires a full scan and is O(n) in the number of records.

### Concurrency model

JSONLT uses optimistic concurrency control with write-write conflict detection at commit time. Transactions provide snapshot isolation within their scope, but there's no read-write conflict detection. This provides something weaker than serializable isolation, closer to snapshot isolation with first-committer-wins semantics for conflicting writes.

File locking coordinates access between processes, with advisory locks acquired during write operations and at transaction commit time.

## Comparable systems

### Bitcask

The closest architectural match is Bitcask, the storage engine originally developed for Riak. Both systems are append-only log-structured hash tables where the system holds the entire keyspace in memory and all writes append to a log file. Both have similar compaction semantics, merging the log into a snapshot that removes tombstones and superseded entries.

The key differences are that Bitcask uses a binary format optimized for throughput, while JSONLT uses text optimized for diffability. Bitcask also keeps only key metadata (with value offsets) in memory while values remain on disk, enabling datasets larger than RAM. JSONLT loads entire records into memory, limiting practical dataset size.

### Event sourcing patterns

JSONLT shares significant DNA with event sourcing patterns. The append-only log of state-changing operations that gets replayed to compute current state is exactly how event-sourced systems work. The difference is that event sourcing typically uses domain events (CustomerRegistered, OrderPlaced) while JSONLT uses state snapshots (the full record after modification). JSONLT is closer to "state sourcing" or a command log where each entry is a complete state rather than a delta.

### CouchDB

CouchDB provides an interesting comparison point. The designers built it around append-only storage (before compaction), used JSON documents, and made replication and synchronization first-class concerns. The underlying philosophy of append-only storage for sync resonates with JSONLT's design goals.

CouchDB is far more sophisticated, offering multi-version concurrency control, MapReduce views for secondary indexes, and rich queries. But both systems share the insight that append-only storage simplifies replication and conflict resolution.

### Version-controlled data stores

For the version-control-friendly aspect, the closest comparison is BEADS (the distributed issue tracker that inspired JSONLT's design), which uses JSONL as a sync format between SQLite instances via git.

Fossil, the version control system, embeds a SQLite database inside its repository but faces similar concerns about meaningful diffs of structured data. Other "database in git" experiments (storing YAML, JSON, or TOML files in repositories) share the same optimization target of making structured data play nicely with version control semantics.

### SQLite

SQLite is worth mentioning as the canonical embedded single-file database, though architecturally it differs entirely: it uses B-tree storage, binary page format, and full SQL query capabilities. The comparison is more about deployment model (embedded, single-file, zero-configuration) than internal architecture.

SQLite excels at rich queries and larger datasets but produces opaque binary diffs that don't integrate with text-based version control workflows.

### LevelDB and RocksDB

LevelDB and RocksDB are log-structured merge-tree (LSM) stores, which share the append-only write path but have sophisticated multi-level compaction and sorted string table (SSTable) storage enabling efficient range queries. They target different access patterns (high write throughput and range scans over large datasets) rather than the human-readable, diff-friendly storage that JSONLT targets.

## Design tradeoffs

JSONLT makes explicit tradeoffs that define its niche.

### What JSONLT optimizes for

JSONLT prioritizes human readability, with plain text JSON that any text editor can read and edit. It produces meaningful diffs where changes to different keys produce clean, reviewable version control diffs. The format maintains simplicity through a minimal specification that developers can correctly build in any language. Compaction uses atomic file replacement rather than in-place updates, which simplifies crash recovery.

### What JSONLT trades away

These optimizations come at the cost of query flexibility, since there are no secondary indexes or range queries. Storage efficiency suffers because text-based JSON is verbose compared to binary formats. Scalability suffers because the entire dataset needs to fit in memory. Scan performance is O(n) for anything beyond single-key lookup.

### Target use cases

The sweet spot for JSONLT is configuration data, app state, or structured records that need to be version-controlled alongside code, edited by humans, and synchronized via git or similar tools. This niche is typically served by ad-hoc YAML or JSON files, but JSONLT adds structure for keyed access, explicit delete semantics, transactional writes, and optional schema validation.

From a CAP perspective (considering git-based distribution), JSONLT is an eventually consistent system that resolves conflicts at the sync layer (git merge) rather than the database layer. The format ensures that non-conflicting changes to different keys produce clean automatic merges, while conflicting changes to the same key surface as visible merge conflicts requiring human resolution.

## Architectural pattern: versioned sync target with local cache

One of the most powerful uses of JSONLT is as the versioned synchronization layer in a two-tier architecture, where a local cache provides rich query capabilities while JSONLT files serve as the portable, version-controlled source of truth. This pattern is directly inspired by BEADS, which uses JSONL files as a sync format between SQLite database instances via git.

### The two-layer architecture

In this architecture, the app maintains two representations of the same data. The JSONLT layer consists of one or more JSONLT files that are the authoritative source of truth, committed to version control and synchronized across machines or collaborators via git. The local cache layer is a query-optimized store (typically SQLite, but could be any database) that provides secondary indexes, joins, and other capabilities that JSONLT intentionally omits.

The app derives the local cache from the JSONLT files and can always rebuild it from them. This makes the cache disposable: if it becomes corrupted or out of sync, simply delete it and regenerate from the JSONLT source.

### Data flow

Writes flow through both layers. When the app modifies data, it writes to both the JSONLT file (for persistence and sync) and the local cache (for immediate query availability). The JSONLT write is the commit point; the cache update can be synchronous or asynchronous depending on consistency requirements.

Reads typically hit the local cache for rich queries, falling back to JSONLT only for key lookups or when the cache is unavailable. The cache provides the query flexibility that JSONLT lacks.

Sync operations involve git pulling remote changes to JSONLT files, then replaying those changes into the local cache. The append-only nature of JSONLT makes this replay direct: new operations append, and the cache updates accordingly. Conflicts surface at the git layer as merge conflicts in the JSONLT files, which developers can resolve with standard text-based merge tools.

### Why this separation works

This architecture uses the strengths of each layer while avoiding their weaknesses.

JSONLT provides properties that are difficult to achieve with traditional databases. It offers meaningful diffs, since changes to structured data produce reviewable, line-based diffs that humans can understand and tools like git can merge automatically when changes don't conflict. The format is portable across languages and platforms with minimal dependencies (it's just JSON text). Human editability means someone can edit the file directly with any text editor when needed. Append-only semantics simplify conflict detection by ensuring that concurrent changes to different keys merge automatically.

The local cache provides properties that JSONLT intentionally lacks. Secondary indexes enable queries like "find all records where status equals active" without scanning every record. Rich queries allow SQL or query-builder syntax for filtering, sorting, joining, and aggregating. The cache can maintain denormalized views or materialized aggregations for performance.

<!-- vale Google.Headings = NO -->
### Comparison with BEADS
<!-- vale Google.Headings = YES -->

BEADS (the distributed issue tracker that inspired JSONLT) implements exactly this pattern. Each node maintains a SQLite database for local queries (finding issues by status, searching by text, aggregating by label). But synchronization happens via JSONL files that collaborators commit to git and push/pull between machines.

When a BEADS node pulls changes from git, it replays the new JSONL operations into its local SQLite database. When it makes local changes, it writes to both SQLite (for immediate query availability) and JSONL (for eventual sync). The JSONL files are the distributed source of truth; the SQLite databases are local caches that can be rebuilt at any time.

JSONLT formalizes and extends the JSONL format that BEADS uses, adding explicit semantics for keys, tombstones, headers, transactions, and compaction.

### When to use this pattern

This two-layer architecture makes sense when you synchronize data across machines or collaborators using git or similar tools, when you need rich local queries but the dataset is small enough that a derived cache is practical, when human readability of the sync format matters, and when the app can tolerate eventual consistency between nodes.

The pattern fits less well when you need real-time synchronization (git-based sync has inherent latency), when datasets are too large for cache regeneration to be practical, or when the overhead of maintaining two data representations outweighs the sync benefits.

### Implementation considerations

Apps implementing this pattern need to consider a few factors.

Cache invalidation requires deciding when to rebuild the cache versus incrementally update it. After a git pull with many changes, full rebuild may be simpler; for local writes, incremental updates are more efficient.

Schema evolution affects both layers. Adding fields to JSONLT records may require cache schema migrations. The cache schema can diverge from JSONLT (adding indexes, denormalized columns) as long as the mapping remains well-defined.

Conflict resolution at the git layer may require app-specific logic. While JSONLT's line-per-record format enables automatic merging of non-conflicting changes, true conflicts (concurrent edits to the same key) need resolution policies.

## Summary

JSONLT is best characterized as a log-structured embedded key-value store optimized for version control interoperability rather than throughput or query flexibility. It occupies a niche between ad-hoc configuration files and full-featured embedded databases, providing just enough structure for reliable keyed access while maintaining the text-based simplicity that enables meaningful diffs and human editing.
