# Implementation guidance

This document provides guidance for implementers building JSONLT libraries, covering cross-language considerations, testing strategies, and optimization opportunities. This expands on the specification's Implementation Mapping appendix with practical advice.

## Cross-language considerations

The JSONLT designers targeted implementation across many languages. These considerations help ensure consistency and idiomatic APIs.

### Type system mapping

Languages vary widely in their type systems. The specification uses abstract types; implementations map these to native constructs.

For keys, languages with union types (TypeScript, Rust, Python with type hints) can represent Key as `String | Integer | Tuple[KeyElement, ...]`. Languages without union types may use a wrapper class or tagged enum. Consider whether keys need to be comparable and hashable for use as map keys.

For records, most languages can use their native JSON object type (dict, map, object, HashMap). Decide whether to expose records as opaque types with accessor methods or as plain data structures.

For optionals, languages with explicit optional types (Rust's `Option`, Swift's `Optional`, Kotlin's nullable types) can use them. Languages where `null` is a valid value for any reference type can document which nulls mean "absent" versus "explicitly null."

For errors, the specification defines error categories (ParseError, KeyError, etc.). Languages with exception systems can map these to exception classes. Languages preferring result types (Rust, Go) can use dedicated error types. Ensure error messages include context (line numbers, key values) for debugging.

### Method naming conventions

The specification uses camelCase for method names. Implementations follow their language's conventions: snake_case for Python and Ruby, camelCase for JavaScript and Java, snake_case for Rust. The abstract interface is a guide; idiomatic naming matters more than exact name matching.

### Key equality and hashing

Keys need to be usable as map keys, requiring equality comparison and (often) hashing. Considerations include integer keys where `1`, `1.0`, and `1e0` all equal and hash to the same value; tuple keys that require element-wise comparison; and string keys where Unicode comparison is by code point, without normalization unless documented.

Test key equality thoroughly, especially for edge cases like negative zero (which equals positive zero) and large integers at the boundary of the valid range.

### Tuple representation

Languages handle tuples differently. Python has native tuples. JavaScript typically uses arrays. Rust has tuple types but they're not dynamically sized. Go lacks native tuples entirely.

Common approaches include using the language's native tuple if available, using arrays or lists with documented semantics (comparison is element-wise), or creating a dedicated `TupleKey` class.

Whatever representation you choose, ensure it's hashable and comparable if you use keys in maps or sets.

## Testing strategies

Thorough testing is essential for format correctness and interoperability.

### Conformance test suite

The JSONLT project provides a conformance test suite with test vectors that all implementations pass. Use this as the baseline for validating your implementation.

The suite covers parsing valid files, rejecting invalid files with expected errors, logical state computation, serialization with deterministic output, and edge cases from the specification.

### Property-based testing

Property-based testing (QuickCheck, Hypothesis, fast-check) is valuable for format implementations. Properties to test include round-trip consistency (serializing any valid logical state and parsing it produces the same state), deterministic serialization (serializing the same state always produces identical bytes), operation replay (the logical state after N operations equals the state after N-1 operations plus the Nth operation), and compaction equivalence (logical state before compaction equals logical state after).

Generate random records, keys, and operation sequences. The specification defines constraints (valid key types, integer ranges, etc.) that guide your generators.

### Edge cases to cover

The specification calls out many edge cases. Ensure your tests cover empty string keys, integer keys at boundary values (±9007199254740991), tuple keys with exactly one element (which produce scalar keys), records with only key fields and no other data, files with header only and no operations, files with no header, tombstones for non-existent keys, repeated operations on the same key, Unicode in keys and string values, and deeply nested record structures.

### Error condition testing

Test that the implementation raises errors for invalid JSON syntax, non-object JSON values, invalid key types (null, boolean, object, array), keys out of integer range, records with `$`-prefixed fields, invalid `$deleted` values, duplicate keys in JSON objects, version mismatches, and key specifier mismatches between file and caller.

### Concurrent access testing

If your implementation supports concurrent access, test for concurrent readers, writer with concurrent readers, and two or more writers (which coordinate via locking).

Consider using stress tests with many threads and randomized timing to expose race conditions.

### Fuzz testing

Fuzz testing is essential for parser implementations. Format parsers are a common source of security vulnerabilities and crashes when handling malformed input. Fuzz JSONLT parsers thoroughly.

Targets for fuzzing include the main file parser (arbitrary bytes as input), individual line parsing (arbitrary strings as JSON candidates), key extraction (records with unusual structures), and header parsing (malformed `$jsonlt` objects).

Modern fuzzing tools include AFL++ and libFuzzer for C/C++/Rust, Atheris for Python, jazzer for Java, and go-fuzz or the built-in fuzzing in Go 1.18+. These tools use coverage-guided mutation to explore code paths.

A basic fuzz target for JSONLT parsing might look like:

```python
# Python with Atheris
import atheris
import sys

def fuzz_parse(data: bytes):
    try:
        # Attempt to parse arbitrary bytes as a JSONLT file
        table = Table.from_bytes(data, key="id")
        # If parsing succeeds, try operations
        table.count()
        list(table.all())
    except (ParseError, KeyError, UnicodeDecodeError):
        # Expected errors for malformed input
        pass
    except Exception as e:
        # Unexpected errors are bugs
        raise

atheris.Setup(sys.argv, fuzz_parse)
atheris.Fuzz()
```

```rust
// Rust with cargo-fuzz
#![no_main]
use libfuzzer_sys::fuzz_target;
use jsonlt::Table;

fuzz_target!(|data: &[u8]| {
    // Parsing should never panic, only return errors
    let _ = Table::from_bytes(data, "id");
});
```

Key properties to verify during fuzzing: parsing never panics or crashes regardless of input, memory usage stays bounded (watch for billion-laughs style attacks with deeply nested JSON), errors go through the defined error types not as uncaught exceptions, and no undefined behavior (for languages where this applies).

Seed your fuzzer with valid JSONLT files, edge cases from the conformance suite, and known-problematic patterns (deeply nested objects, long strings, unusual Unicode). Let it run for extended periods. Fuzzers often find issues only after hours or days of execution.

Consider also fuzzing at the JSON layer if you're using a custom JSON parser, and fuzzing concurrent operations if your implementation supports them (use thread-sanitizer builds).

## Benchmarking

Benchmarks help you understand performance characteristics, confirm optimizations, and compare implementations. Good benchmarks are reproducible, representative of real workloads, and measure the right things.

### What to benchmark

Core operations to benchmark include file loading (time to parse and compute logical state), single key lookup (get by key, expected O(1)), iteration (all records, all keys), filtered queries (find with predicate selectivities from 1% to 100%), single record write (put, including file I/O), batch writes (many puts in sequence or transaction), and compaction (time to compact files of different sizes).

Vary the parameters: number of records (100, 1K, 10K, 100K), record size (small records with few fields, large records with many fields or large string values), key types (string keys, integer keys, tuple keys), and file state (freshly compacted vs files with history and tombstones).

### Benchmark design

Avoid common benchmarking mistakes. Warm up before measuring, since JIT compilation, disk caches, and memory allocation can skew early iterations. Run many iterations and report statistical summaries (median, percentiles) not just means. Isolate what you're measuring: if benchmarking lookup, don't include file loading time in the measurement. Use realistic data: random strings may behave differently than real-world keys and values.

For microbenchmarks, use your language's benchmarking framework: pytest-benchmark or pyperf for Python, criterion for Rust, JMH for Java, BenchmarkDotNet for C#. These handle warm-up, iteration, and statistics correctly.

Example benchmark structure:

```python
# Python with pytest-benchmark
import pytest
from jsonlt import Table

@pytest.fixture
def large_table(tmp_path):
    """Create a table with 10K records."""
    path = tmp_path / "bench.jsonlt"
    table = Table(str(path), key="id")
    for i in range(10_000):
        table.put({"id": f"key-{i}", "data": "x" * 100})
    table.compact()
    return str(path)

def test_lookup_performance(benchmark, large_table):
    table = Table(large_table, key="id")
    # Benchmark single key lookup
    result = benchmark(lambda: table.get("key-5000"))
    assert result is not None

def test_iteration_performance(benchmark, large_table):
    table = Table(large_table, key="id")
    # Benchmark full iteration
    result = benchmark(lambda: list(table.all()))
    assert len(result) == 10_000
```

### Continuous benchmarking

Integrate benchmarks into CI to catch performance regressions. Tools like Codspeed, bencher, or GitHub Actions with benchmark result comparison can track performance over time. Set thresholds for acceptable regression (for example, fail if any benchmark regresses more than 10%).

Store benchmark results historically to identify trends. A gradual 1% regression per commit adds up.

### Comparative benchmarks

When comparing JSONLT implementations or comparing JSONLT to alternatives, ensure fair comparison. Use identical data and operations. Account for language differences (comparing Python to Rust isn't apples-to-apples). Benchmark what matters for your use case: raw throughput may matter less than latency or memory usage.

Document benchmark methods so others can reproduce results. Include hardware specs, OS, language versions, and exact commands to run.

### Memory profiling

Beyond time benchmarks, profile memory usage. JSONLT loads full state into memory, so understanding memory overhead matters. Measure peak memory during file loading, steady-state memory with loaded table, and memory growth during write operations (before compaction).

Tools include memory_profiler for Python, heaptrack or valgrind for C/C++/Rust, and async-profiler for Java.

## Performance optimization

The specification prioritizes correctness and simplicity, but implementations can optimize within spec constraints.

### Lazy parsing

The spec requires loading the full logical state, but you can defer full JSON parsing. Parse each line enough to extract the key and detect tombstones, storing the raw JSON string. Full record parsing happens on access. This trades memory for CPU: you store both raw strings and parsed records for accessed items.

### Incremental state updates

After initial load, you know the logical state. Later file reads (for auto-reload) can seek to the last known position and parse only new lines, updating the state incrementally rather than rebuilding from scratch.

This optimization adds complexity (it needs to handle truncation, external compaction, etc.) and may not be worth it for small files.

### Efficient serialization

Deterministic serialization requires sorted keys. For records with many fields, sorting for each serialization is wasteful. Consider caching the sorted key order for records that haven't changed, using a JSON library that supports sorted serialization natively, or pre-sorting during record construction.

### Memory layout

For large numbers of records, memory layout matters. Consider whether to store records as parsed JSON structures (flexible, potentially memory-heavy) or as domain objects with known fields (less flexible, more compact). The choice depends on your use case and language.

### File input/output patterns

For writes, buffer append operations. Small writes (one byte at a time) are inefficient; large buffers delay persistence. Balance based on your use case.

For reads, memory-mapping may help for large files, but typical JSONLT files are small enough that sequential reads suffice.

## API design considerations

Beyond spec compliance, API design affects usability.

### Builder patterns

For languages where construction with many options is common, consider builder patterns for table opening.

```python
table = (Table.open("data.jsonlt")
    .with_key("id")
    .auto_reload(True)
    .lock_timeout(5000)
    .build())
```

### Context managers and RAII

Release resources (file handles, locks) when done. Use context managers (Python), RAII (C++, Rust), or try-with-resources (Java) patterns.

```python
with Table.open("data.jsonlt", key="id") as table:
    table.put({"id": "x", "data": "y"})
# file handle released here
```

### Async support

For languages with async I/O (JavaScript, Python asyncio, Rust async), consider whether to provide async APIs. File I/O is often not truly async at the OS level, so async APIs may just wrap sync operations. Assess whether async provides real benefit for your users.

### Type safety for records

Some users want type-safe record access rather than untyped dictionaries. Consider supporting generic type parameters or schema-driven code generation.

```typescript
interface User {
  id: string;
  name: string;
  email: string;
}

const table = Table.open<User>("users.jsonlt", { key: "id" });
const user: User = table.get("alice"); // typed
```

This adds API complexity but catches errors at compile time.

### Immutability

Consider whether records returned from `get` are mutable. If mutable, changes don't automatically persist (callers call `put` to save). If immutable, the API is clearer but some languages make immutability awkward.

Document the behavior either way.

## Interoperability testing

JSONLT's value comes partly from cross-language interoperability. Test that other implementations can read files your implementation produces, that your implementation can read files from other implementations, that logical state is identical across implementations for the same file, and that deterministic serialization produces compatible (if not byte-identical) output.

The conformance test suite provides a baseline, but testing against actual other implementations catches integration issues.

## Documentation expectations

Beyond API documentation, implementations document which conformance profiles they support (parser, generator, or both), which optional features they include, specific limits (key length, record size, nesting depth), thread safety guarantees, platform-specific behaviors (locking mechanism, path handling), and any extensions or deviations from the spec.

This documentation helps users understand what to expect and aids debugging when behavior differs from another implementation.
