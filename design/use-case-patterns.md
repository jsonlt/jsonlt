# Use case patterns

This document describes concrete patterns for applying JSONLT well, with examples and guidance for common scenarios.

## Configuration management

JSONLT works well for configuration data that needs version control, review, and deployment across environments.

### Feature flags

A feature flag system where you toggle flags independently, with changes tracked and reviewed.

```json
{"$jsonlt": {"version": 1, "key": "flag"}}
{"flag": "dark-mode", "enabled": true, "rollout": 100, "description": "Enable dark mode UI"}
{"flag": "new-checkout", "enabled": false, "rollout": 0, "description": "New checkout flow"}
{"flag": "beta-api", "enabled": true, "rollout": 25, "description": "Beta API endpoints"}
```

Each flag is an independent record. Enabling or disabling a flag produces a single-line diff. Two or more engineers can change different flags in separate branches with automatic merges.

Consider adding metadata fields for audit: who enabled the flag, when, why. The full git history provides an audit trail.

### Environment configuration

Configuration that varies by environment, stored as one record per setting.

```json
{"$jsonlt": {"version": 1, "key": "setting"}}
{"setting": "database.host", "dev": "localhost", "staging": "staging-db.internal", "prod": "prod-db.internal"}
{"setting": "cache.ttl", "dev": 60, "staging": 300, "prod": 3600}
{"setting": "log.level", "dev": "debug", "staging": "info", "prod": "warn"}
```

You can also use a compound key to separate environments entirely:

```json
{"$jsonlt": {"version": 1, "key": ["env", "setting"]}}
{"env": "dev", "setting": "database.host", "value": "localhost"}
{"env": "prod", "setting": "database.host", "value": "prod-db.internal"}
```

The first approach keeps all environments in one record for easy comparison. The second approach allows environment-specific overrides without touching shared settings.

## Team state synchronization

JSONLT enables teams to share structured state through version control.

### Shared task lists

A team task list where members can add, complete, and delete tasks.

```json
{"$jsonlt": {"version": 1, "key": "id"}}
{"id": "task-001", "title": "Review PR #42", "assignee": "alice", "status": "open", "created": "2025-01-15"}
{"id": "task-002", "title": "Update dependencies", "assignee": "bob", "status": "done", "created": "2025-01-14"}
{"id": "task-003", "title": "Write documentation", "assignee": "alice", "status": "open", "created": "2025-01-16"}
```

Team members commit task updates to a shared repository. Git handles merging non-conflicting changes (different tasks modified by different people). Conflicting changes (same task modified by two people) surface as merge conflicts for human resolution.

### Project metadata

Metadata about projects, repositories, or services in an organization.

```json
{"$jsonlt": {"version": 1, "key": "repo"}}
{"repo": "api-gateway", "owner": "platform-team", "language": "go", "oncall": "alice", "tier": "critical"}
{"repo": "web-frontend", "owner": "web-team", "language": "typescript", "oncall": "bob", "tier": "high"}
{"repo": "internal-tools", "owner": "devx-team", "language": "python", "oncall": "carol", "tier": "low"}
```

This pattern works well for data that's edited by humans, needs review, and benefits from version history. For derived or frequently changing data, consider whether a database fits better.

## Command-line tool state

Command-line tools can persist state in JSONLT files within the user's home directory or repository.

### Bookmarks or aliases

User-defined shortcuts or bookmarks.

```json
{"$jsonlt": {"version": 1, "key": "name"}}
{"name": "home", "path": "/home/user/projects"}
{"name": "work", "path": "/home/user/work/monorepo"}
{"name": "notes", "path": "/home/user/documents/notes"}
```

### Tool configuration with overrides

Base configuration with per-project overrides, stored in the user's home directory.

```json
{"$jsonlt": {"version": 1, "key": ["project", "setting"]}}
{"project": "_default", "setting": "editor", "value": "vim"}
{"project": "_default", "setting": "pager", "value": "less"}
{"project": "work-repo", "setting": "editor", "value": "code"}
```

The tool checks for project-specific settings first, falling back to `_default`.

### Session state

Persisting session state across tool invocations.

```json
{"$jsonlt": {"version": 1, "key": "key"}}
{"key": "last_directory", "value": "/home/user/projects/myapp"}
{"key": "history_cursor", "value": 42}
{"key": "last_search", "value": "TODO"}
```

For session state, the append-only property may cause file growth over time. Consider compaction on tool exit or startup.

## Application state persistence

Small applications can use JSONLT as their primary persistence layer.

### Entity storage

A basic app storing entities by ID.

```json
{"$jsonlt": {"version": 1, "key": "id"}}
{"id": "user-1", "type": "user", "name": "Alice", "email": "alice@example.com"}
{"id": "user-2", "type": "user", "name": "Bob", "email": "bob@example.com"}
{"id": "doc-1", "type": "document", "title": "Meeting Notes", "owner": "user-1"}
```

This pattern works for small applications with hundreds to low thousands of entities. For larger applications, consider the two-layer pattern with a SQLite cache for queries.

### Event log with computed state

Some apps work better storing an event log rather than current state.

```json
{"$jsonlt": {"version": 1, "key": "id"}}
{"id": "evt-001", "type": "account_created", "account": "acct-1", "timestamp": "2025-01-15T10:00:00Z"}
{"id": "evt-002", "type": "deposit", "account": "acct-1", "amount": 1000, "timestamp": "2025-01-15T10:05:00Z"}
{"id": "evt-003", "type": "withdrawal", "account": "acct-1", "amount": 200, "timestamp": "2025-01-15T11:00:00Z"}
```

