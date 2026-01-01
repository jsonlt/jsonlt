# JSONLT conformance test suite

This directory contains a language-agnostic test suite for verifying conformance to the JSONLT specification. The tests are expressed as JSON files that can be consumed by any implementation through a test harness.

## Design principles

The conformance suite focuses on interoperability: can a file written by one implementation be correctly read by another? Tests cover file format parsing, state computation, serialization determinism, and the core CRUD operations.

Tests are declarative data, not executable code. Each implementation writes a harness that reads test files and maps them to the implementation's API. This keeps the test suite small and unambiguous while allowing implementations flexibility in how they run tests.

The suite intentionally avoids testing implementation-specific features like query languages, indexing, or performance characteristics. Those belong in implementation-specific test suites.

## Conformance profiles

The specification defines two conformance profiles that implementations may support:

The Parser profile covers reading JSONLT files. Parsers follow Postel's Law, accepting input liberally while maintaining correctness. Parser conformance includes SHOULD-level recovery behaviors like stripping CRLF line endings, skipping empty lines, and ignoring truncated final lines.

The Generator profile covers writing JSONLT files. Generators produce strictly conformant output that any parser can read. Generator conformance requires deterministic serialization with sorted keys, no whitespace outside strings, and rejection of invalid records.

Most implementations support both profiles (they can read and write JSONLT files). The test suite is organized to test each profile's requirements separately.

## Consuming the test suite

Implementations can consume the test suite in several ways:

Git submodule is recommended for reference implementations. Pin to a tagged release for stability:

```
git submodule add https://github.com/jsonlt/jsonlt.git vendor/jsonlt-spec
```

Direct download works for CI environments. Tagged releases are available at:

```
https://github.com/jsonlt/jsonlt/releases
```

The test files are self-contained JSON with no external dependencies.

## Test file structure

Each test file contains an array of test cases wrapped in a container object:

```json
{
  "$schema": "https://spec.jsonlt.org/conformance/v1/suite.schema.json",
  "suite": "state",
  "tests": [...]
}
```

The `$schema` field references the JSON Schema for validation. The `suite` field identifies the test category.

## Test suites and profiles

Tests are organized into suite files by category. Each suite targets specific aspects of conformance:

| Suite              | Profile   | Description                                          |
|--------------------|-----------|------------------------------------------------------|
| `format.jsonc`     | Parser    | Physical format parsing, accepting and rejecting     |
| `state.jsonc`      | Parser    | Logical state computation from append-only log       |
| `keys.jsonc`       | Both      | Key validation, extraction, comparison, and ordering |
| `header.jsonc`     | Parser    | Header parsing and key specifier validation          |
| `ops.jsonc`        | Both      | Interface operations (get, put, delete, etc.)        |
| `generator.jsonc`  | Generator | Serialization format and output validation           |
| `recovery.jsonc`   | Parser    | SHOULD-level recovery behaviors                      |
| `transactions.jsonc` | Both    | Transaction semantics (isolation, commit, conflict)  |
| `compaction.jsonc` | Generator | Compaction output                                    |

Implementations declare which profiles they support. Test harnesses skip suites that don't apply to the implementation's declared profiles.

## Common test fields

All test cases include:

| Field         | Type   | Required | Description                             |
|---------------|--------|----------|-----------------------------------------|
| `id`          | string | yes      | Unique identifier (e.g., `"state-001"`) |
| `description` | string | yes      | Human-readable description              |

## Test structures by category

### format tests

Format tests verify that parsers correctly accept valid files and reject invalid files.

```json
{
  "id": "format-invalid-json",
  "description": "Invalid JSON is rejected",
  "key": "id",
  "input": "{\"id\": 1, \"name\": }\n",
  "expect": "reject",
  "error": "PARSE_ERROR"
}
```

| Field             | Type            | Description                                       |
|-------------------|-----------------|---------------------------------------------------|
| `key`             | string or array | Key specifier for opening the table               |
| `input`           | string or array | File content (array elements joined with `\n`)    |
| `inputBase64`     | string          | Alternative to `input` for binary content         |
| `expect`          | string          | `"accept"` or `"reject"`                          |
| `error`           | string          | Expected error category if `expect` is `"reject"` |
| `state`           | object          | Expected logical state if `expect` is `"accept"`  |
| `alternateExpect` | object          | Alternative valid outcome for SHOULD-level requirements |

