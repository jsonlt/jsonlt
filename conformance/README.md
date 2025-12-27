# JSONLT conformance test suite

This directory contains a language-agnostic test suite for verifying conformance to the JSONLT specification. The tests are expressed as JSON files that can be consumed by any implementation through a test harness.

## Design principles

The conformance suite focuses on interoperability: can a file written by one implementation be correctly read by another? Tests cover file format parsing, state computation, serialization determinism, and the core CRUD operations.

Tests are declarative data, not executable code. Each implementation writes a harness that reads test files and maps them to the implementation's API. This keeps the test suite small and unambiguous while allowing implementations flexibility in how they run tests.

The suite intentionally avoids testing implementation-specific features like query languages, indexing, or performance characteristics. Those belong in implementation-specific test suites.

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

## Test categories

### format

Tests that implementations correctly parse valid files and reject invalid files according to the physical format rules.

Subcategories:

- `format/common` — tests both strict and lenient readers must pass
- `format/strict` — tests only strict readers must pass (lenient readers may accept these inputs)
- `format/lenient` — tests only lenient readers must pass (strict readers must reject these inputs)

### state

Tests that a sequence of operations produces the correct logical state. These verify the core append-only log semantics.

### serial

Tests that serialization produces deterministic output. Subcategories:

- `serial/lenient` — sorted keys, no whitespace (may vary in number formatting)
- `serial/strict` — RFC 8785 JCS compliance (byte-identical output)

### ops

Tests for interface operations: `get`, `put`, `delete`, `has`, `all`, `keys`, `count`, `clear`, `compact`.

### tx

Tests for transaction semantics: isolation, commit, abort, and conflict detection.

### header

Tests for header parsing and key specifier validation.

### keys

Tests for key validation, extraction, comparison, and ordering.

### recovery

Tests for lenient reader behavior with truncated or malformed files (crash recovery).

## Common test fields

All test cases include:

| Field         | Type   | Required | Description                                                  |
|---------------|--------|----------|--------------------------------------------------------------|
| `id`          | string | yes      | Unique identifier (e.g., `"state-001"`)                      |
| `description` | string | yes      | Human-readable description                                   |
| `profile`     | string | no       | `"strict"`, `"lenient"`, or `"common"` (default: `"common"`) |

## Test structures by category

### format tests

```json
{
  "id": "format-crlf-rejected",
  "description": "Strict readers reject files with CRLF line endings",
  "profile": "strict",
  "key": "id",
  "input": "{\"id\": 1}\r\n",
  "expect": "reject",
  "error": "PARSE_ERROR"
}
```

| Field         | Type            | Description                                       |
|---------------|-----------------|---------------------------------------------------|
| `key`         | string or array | Key specifier for opening the table               |
| `input`       | string or array | File content (array elements joined with `\n`)    |
| `inputBase64` | string          | Alternative to `input` for binary content         |
| `expect`      | string          | `"accept"` or `"reject"`                          |
| `error`       | string          | Expected error category if `expect` is `"reject"` |
| `state`       | object          | Expected logical state if `expect` is `"accept"`  |

### state tests

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

### serial tests

```json
{
  "id": "serial-key-order",
  "description": "Object keys are sorted lexicographically",
  "record": {"z": 1, "a": 2, "m": 3},
  "lenient": "{\"a\":2,\"m\":3,\"z\":1}",
  "strict": "{\"a\":2,\"m\":3,\"z\":1}"
}
```

| Field     | Type   | Description                                     |
|-----------|--------|-------------------------------------------------|
| `record`  | object | Record to serialize                             |
| `lenient` | string | Expected output from lenient writer (optional)  |
| `strict`  | string | Expected output from strict writer (byte-exact) |

When `lenient` is omitted, harnesses should verify the output is valid JSON that deserializes to the same value, but not require exact byte match.

### ops tests

Operations tests use a sequence of steps:

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

### tx tests

Transaction tests specify setup, transaction operations, and post-commit verification:

```json
{
  "id": "tx-isolation",
  "description": "Reads within transaction see transaction writes",
  "key": "id",
  "setup": [
    {"op": "put", "record": {"id": "a", "v": 1}}
  ],
  "transaction": [
    {"op": "put", "record": {"id": "a", "v": 2}},
    {"op": "get", "key": "a", "returns": {"id": "a", "v": 2}}
  ],
  "commit": true,
  "after": [
    {"op": "get", "key": "a", "returns": {"id": "a", "v": 2}}
  ]
}
```

| Field         | Type    | Description                                     |
|---------------|---------|-------------------------------------------------|
| `setup`       | array   | Operations before transaction starts            |
| `transaction` | array   | Operations within the transaction               |
| `commit`      | boolean | Whether commit should succeed (default: `true`) |
| `error`       | string  | Expected error if `commit` is `false`           |
| `after`       | array   | Operations after commit (verify final state)    |

### header tests

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

```json
{
  "id": "recovery-truncated-line",
  "description": "Lenient reader ignores truncated final line without newline",
  "profile": "lenient",
  "key": "id",
  "input": "{\"id\": 1, \"v\": 1}\n{\"id\": 2, \"v\":",
  "state": {
    "1": {"id": 1, "v": 1}
  }
}
```

These tests verify lenient readers handle crash scenarios gracefully.

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
| `PARSE_ERROR`       | Invalid JSON, wrong type, duplicate keys, invalid `$deleted` |
| `KEY_ERROR`         | Missing key field, invalid key type, key specifier mismatch  |
| `IO_ERROR`          | File read/write failures                                     |
| `LOCK_ERROR`        | Lock acquisition timeout                                     |
| `TRANSACTION_ERROR` | Nested transaction, commit conflict                          |

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
2. Filters tests by the profiles the implementation supports
3. For each test, sets up the environment (creates temp files as needed)
4. Executes the test according to its category
5. Compares results using the comparison rules above
6. Reports pass/fail/skip for each test

Harnesses should accept configuration for which profiles to test (`strict`, `lenient`, or both).

Example harness pseudocode:

```python
def run_test(test, implementation):
    if test.profile not in implementation.supported_profiles:
        return SKIP

    match test.category:
        case "format":
            return run_format_test(test, implementation)
        case "state":
            return run_state_test(test, implementation)
        case "ops":
            return run_ops_test(test, implementation)
        # ...

def run_state_test(test, impl):
    with temp_file(test.input) as path:
        table = impl.open(path, key=test.key)
        actual_state = {serialize_key(k): v for k, v in table.all()}
        return PASS if actual_state == test.state else FAIL
```

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
    ├── format.json       # Physical format parsing tests
    ├── state.json        # Logical state computation tests
    ├── keys.json         # Key validation and ordering tests
    ├── header.json       # Header parsing tests
    ├── ops.json          # API operation tests
    ├── recovery.json     # Recovery from non-conforming input (optional)
    ├── transactions.json # Transaction operations (optional)
    └── compaction.json   # Compaction operations (optional)
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

1. Use a unique `id` following the pattern `{category}-{description}`
2. Write a clear `description` explaining what the test verifies
3. Reference the relevant section of the spec in a comment if helpful
4. Ensure the test is minimal (tests one thing)
5. Validate against `schemas/v1/suite.schema.json` before submitting

Tests that expose ambiguities or edge cases in the spec are especially valuable—they help clarify the specification for all implementations.
