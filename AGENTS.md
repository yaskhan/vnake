# Notes for Agents

## V Compiler Limitation (V 0.5.1)

The compiler may fail with `cgen error: reached maximum levels of nesting for ... &c.Gen{}.type_default_impl` when processing the deep recursive structure of the `ast.Statement` and `ast.Expression` interfaces and their implementations.

This is a known issue in V 0.5.1. Major `match` blocks on these types in `translator/` and `analyzer/` have been refactored to `if node is T` chains to mitigate similar nesting issues, but the type definition complexity itself may still trigger the error during full builds.

If the V-based transpiler fails to compile, the Python-based version in `./logs/py2v_transpiler` can be used as a fallback if necessary.
