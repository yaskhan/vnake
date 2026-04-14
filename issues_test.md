# Vnake Translation Issues: Deep Analysis Report

This report contains both automated findings from the translation logs and manual deep-dive analysis of the generated V code.

---

## ✅ Resolved Issues

### [FIXED] Invalid Bitwise OR Translation
**Issue:** The translator generated `int | int(a | b)` which is invalid.
**Fix:** Updated `handle_binary` in `operators.v` to sanitize types, removing redundant union-like syntax for primitive types.

### [FIXED] Broken Multiline Strings
**Issue:** Python triple-quoted strings were broken in V.
**Fix:** Updated `quote_string_content` to correctly escape newlines if multiline quotes are not used, or preserved them as valid V literals.

### [FIXED] Invalid Variadic Calls for Function Variables
**Issue:** V anonymous functions don't support variadic parameters.
**Fix:** Updated nested function generation to use `[]Any` and updated call sites to wrap arguments in an array when calling local function variables identified as variadic. Added nested function registration to parent scope.

### [FIXED] Variable Scope in Try/Else
**Issue:** Variables defined in `try` were not accessible in `orelse`.
**Fix:** Implemented pre-declaration of variables defined inside `try` blocks at the parent scope level.

### [FIXED] Missing Dictionary Methods
**Issue:** `dict.items()`, `.values()`, `.keys()` were not supported on maps.
**Fix:** Added method mapping in `handle_object_method_call` to translate these to idiomatic V map calls (e.g., `map.keys()`).

### [FIXED] Unescaped Windows Paths (Raw Strings)
**Issue:** Raw strings lost their `r` prefix.
**Fix:** Updated Lexer to preserve prefixes in token values and updated `visit_constant` to correctly detect and use `r'...'` in V.

### [FIXED] Missing Import for `div72.vexc`
**Issue:** `vexc.end_try()` was called without marking `vexc` as used in some control flow paths.
**Fix:** Ensured `used_builtins['vexc'] = true` is set whenever `vexc.end_try()` is emitted in `return`, `break`, or `continue`.

### [FIXED] Missing Global/Class Variables (Meta-classes)
**Issue:** Class-level variables remapped to `_meta` constants were missing from the generated code.
**Fix:** Updated `ModuleTranslator.visit_module` to correctly extract and emit constants from the shared `VCodeEmitter`.

---

## 1. Syntax Errors & Invalid V Code Generation

### [CRITICAL] Missing `self` in Method Signatures
**Issue:** Some methods are generated without the `mut self Class` receiver even when they are part of a class. (To be investigated).

---

## 2. Logic & Scope Issues

### [MAJOR] Match/Case Pattern Failures
**Issue:** Many complex match patterns (e.g., value patterns, sequence patterns) are not yet implemented and emit warnings.
**Python Source:**
```python
# test_even_more_features.py
match status:
    case 200: ...
```
**Generated V Code Output:**
```
Warning: CASE PATTERN: ast.Value
```

---

## 3. Partially Implemented Features

### [WARNING] Unpacking Inconsistencies
**Issue:** Dictionary unpacking (`**kwargs`) is often marked as unresolved. (Note: Currently excluded from fixes per user request).

---

## 4. Standard Library & Helper Issues

### [MINOR] `sys.version_info` Mapping
**Issue:** `sys.version_info` is accessed but not defined in any helper.
**Python Source:**
```python
import sys
if sys.version_info.major >= 3: ...
```
**Generated V Code:**
```v
if sys_version_info.major >= 3 { ... } // Error: undefined 'sys_version_info'
```
