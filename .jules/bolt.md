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
