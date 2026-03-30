## 2025-05-14 - [V-Lang String Optimization Trade-offs]
**Learning:** In V, iterating over a string with `.runes()` and using `strings.Builder` for simple case conversion can be slower than recursive string splitting for short identifiers due to the overhead of UTF-8 decoding and builder allocations. However, a byte-based fast path for ASCII strings provides a 3-4x speedup while maintaining safety.
**Action:** Always prefer ASCII fast paths for string utilities that process identifiers, falling back to rune-based logic only when `is_ascii()` is false.
