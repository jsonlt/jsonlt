# Design documents

This directory contains design documents that explain the rationale behind JSONLT's architecture, position it within the broader landscape of data storage systems, and provide guidance for users and implementers.

These documents are non-normative. The specification is the authoritative reference for JSONLT behavior. The design documents explain why the specification takes its current form and help readers understand how to use JSONLT.

## Documents

### [Database classification and comparable systems](database-classification.md)

Characterizes JSONLT from a database design perspective, situating it within established taxonomy (log-structured stores, key-value databases, event sourcing) and identifying comparable systems like Bitcask, CouchDB, and SQLite. Explains the design tradeoffs, target use cases, and the two-layer architectural pattern where JSONLT serves as a versioned sync target backed by a local query cache.

### [Design rationale](design-rationale.md)

Explains the reasoning behind key design decisions: why append-only storage, why keys come from within records, why no secondary indexes, why deterministic serialization without full JCS, why optimistic concurrency, and the specific limits chosen. Understanding these rationales helps implementers make consistent choices and provides context for future specification evolution.

### [Comparison with alternatives](comparison-with-alternatives.md)

Helps you decide whether JSONLT fits your use case by comparing it with alternatives: plain JSON files, YAML/TOML configuration, SQLite, plain JSON Lines, and CSV. Includes a decision framework for choosing the right tool.

### [Limitations and anti-patterns](limitations-and-anti-patterns.md)

Honestly describes what JSONLT is not good at (memory limits, O(n) scans, no secondary indexes, eventual consistency only) and common mistakes to avoid (using JSONLT when simpler tools suffice, ignoring compaction, storing large blobs). Includes performance characteristics to help avoid surprises.

### [Use case patterns](use-case-patterns.md)

Concrete examples showing how to apply JSONLT: configuration management (feature flags, environment config), team state synchronization (shared task lists, project metadata), command-line tool state, app state persistence, and multi-file patterns. Includes guidance on schema evolution.

### [Implementation guidance](implementation-guidance.md)

Guidance for implementers building JSONLT libraries: cross-language type system considerations, testing strategies (conformance tests, property-based testing, edge cases), performance optimization opportunities, API design considerations, and interoperability testing.

### [Future directions](future-directions.md)

Captures ideas the project considered but deferred from v1 (secondary indexes, range queries, streaming reads), extension points in the current design ($-prefix reservation, header fields), and thoughts on potential future evolution. Useful for managing feature requests and understanding the project's scope.
