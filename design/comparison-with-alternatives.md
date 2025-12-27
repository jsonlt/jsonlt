# Comparison with alternatives

This document compares JSONLT with alternative approaches to help you decide whether JSONLT fits your use case. The goal is honest evaluation, not advocacy. JSONLT is a good fit for some scenarios and a poor fit for others.

## JSONLT vs plain JSON files

Plain JSON files are the simplest approach to storing structured data. A single JSON object or array in a file, edited directly or through app code.

### When plain JSON works

Plain JSON works well when your data is a single document rather than a collection of keyed records, when you don't need explicit delete semantics (removing a field is easy), when concurrent access isn't a concern, when you don't need transactional guarantees, and when the entire file changing in diffs is acceptable.

Configuration files, single-document state, and small settings often fit this profile.

### What JSONLT adds

JSONLT provides structure for collections of keyed records where you need to look up, update, or delete individual records by key. It provides explicit delete semantics through tombstones that propagate through sync. It offers transactional writes with conflict detection and deterministic serialization for consistent diffs. The append-only format means changes to different records produce clean, line-based diffs.

### The tradeoff

JSONLT adds complexity. If you're storing a single configuration object that changes infrequently, plain JSON is simpler. If you're storing a collection of records that need independent access and version-controlled history, JSONLT's structure pays off.

## JSONLT vs YAML and TOML

YAML and TOML are popular for configuration files, offering human-friendly syntax and good editor support.

### When YAML or TOML fit better

YAML and TOML excel at hierarchical configuration with nested structures, inline comments explaining settings, and human authoring as the primary interaction mode. They're designed for files that humans write and read directly.

### When JSONLT fits better

JSONLT is better suited to tabular data (collections of similar records), programmatic access patterns where machines write most updates, scenarios requiring explicit delete semantics, and use cases where version control diffs of individual record changes matter.

### The structural difference

YAML and TOML represent trees; JSONLT represents tables. A YAML config might have nested sections for different subsystems. A JSONLT file contains a flat collection of records, each identified by a key.

You could store JSONLT-style records in YAML (as a list of objects), but you'd lose the keyed access semantics, append-only properties, and diff optimization.

<!-- vale Google.Headings = NO -->
## JSONLT vs SQLite
<!-- vale Google.Headings = YES -->

SQLite is the canonical embedded database, offering full SQL query capabilities in a single file.

### When SQLite is the right choice

SQLite excels when you need queries with joins, aggregations, and filtering on many fields; secondary indexes for efficient non-primary-key lookups; datasets larger than available memory; ACID transactions with full isolation; or a mature, battle-tested implementation.

For pure "embedded database" use cases, SQLite is almost always the better choice. It's faster, more capable, and thoroughly proven.

### When JSONLT fits better

JSONLT's advantage is version control integration. SQLite databases are binary blobs that produce meaningless diffs. When you commit data alongside code, review it in pull requests, and merge it across branches, JSONLT's text format becomes valuable.

The two-layer pattern described in the database classification document offers a middle path: use JSONLT as the versioned sync layer and SQLite as a local query cache. This provides SQLite's query capabilities locally while maintaining JSONLT's sync properties.

### The hybrid approach

For many apps, the answer isn't JSONLT or SQLite but both. JSONLT serves as the portable, version-controlled source of truth. SQLite provides rich local queries. The app derives the SQLite database from JSONLT and can rebuild it at any time.

This adds implementation complexity but provides the best of both worlds for apps that need both version control integration and query flexibility.

<!-- vale Google.Headings = NO -->
## JSONLT vs plain JSON Lines
<!-- vale Google.Headings = YES -->

JSON Lines (JSONL) is the base format that JSONLT builds on: one JSON value per line, newline-separated.

### What plain JSON Lines provides

JSON Lines is a minimal format: any JSON value per line, no schema, no semantics beyond "sequence of JSON values." It works well for log files, streaming data, and append-only storage.

### What JSONLT adds to JSON Lines

JSONLT adds keyed record semantics where each line is a record identified by a key extracted from its contents. It introduces operation semantics distinguishing upserts (records) from deletes (tombstones). Headers provide metadata including version, key specifier, and optional schema. The spec defines logical state as the map computed by replaying operations. The spec includes conformance requirements for parsers and generators plus a defined compaction algorithm.

### When plain JSON Lines works

If you're storing a sequence of events or log entries that don't need keyed lookup, plain JSON Lines is simpler. If you're streaming data that you won't query by key, JSON Lines is enough.

### When you need JSONLT

If you need to look up records by key, update existing records, or delete records and have those deletes propagate through sync, JSONLT's semantics matter. JSONLT is JSON Lines with key-value store semantics layered on top.

<!-- vale Google.Headings = NO -->
## JSONLT vs NDJSON
<!-- vale Google.Headings = YES -->

NDJSON (Newline Delimited JSON) is the same as JSON Lines: one JSON value per line. The comparison with JSONLT is identical to the JSON Lines comparison in the preceding section.

<!-- vale Google.Headings = NO -->
## JSONLT vs CSV
<!-- vale Google.Headings = YES -->

CSV remains popular for tabular data, with broad tool support.

### When CSV fits

CSV works for tabular data with a fixed schema, for interchange with spreadsheet apps, when file size matters (CSV is more compact than JSON), and when the data is primarily consumed by tools expecting CSV.

### When JSONLT fits better

JSONLT handles nested field values that CSV cannot represent, schema flexibility where records can have different fields, explicit typing (CSV values are all strings), and programmatic access where JSON tooling is stronger.

### The fundamental difference

CSV is a lowest-common-denominator interchange format optimized for simplicity and tool compatibility. JSONLT is a structured format optimized for version control and programmatic access. They serve different niches.

## Decision framework

Consider JSONLT when your data is a collection of keyed records (not a single document or a stream), when version control integration matters (diffs, merges, pull request review), when you need explicit delete semantics that propagate through sync, when human readability of the storage format is valuable, and when you only need key lookup plus basic scans.

Consider alternatives when your data is a single document or configuration tree (use JSON, YAML, or TOML), when you need queries with joins or secondary indexes (use SQLite, possibly with JSONLT as sync layer), when the data is append-only logs or streams (use plain JSON Lines), when performance or storage efficiency is critical (use binary formats or SQLite), or when the dataset is too large to fit in memory (use SQLite or a database server).