The app computes current state (account balances) from the event log. This provides full audit history but requires careful design of the event schema and state computation logic.

## Schema evolution patterns

As applications evolve, record schemas change. These patterns help manage evolution.

### Additive changes

Adding new optional fields is safe. Old records lacking the field continue to work; new records include it.

```json
{"id": "item-1", "name": "Widget"}
{"id": "item-2", "name": "Gadget", "category": "electronics"}
```

Apps handle missing fields gracefully, providing defaults when needed.

### Field renaming

When renaming a field, consider a transition period where the code accepts both names.

```json
{"id": "old-record", "userName": "alice"}
{"id": "new-record", "username": "bob"}
```

Application code reads both `userName` and `username`, preferring the new name. After migrating all records (possibly via compaction with transformation), remove support for the old name.

### Type changes

Changing a field's type is risky. Consider introducing a new field instead.

```json
{"id": "v1-record", "count": "5"}
{"id": "v2-record", "count": 5, "countLegacy": "5"}
```

Or use a version field to distinguish schema versions:

```json
{"id": "old-record", "schemaVersion": 1, "count": "5"}
{"id": "new-record", "schemaVersion": 2, "count": 5}
```

### Migration via compaction

Compaction provides an opportunity to transform records. A custom compaction process can read old records, transform them to the new schema, and write the updated records.

This is not automated by JSONLT itself. Apps build their own migration logic. Document migration procedures and test them thoroughly.

## Multi-file patterns

Some apps work better with two or more JSONLT files rather than one large file.

### Partitioning by type

Separate files for different record types.

```
data/
  users.jsonlt
  documents.jsonlt
  settings.jsonlt
```

Each file has its own key specifier and schema. This keeps files focused and allows independent compaction schedules.

### Partitioning by tenant or namespace

In multi-tenant applications, separate files per tenant.

```
data/
  tenant-a/records.jsonlt
  tenant-b/records.jsonlt
  tenant-c/records.jsonlt
```

This provides isolation and allows per-tenant sync patterns.

### Sharding large datasets

If a single file grows too large, consider sharding by key prefix or hash.

```
data/
  records-0.jsonlt  # keys hashing to 0
  records-1.jsonlt  # keys hashing to 1
  ...
```

This adds overhead (lookups determine the right shard) but allows scaling beyond single-file limits. For most JSONLT use cases, if you need sharding, you might want a different solution entirely.

## Data analysis workflows

JSONLT files are JSON Lines files with optional headers and tombstones. For data analysis, you can strip the header and feed the records directly to tools with strong JSONL support like Polars or DuckDB.

### Stripping the header for analysis tools

The header (if present) is always the first line and contains `$jsonlt`. A filter removes it:

```bash
# Strip header and pipe to analysis tool
tail -n +2 data.jsonlt | duckdb -c "SELECT * FROM read_json_auto('/dev/stdin')"

# Or check for header presence first
head -1 data.jsonlt | grep -q '"\$jsonlt"' && tail -n +2 data.jsonlt || cat data.jsonlt
```

For compacted files (no tombstones), the result is clean JSONL ready for analysis. For files with tombstones, you may want to filter those as well:

```bash
# Strip header and tombstones
tail -n +2 data.jsonlt | grep -v '"\$deleted"'
```

### Using polars

Polars can read JSON Lines directly with good performance:

```python
import polars as pl

# Read JSONLT file, skipping header
df = pl.read_ndjson("data.jsonlt", ignore_errors=True)

# Filter out header and tombstones if present
df = df.filter(
    ~pl.col("$jsonlt").is_not_null() &
    ~pl.col("$deleted").is_not_null()
)

# Now analyze
df.group_by("category").agg(pl.count())
```

For large files, Polars' lazy evaluation and streaming capabilities work well:

```python
# Lazy evaluation for large files
lf = pl.scan_ndjson("data.jsonlt")
result = lf.filter(pl.col("status") == "active").collect()
```

### Using duckdb

DuckDB has native JSON Lines support and can query files directly:

```sql
-- Query JSONLT file directly
SELECT * FROM read_json_auto('data.jsonlt')
WHERE "$jsonlt" IS NULL  -- exclude header
  AND "$deleted" IS NULL; -- exclude tombstones

-- Aggregate queries
SELECT category, COUNT(*) as count
FROM read_json_auto('data.jsonlt')
WHERE "$jsonlt" IS NULL AND "$deleted" IS NULL
GROUP BY category;
```

DuckDB can also query two or more files with glob patterns:

```sql
-- Query all JSONLT files in a directory
SELECT * FROM read_json_auto('data/*.jsonlt')
WHERE "$jsonlt" IS NULL AND "$deleted" IS NULL;
```

### Creating analysis-ready exports

For frequent analysis, consider maintaining a compacted, header-stripped export:

```bash
# Create analysis-ready JSONL from JSONLT
jsonlt compact data.jsonlt  # remove tombstones and history
tail -n +2 data.jsonlt > data.analysis.jsonl  # strip header
```

Or automate this as part of your data pipeline. The compacted file contains only current records with no tombstones, and stripping the header produces standard JSONL that any tool can consume.

### When to use analysis tools vs JSONLT directly

Use JSONLT's native operations for single-key lookups and updates, transactional writes with conflict detection, and maintaining the append-only log for version control.

Use analysis tools like Polars or DuckDB for queries that summarize many records, filtering on non-key fields, joins between files, exploratory data analysis, and generating reports or visualizations.

The two approaches complement each other. JSONLT handles writes and key-based access with version control integration, while analysis tools handle rich read queries that would be O(n) scans in JSONLT anyway.
