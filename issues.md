# Identified Transpilation Issues: Richards Benchmark (V 0.5)

This document lists the systemic bugs and regressions identified during the transpilation of `bm_richards.py` to V 0.5. These issues must be addressed in the core `translator` codebase.

## 1. Redundant 'or' Blocks on Narrowed Options
**Issue:** V 0.5 automatically narrows `?&T` to `&T` after an `is none` check or inside `if mut x := ...`.
**Regression:** The translator generates `x or { ... }` even after `x` has been checked for nullity, causing an "unexpected or block" error.
**Fix:** The translator's type-checker/generator must track the "narrowed" state of variables and omit `or` blocks for known non-null references.

## 2. Pointer Mutation Constraints
**Issue:** V 0.5 strictly enforces immutability for reference types (`&T`).
**Regression:** Modifying a field of a packet (e.g., `p.link = next`) when `p` is an immutable reference (`&Packet`) is forbidden.
**Fix:** The translator should detect field mutations on reference types and either:
- Ensure the reference is passed/stored as `mut`.
- Wrap the mutation in `unsafe { &mut T(p) }` if strict V ownership rules are difficult to satisfy automatically.

## 3. Interface Signature Mismatch
**Issue:** Interface methods and their concrete implementations must have identical signatures, including `mut` qualifiers.
**Regression:** The translator occasionally omits `mut` for the receiver or parameters in the concrete struct's method implementation, causing an interface non-compliance error.
**Fix:** Enforce strict signature mirroring during code generation for all interface-implementing methods.

## 4. Initialization of Interface Arrays
**Issue:** `TaskWorkArea` requires an array of optional interfaces: `[]?Task`.
**Regression:** Default initialization or empty literal initialization `[]` may not correctly infer the optional interface type.
**Fix:** Use explicit initialization: `[]?Task{len: size, init: none}`.

## 5. Global/Constant Formatting (V 0.5)
**Issue:** `const ( ... )` groups are deprecated and will be an error after 2025.
**Regression:** The translator uses grouped constants.
**Fix:** Generate individual `const` lines or use the new allowed syntax for groups if available.

## 6. Global Variable Shadowing
**Issue:** Identifying variable names that conflict with V keywords or common library names.
**Example:** `layout` was shadowed, requiring a rename to `g_layout`.
**Fix:** Implement a reserved-word check and automatic renaming for top-level globals and common shadowed identifiers.

## 7. Sum-Type Narrowing for Interfaces
**Issue:** When a parameter is an interface (e.g., `TaskRec`), downcasting it to a concrete struct (e.g., `DeviceTaskRec`) must be handled correctly via `as` or `match`.
**Regression:** Incorrect `as` casting on already-narrowed or complex interface types.
**Fix:** Improve the `match` / `is` / `as` generation logic to be aware of the underlying interface implementation.

## 8. Recursive Function Calls in add_packet
**Issue:** The `add_packet` implementation in Richards is inherently recursive/linked-list based.
**Regression:** Logic errors in the transpiled output caused infinite loops or incorrect head/tail pointers.
**Fix:** Ensure the translator correctly maps Python's reference-based linked list assignments to V's optional pointer assignments.

## 9. Task Input Logic Bug
**Issue:** Tasks were being initialized with an initial packet (`wkp`) but weren't consuming it correctly in `run_task`.
**Fix:** The translator must ensure that `__init__` arguments mapped to `input` fields are correctly integrated into the task's execution cycle.

## 10. Module Import Cleanup
**Issue:** `import math` and other modules are sometimes added even if unused.
**Fix:** Implement a post-process import cleanup or more precise dependency tracking.