### state tests

State tests verify that parsing a file produces the correct logical state.

```json
{
  "id": "state-upsert-overwrite",
  "description": "Later upsert overwrites earlier record with same key",
  "key": "id",
  "input": [
    "{\"id\": \"a\", \"v\": 1}",
    "{\"id\": \"a\", \"v\": 2}"
  ],
  "state": {
    "a": {"id": "a", "v": 2}
  }
}
```

| Field   | Type            | Description                                                |
|---------|-----------------|------------------------------------------------------------|
| `key`   | string or array | Key specifier                                              |
| `input` | string or array | File content                                               |
| `state` | object          | Expected logical state (map from serialized key to record) |

### generator tests

Generator tests verify that serialization produces correct, deterministic output.

```json
{
  "id": "generator-key-order-simple",
  "description": "Generator sorts object keys lexicographically",
  "key": "id",
  "state": {
    "1": {"id": 1, "zebra": "z", "apple": "a", "mango": "m"}
  },
  "outputMatches": "\"apple\":\"a\",\"id\":1,\"mango\":\"m\",\"zebra\":\"z\""
}
```

| Field             | Type   | Description                                         |
|-------------------|--------|-----------------------------------------------------|
| `key`             | string or array | Key specifier                               |
| `state`           | object | Logical state to serialize                          |
| `record`          | object | Single record to serialize (alternative to `state`) |
| `outputMatches`   | string | Regex pattern the output must match                 |
| `outputNotMatches`| string | Regex pattern the output must not match             |
| `outputExact`     | string | Exact expected output (byte-for-byte)               |
| `expect`          | string | `"accept"` or `"reject"` for validation tests       |
| `error`           | string | Expected error category if `expect` is `"reject"`   |

Generator tests also verify rejection of invalid records (null keys, $-prefixed fields, etc.).

### ops tests

Operations tests execute a sequence of API operations and verify return values.

```json
{
  "id": "ops-put-get-delete",
  "description": "Basic put, get, delete sequence",
  "key": "id",
  "steps": [
    {"op": "put", "record": {"id": "a", "v": 1}, "returns": null},
    {"op": "get", "key": "a", "returns": {"id": "a", "v": 1}},
    {"op": "has", "key": "a", "returns": true},
    {"op": "delete", "key": "a", "returns": true},
    {"op": "get", "key": "a", "returns": null},
    {"op": "has", "key": "a", "returns": false}
  ]
}
```

Each step specifies an operation and its expected return value.

#### Supported operations

| Operation | Parameters | Returns                      |
|-----------|------------|------------------------------|
| `put`     | `record`   | `null`                       |
| `get`     | `key`      | record or `null`             |
| `has`     | `key`      | boolean                      |
| `delete`  | `key`      | boolean (existed)            |
| `all`     | —          | array of records (key order) |
| `keys`    | —          | array of keys (key order)    |
| `count`   | —          | integer                      |
| `clear`   | —          | `null`                       |
| `compact` | —          | `null`                       |

For operations that should fail, use `error` instead of `returns`:

```json
{"op": "put", "record": {"id": null}, "error": "KEY_ERROR"}
```

### transactions tests

Transaction tests specify setup, transaction operations, and post-commit verification:

```json
{
  "id": "tx-isolation-read",
  "description": "Reads within transaction see transaction writes",
  "key": "id",
  "setup": [
    {"op": "put", "record": {"id": "alice", "v": 1}}
  ],
  "transaction": [
    {"op": "put", "record": {"id": "alice", "v": 2}},
    {"op": "get", "key": "alice", "returns": {"id": "alice", "v": 2}}
  ],
  "commit": true,
  "after": [
    {"op": "get", "key": "alice", "returns": {"id": "alice", "v": 2}}
  ]
}
```

| Field                   | Type    | Description                                        |
|-------------------------|---------|----------------------------------------------------|
| `setup`                 | array   | Operations before transaction starts               |
| `transaction`           | array   | Operations within the transaction                  |
| `commit`                | boolean | Whether commit should succeed (default: `true`)    |
| `error`                 | string  | Expected error if commit fails                     |
| `after`                 | array   | Operations after commit (verify final state)       |
| `externalModifications` | array   | Operations by another writer during transaction    |
| `nestedAttempt`         | boolean | Whether to attempt nested transaction (should fail)|

