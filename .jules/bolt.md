## 2025-05-14 - [V-Lang String Optimization Trade-offs]
**Learning:** In V, iterating over a string with `.runes()` and using `strings.Builder` for simple case conversion can be slower than recursive string splitting for short identifiers due to the overhead of UTF-8 decoding and builder allocations. However, a byte-based fast path for ASCII strings provides a 3-4x speedup while maintaining safety.
**Action:** Always prefer ASCII fast paths for string utilities that process identifiers, falling back to rune-based logic only when `is_ascii()` is false.

## 2025-05-14 - [V-Lang Mutable Parameters]
**Learning:** In V, when a function parameter is marked as 'mut', the argument passed must also be explicitly marked with 'mut' at the call site. Furthermore, the variable itself must have been declared as 'mut' using 'mut var := ...'. Passing an immutable variable to a 'mut' parameter results in a compilation error.
**Action:** When calling functions with 'mut' parameters, always ensure the source variable is declared as 'mut' and prefix it with 'mut' in the call.

## 2025-05-15 - [V-Lang String and Map Performance]
**Learning:** Repeated string concatenation in V is $O(N^2)$ due to its immutable nature and frequent re-allocations. Furthermore, local map literals are re-allocated and populated on every function call, adding significant heap overhead.
**Action:** Use index-based string slicing instead of character-by-character concatenation in loops. Replace local mapping maps with `match` expressions to avoid redundant allocations.

## 2026-04-08 - [Single-pass Type Homogeneity Tracking]
**Learning:** Allocating temporary arrays or maps to determine the common type of collection elements (e.g., in list or dict literals) during recursive AST traversal creates significant GC pressure and overhead.
**Action:** Use a single-pass loop with state variables to track homogeneity and nullability, returning early or defaulting to a base type if an inconsistency is detected.

## 2024-05-16 - [V-Lang match vs in for string sets]
**Learning:** In V 0.5.1, using a `match` expression for string constant sets is significantly faster (~23% in -prod) than the `in` operator with an array literal, as `match` is optimized to a jump table or efficient branching while `in` may involve array iteration.
**Action:** Use `match` for fixed-set identifier lookups in hot paths.

## 2024-05-18 - [Backward Scope Stack Iteration and State Optimization]
**Learning:** In compiler/translator architectures, innermost scopes are accessed significantly more frequently than outer ones. Forward iteration through a scope stack results in $O(N)$ lookup complexity for the common case. Switching to backward iteration (innermost to outermost) yielded a measured ~3.7x speedup for typical local variable accesses. Additionally, cloning static configuration data (like indentation arrays) into every state instance creates unnecessary heap pressure.
**Action:** Always iterate scope stacks from local to global (backward) and prefer direct access to global constants over cloning for read-only state data.

## 2024-05-19 - [Optimized method lookups and allocation reduction]
**Learning:** In V, linear search in an array literal (`if x in ['a', 'b']`) is less efficient than a `match` expression, especially with a length-based fast path. Furthermore, creating temporary arrays for lookups in hot paths (like a visitor) adds significant heap pressure.
**Action:** Centralize fixed-set lookups into optimized functions with `match` and length guards. Avoid temporary array allocations for lookups by using direct map access with string interpolation.

## 2024-05-20 - [V-Lang trim_left Performance]
**Learning:** In V 0.5.1, `s.trim_left(cutset)` performs heap allocations even when no characters are trimmed; manual checks for the first character before calling `trim_left` are significantly faster (~16x speedup) in hot paths where prefixes are often absent.
**Action:** Always use a fast-path check for the first character before calling `trim_left` in performance-critical code.

## 2024-05-21 - [Optimized Type Mapping with Byte Dispatch and Map Deduplication]
**Learning:** In V 0.5.1, sequential `starts_with` checks and linear search deduplication in recursive functions (like type mapping) create significant overhead. Byte-level dispatch on the first character of a string provides a fast path for branching. Additionally, map-based deduplication is crucial even for small sets (like Union types) to avoid O(N^2) complexity in nested scenarios.
**Action:** Use byte-level `match` dispatch for string-based branching and prefer map-based deduplication for type processing.

## 2024-05-22 - [Optimized Type Mapping with Byte Dispatch and Conditional Trimming]
**Learning:** In V 0.5.1, string operations like `trim_left`, `trim_right`, and `trim_space` always perform heap allocations even if no characters are removed. Adding a simple check for leading/trailing characters (e.g., `if s[0].is_space() || s[s.len-1].is_space()`) before calling them can avoid these allocations. Additionally, using byte-level dispatch (match on `s[0]`) for prefix stripping significantly reduces the overhead of multiple `starts_with` calls in hot paths.
**Action:** Use conditional trimming and byte-level dispatch for hot-path string transformations.

## 2024-05-24 - [Optimized Type Name Generation with strings.Builder]
**Learning:** In V 0.5.1, high-level string pipelines like `.split(' | ').map(it.trim_space())` and `.capitalize()` on every part create significant heap pressure and redundant allocations. Replacing these with `strings.Builder` and single-pass character processing (manual quote/prefix stripping and capitalization) yielded a measured ~1.7x to 1.9x speedup for `get_sum_type_name` and `get_literal_enum_name`.
**Action:** Use `strings.Builder` and manual character-level transformations instead of functional pipelines for hot-path string formatting.

## 2025-02-13 - [V-Lang trim_space Allocation Avoidance]
**Learning:** In V 0.5.1, the `trim_space()` method performs a heap allocation even if the string has no leading or trailing whitespace. In high-traffic code (like type parsing and AST traversal), this creates significant memory pressure. A "fast-path" check like `if s.len > 0 && (s[0].is_space() || s[s.len-1].is_space()) { s = s.trim_space() }` avoids this allocation, providing a measured ~7x speedup for strings that are already trimmed.
**Action:** Implement a `fast_trim_space` helper or use the conditional check pattern in all performance-critical string processing paths.

## 2025-02-14 - [V-Lang String Prefix Optimization]
**Learning:** In V 0.5.1, calling `.to_lower()` on short identifiers or string prefixes (like 'f', 'r', 'rb') creates unnecessary heap allocations. Using byte-level bitwise operations (e.g., `prefix[i] | 32` for ASCII) and pre-calculating boolean flags once per string scanning operation eliminates these allocations in the lexer's hot path.
**Action:** Use byte-level case-insensitive comparisons and pre-calculate flags outside of character loops for hot string processing logic.

## 2025-05-25 - [Single-pass string escaping with strings.Builder]
**Learning:** Sequential `.replace()` calls in V 0.5.1 are inefficient for multiple escapes as each call performs a full string scan and a heap allocation. A fast-path check for characters needing escaping followed by a single-pass `strings.Builder` transformation reduces complexity from $O(N \cdot K)$ to $O(N)$ and eliminates intermediate allocations. Measured ~1.84x speedup for typical string literals.
**Action:** Replace multiple sequential `.replace()` calls with a fast-path scan and a single-pass `strings.Builder` loop in high-traffic string processing code.
## 2025-01-24 - Optimized Lexer Operator and String Scanning
**Learning:** In V 0.5.1, `u8.ascii_str()` allocates a new string on the heap. Replacing it with string literals in the lexer's hot path significantly reduces memory churn. Additionally, manual `l.pos++` and `l.column++` increments for known non-newline characters avoid the branching overhead of `l.advance_char()`.
**Action:** Always prefer string literals or `match` expressions returning literals over `ascii_str()` for known characters in hot paths. Use manual position tracking for non-newline ASCII sequences to bypass `advance_char()` branches.
