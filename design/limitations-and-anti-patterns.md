# Limitations and anti-patterns

This document honestly describes what JSONLT is not good at and common mistakes to avoid. Understanding limitations helps you make informed decisions about when to use JSONLT and how to use it well.

## Fundamental limitations

### Dataset needs to fit in memory

JSONLT loads the entire logical state into memory. There's no streaming mode, no memory-mapped access, no way to query records without first loading the whole file. This is inherent to the design: the logical state comes from replaying all operations, requiring the full state in memory.

Practical limits depend on your environment, but as a rough guide: files with tens of thousands of small records are fine; files with millions of records or large records will cause problems. If your dataset exceeds a gigabyte, JSONLT is not the right tool.

The two-layer pattern (JSONLT plus SQLite cache) doesn't help here because you still need to load the JSONLT file to sync it. If memory is a constraint, consider using SQLite directly with git-lfs for the binary file, or a different sync mechanism entirely.

### O(n) scans for non-key queries

Every query except single-key lookup requires scanning all records. The `find` operation that filters by predicate checks every record. JSONLT has no indexes, no query optimization, no way to make non-key queries faster.

For small datasets (hundreds to low thousands of records), this is rarely a problem. For larger datasets or performance-sensitive code paths, it becomes significant. Profile before assuming it's fine.

### No secondary indexes

You cannot create indexes on non-key fields. If you frequently query by a field that isn't the primary key, every such query is a full scan.

The intended solution is the two-layer pattern: maintain a SQLite cache with indexes tailored to your query patterns, using JSONLT only for persistence and sync. If you find yourself wanting secondary indexes in JSONLT itself, you probably want this pattern.

### No range queries on keys

Even for key queries, JSONLT only supports exact lookup. There's no "find all records with keys between A and B" operation. JSONLT stores keys in a hash map, not a sorted structure.

If you need range queries, consider whether a compound key can help (making the range dimension part of the key) or whether a local cache with indexes makes sense.

### Eventual consistency only

JSONLT provides no mechanism for real-time sync. The git-based sync model has inherent latency: changes propagate when someone commits, pushes, pulls, and merges. This can be minutes, hours, or days depending on workflow.

If you need real-time synchronization, JSONLT is not the right tool. Consider CRDTs, operational transformation, or a real-time database with sync capabilities.

### Write-write conflict detection only

Transactions detect only write-write conflicts (two transactions modifying the same key). Read-write conflicts are not detected. If transaction A reads a value, transaction B modifies it, and transaction A commits based on the stale read, no error occurs.

Apps requiring stronger isolation need to add their own coordination. For most JSONLT use cases (single-user or low-contention), this limitation is acceptable.

## Anti-patterns

### Using JSONLT when plain JSON would suffice

If you're storing a single configuration object that changes as a unit, plain JSON is simpler. JSONLT's keyed-record model adds overhead without benefit when you don't need independent record access.

Signs you might be over-engineering: your file has exactly one record, you never query by key, you never delete individual records.

### Using JSONLT when SQLite would be better

If you find yourself wanting joins, secondary indexes, or rich queries, SQLite is probably the right tool. JSONLT can serve as a sync layer in front of SQLite, but forcing rich query patterns into JSONLT directly leads to painful workarounds.

Signs you need SQLite: you're building custom index structures in app code, your find predicates are rich and performance-sensitive, you're joining data across two or more JSONLT files manually.

### Ignoring compaction until files grow unwieldy

Every update and delete appends to the file. Without compaction, files grow indefinitely, containing full history of all operations. This wastes disk space, slows file loading, and makes manual inspection harder.

Use a compaction strategy: compact when the file exceeds a size threshold, compact after a certain number of operations, or compact on a schedule. The right strategy depends on your write patterns and how much history you want to preserve.

### Storing large blobs in records

JSONLT records are JSON, which means binary data requires base64 encoding. A 1 MB image becomes 1.33 MB of base64 text. The entire file loads to access any record, so large blobs bloat memory usage.

If you need to store binary data, consider storing references (file paths or URLs) in JSONLT records rather than the data itself. Keep blobs in separate files managed outside JSONLT.

### Assuming JSONLT is a database

JSONLT is a file format with key-value semantics, not a database. There's no query optimizer, no connection pooling, no replication, no backup facilities beyond filesystem operations. Treating JSONLT as a database replacement leads to disappointment.

JSONLT is a good fit for: configuration data, app state, structured data that needs version control, sync layers backed by real databases. It's not a good fit for: primary data storage for web apps, anything requiring rich queries, datasets that won't fit in memory.

### Over-engineering the local cache layer

The two-layer pattern (JSONLT plus local cache) is powerful but adds overhead. Keep both layers in sync, handle schema changes in both, and watch for bugs in the sync logic that can cause subtle inconsistencies.

Before building the full pattern, consider whether you actually need rich queries or whether JSONLT's basic operations suffice. The best solution is often just JSONLT without a cache, accepting O(n) scans for non-key queries.

### Misunderstanding conflict resolution scope

JSONLT transactions provide conflict detection for local concurrent access. Git provides conflict detection for sync-time merges. These are different mechanisms at different layers.

A JSONLT transaction conflict means two local processes tried to change the same key. A git merge conflict means two branches changed the same line in the file. The former shows up at transaction commit; the latter shows up at git merge. Don't conflate them.

### Not planning for schema evolution

Records can have any JSON structure, but applications typically expect certain fields. When you need to add, remove, or rename fields, what's the migration path?

Consider: how will old code handle records with new fields? How will new code handle records missing new fields? Document your schema expectations and versioning strategy before they become urgent.

## Performance characteristics

Understanding what operations are cheap versus expensive helps avoid performance surprises.

Cheap operations include single-key lookup (O(1) hash lookup), existence check (O(1) hash lookup), single put or delete (O(1) state update, O(record size) file append), and count (O(1) if cached, O(n) if computed).

Expensive operations include find with predicate (O(n) scan), get all records (O(n) iteration plus sort), get all keys (O(n) iteration plus sort), compaction (O(n log n) for sort, O(total data size) for write), and file loading (O(file size) parse, O(n) state construction).

If your access pattern consists of key lookups with occasional scans, JSONLT performs well. If your access pattern involves frequent filtered queries or requires sorted iteration, performance may suffer as datasets grow.