The `externalModifications` field simulates concurrent modification to test conflict detection.

### header tests

Header tests verify header parsing and key specifier behavior.

```json
{
  "id": "header-key-mismatch",
  "description": "Opening with mismatched key specifier fails",
  "input": [
    "{\"$jsonlt\": {\"version\": 1, \"key\": \"id\"}}",
    "{\"id\": 1, \"name\": \"test\"}"
  ],
  "openWith": {"key": "name"},
  "expect": "reject",
  "error": "KEY_ERROR"
}
```

| Field      | Type            | Description                                          |
|------------|-----------------|------------------------------------------------------|
| `input`    | string or array | File content                                         |
| `openWith` | object          | Options passed when opening (e.g., `{"key": "..."}`) |
| `expect`   | string          | `"accept"` or `"reject"`                             |
| `error`    | string          | Expected error if rejected                           |
| `state`    | object          | Expected state if accepted                           |

### keys tests

Key validation and ordering tests:

```json
{
  "id": "key-null-rejected",
  "description": "Null key values are rejected",
  "key": "id",
  "input": ["{\"id\": null, \"name\": \"test\"}"],
  "expect": "reject",
  "error": "KEY_ERROR"
}
```

```json
{
  "id": "key-order-mixed",
  "description": "Integers sort before strings",
  "key": "id",
  "input": [
    "{\"id\": \"b\", \"v\": 1}",
    "{\"id\": 2, \"v\": 2}",
    "{\"id\": \"a\", \"v\": 3}",
    "{\"id\": 1, \"v\": 4}"
  ],
  "keys": [1, 2, "a", "b"]
}
```

| Field  | Type  | Description                                |
|--------|-------|--------------------------------------------|
| `keys` | array | Expected key order from `keys()` operation |

### recovery tests

Recovery tests verify Parser SHOULD-level behaviors for handling non-conformant input gracefully.

```json
{
  "id": "recovery-truncated-final-line",
  "description": "Parser ignores truncated final line without newline (SHOULD per spec)",
  "key": "id",
  "input": "{\"id\": 1}\n{\"id\":",
  "state": {
    "1": {"id": 1}
  }
}
```

These tests verify behaviors like CRLF stripping, empty line skipping, BOM handling, truncated line recovery, and duplicate key handling. Parsers that implement these SHOULD requirements pass these tests; parsers that don't may skip them.

