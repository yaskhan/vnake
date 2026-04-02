## 2025-05-14 - [V-Lang String Optimization Trade-offs]
**Learning:** In V, iterating over a string with `.runes()` and using `strings.Builder` for simple case conversion can be slower than recursive string splitting for short identifiers due to the overhead of UTF-8 decoding and builder allocations. However, a byte-based fast path for ASCII strings provides a 3-4x speedup while maintaining safety.
**Action:** Always prefer ASCII fast paths for string utilities that process identifiers, falling back to rune-based logic only when `is_ascii()` is false.

## 2025-05-14 - [V-Lang Mutable Parameters]
**Learning:** In V, when a function parameter is marked as 'mut', the argument passed must also be explicitly marked with 'mut' at the call site. Furthermore, the variable itself must have been declared as 'mut' using 'mut var := ...'. Passing an immutable variable to a 'mut' parameter results in a compilation error.
**Action:** When calling functions with 'mut' parameters, always ensure the source variable is declared as 'mut' and prefix it with 'mut' in the call.

## 2025-05-15 - [V-Lang String and Map Performance]
**Learning:** Repeated string concatenation in V is $O(N^2)$ due to its immutable nature and frequent re-allocations. Furthermore, local map literals are re-allocated and populated on every function call, adding significant heap overhead.
**Action:** Use index-based string slicing instead of character-by-character concatenation in loops. Replace local mapping maps with `match` expressions to avoid redundant allocations.