Some recovery tests use `alternateExpect` to specify two valid outcomes. For example, duplicate key tests accept either:
- Rejection with PARSE_ERROR (parsers that detect duplicates), or
- Acceptance with last-value-wins state (parsers that don't detect duplicates)

A test passes if either the primary expectation or the alternate expectation is satisfied.

## Key serialization in state maps

The `state` field maps serialized keys to expected records. Keys are serialized as follows:

| Key type | Serialization    | Example                 |
|----------|------------------|-------------------------|
| String   | The string value | `"alice"`               |
| Integer  | Decimal string   | `"42"`                  |
| Tuple    | JSON array       | `"[\"org\",\"user1\"]"` |

Example with integer keys:

```json
{
  "state": {
    "1": {"id": 1, "name": "first"},
    "2": {"id": 2, "name": "second"}
  }
}
```

Example with tuple keys:

```json
{
  "state": {
    "[\"acme\",1]": {"org": "acme", "id": 1, "name": "alice"},
    "[\"acme\",2]": {"org": "acme", "id": 2, "name": "bob"}
  }
}
```

## Error categories

Tests that expect errors specify one of these categories:

| Category            | Description                                                  |
|---------------------|--------------------------------------------------------------|
| `PARSE_ERROR`       | Invalid JSON, wrong type, duplicate keys (if detected), invalid `$deleted` |
| `KEY_ERROR`         | Missing key field, invalid key type, key specifier mismatch  |
| `LIMIT_ERROR`       | Key length, tuple elements, or other limits exceeded         |
| `IO_ERROR`          | File read/write failures                                     |
| `LOCK_ERROR`        | Lock acquisition timeout                                     |
| `CONFLICT_ERROR`    | Transaction commit conflict                                  |
| `TRANSACTION_ERROR` | Nested transaction or other transaction protocol error       |

Harnesses should map implementation-specific error types to these categories.

## Comparison rules

When comparing actual results to expected values:

Records are compared for deep equality. Field order does not matter.

Numeric values are compared by value, not representation. `1`, `1.0`, and `1e0` are equal.

Null values must match exactly. A missing field is not equal to a field with value `null`.

Arrays are compared element-by-element in order.

## Writing a test harness

A conforming test harness:

1. Loads test files from this directory
2. Filters suites by the profiles the implementation supports
3. For each test, sets up the environment (creates temp files as needed)
4. Executes the test according to its category
5. Compares results using the comparison rules above
6. Reports pass/fail/skip for each test

Harnesses should accept configuration for which profiles to test (`parser`, `generator`, or both).

Example harness pseudocode:

```python
SUITE_PROFILES = {
    "format": ["parser"],
    "state": ["parser"],
    "generator": ["generator"],
    "recovery": ["parser"],
    "ops": ["parser", "generator"],
    "transactions": ["parser", "generator"],
    "keys": ["parser", "generator"],
    "header": ["parser"],
    "compaction": ["generator"],
}

def run_suite(suite_name, implementation):
    required_profiles = SUITE_PROFILES[suite_name]
    if not any(p in implementation.profiles for p in required_profiles):
        return SKIP_ALL

    for test in load_suite(suite_name):
        yield run_test(test, implementation)

def run_test(test, impl):
    match test.category:
        case "format" | "state" | "recovery":
            return run_parser_test(test, impl)
        case "generator":
            return run_generator_test(test, impl)
        case "ops":
            return run_ops_test(test, impl)
        # ...
```

See the [conformance test harness design document](../design/conformance-test-harness.md) for a detailed protocol specification.

## Test file organization

```
conformance/
├── README.md             # This file
├── index.bs              # Conformance test suite documentation (Bikeshed)
├── schemas/
│   └── v1/
│       ├── suite.schema.json   # JSON Schema for test files
│       └── report.schema.json  # JSON Schema for conformance reports
└── suite/
    ├── format.jsonc      # Physical format parsing tests (Parser)
    ├── state.jsonc       # Logical state computation tests (Parser)
    ├── generator.jsonc   # Serialization output tests (Generator)
    ├── keys.jsonc        # Key validation and ordering tests (Both)
    ├── header.jsonc      # Header parsing tests (Parser)
    ├── ops.jsonc         # API operation tests (Both)
    ├── recovery.jsonc    # Parser SHOULD-level recovery (Parser)
    ├── transactions.jsonc # Transaction semantics (Both)
    └── compaction.jsonc  # Compaction output (Generator)
```

## Versioning

The test suite is versioned alongside the specification. The `$schema` URLs include the version:

```text
https://spec.jsonlt.org/conformance/v1/suite.schema.json
https://spec.jsonlt.org/conformance/v1/report.schema.json
```

When the spec changes in ways that affect conformance, the test suite version increments. Implementations can pin to a specific version for stability.

## What about `find` and `findOne`?

The spec defines `find(predicate)` and `findOne(predicate)` operations, but this conformance suite intentionally excludes them. Here's why:

The predicate parameter is a function, which cannot be expressed in a language-agnostic JSON format without defining a query language. Defining a query language (even a simple one) adds significant complexity to both the test format and every harness implementation.

For conformance purposes, what matters is that `find` iterates records in key order and applies the predicate correctly. This can be verified indirectly through `all()` (which returns records in key order) and implementation-specific tests.

Implementations that want to provide a query language (like MongoDB-style operators) should test that functionality in their own test suites.

## Contributing tests

New tests are welcome. When adding tests:

1. Use a unique `id` following the pattern `{suite}-{description}`
2. Write a clear `description` explaining what the test verifies
3. Reference the relevant section of the spec in a comment if helpful
4. Ensure the test is minimal (tests one thing)
5. Validate against `schemas/v1/suite.schema.json` before submitting

Tests that expose ambiguities or edge cases in the spec are especially valuable—they help clarify the specification for all implementations.
