# Development

This guide provides information for developers who want to contribute to the Vnake Transpiler (Python to V).

## Getting Started

### Prerequisites

- **V Compiler** - The V language compiler
- **Git** - Version control
- **C Compiler** - Required by V for compilation (gcc, clang, tcc, or msvc)

### Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/yaskhan/vnake.git
cd vnake

# Build the project
v -o vnake .

# Run tests
v -enable-globals test tests
```

## Project Structure

```
vnake/
├── main.v                  # CLI entry point
├── v.mod                   # V module definition
├── ast/                    # Python-compatible parser and AST
│   ├── ast.v               # AST node definitions
│   ├── lexer.v             # Python lexer
│   ├── parser.v            # Python parser
│   ├── token.v             # Token definitions
│   ├── visitor.v           # AST visitor
│   ├── printer.v           # AST printer
│   ├── serialize.v         # AST serialization
│   └── errors.v            # Error definitions
├── mypy/                   # Full mypy port
│   ├── nodes.v             # Mypy AST nodes
│   ├── types.v             # Type system
│   ├── checker.v           # Type checker
│   ├── bridge.v            # V AST → Mypy AST bridge
│   └── ...                 # Many more mypy modules
├── analyzer/               # Type analysis
│   ├── analyzer.v          # Main analyzer
│   ├── visitor.v           # Type inference visitor
│   ├── inferers.v          # Alias inference
│   ├── mypy_plugin.v       # Mypy plugin
│   └── ...
├── translator/             # Python → V translation
│   ├── translator.v        # Main translator
│   ├── vcode_emitter.v     # V code emitter
│   ├── base/               # Base infrastructure
│   ├── classes/            # Class handling
│   ├── control_flow/       # Control flow
│   ├── expressions/        # Expressions
│   ├── functions/          # Functions
│   ├── variables/          # Variables
│   └── pydantic_support/   # Pydantic support
├── stdlib_map/             # Standard library mappings
│   ├── mapper.v            # Main mapper
│   └── builtins.v          # Built-in functions
├── models/                 # Common types and structures
├── utils/                  # Utilities
├── tests/                  # Test suite
│   ├── cases/              # Test cases (.py + .expected.v)
│   ├── transpiler_test.v
│   └── remaining_expr_tests_test.v
└── docs/                   # Documentation
```

## Development Workflow

### 1. Make Changes

Edit the relevant module based on the feature or bug fix:

- **New language feature**: `translator/` (expressions, statements, functions, etc.)
- **New stdlib mapping**: `stdlib_map/mapper.v`
- **Type handling**: `models/v_types.v`
- **CLI changes**: `main.v`
- **Parser changes**: `ast/` (only if new Python syntax is needed)

### 2. Add Tests

Write tests for your changes in `tests/cases/`:

```python
# tests/cases/my_feature.py (Python input)
def new_feature(x: int) -> int:
    return x * 2
```

```v
// tests/cases/my_feature.expected.v (Expected output)
fn new_feature(x int) int {
    return x * 2
}
```

### 3. Run Tests

```bash
# Run all tests
v -enable-globals test tests

# Run specific test file
v -enable-globals test tests/transpiler_test.v

# Run with verbose output
v -enable-globals test tests -stats
```

### 4. Test Transpilation

```bash
# Build the transpiler
v -o vnake .

# Test your changes on a sample file
./vnake examples/sample.py

# Check the generated V code
cat examples/sample.v

# Try to compile with V
v run examples/sample.v
```

## Coding Standards

### Style Guide

- Follow **V style conventions** (snake_case for functions, PascalCase for types)
- Write **comments** for public APIs
- Keep functions **focused and small**
- Use **V's `pub` keyword** for public APIs

### Naming Conventions

```v
// Types: PascalCase
pub struct TranslatorState {
}

// Functions: snake_case
pub fn map_python_type_to_v(py_type string) string {
}

// Constants: snake_case with module prefix
const builtin_types = ['int', 'str', 'bool']

// Methods: snake_case, receiver is short
pub fn (mut t Translator) translate(source string) string {
}

// Fields: snake_case
pub struct MyStruct {
    name string
    count int
}
```

### Module Organization

```v
module my_module

// Imports
import os
import json

// Constants
const VERSION = '1.0.0'

// Types
pub struct MyType {
}

// Public functions
pub fn new_my_type() MyType {
    return MyType{}
}

// Internal functions
fn helper_function() {
}
```

## Adding New Features

### 1. New Language Feature

**Step 1**: Ensure AST support (if needed)

If the Python construct isn't already in the AST, add it to `ast/ast.v`:

```v
pub struct NewNode {
pub:
    token Token
    // fields
}

pub fn (n &NewNode) get_token() Token {
    return n.token
}

pub fn (n &NewNode) str() string {
    return 'NewNode(...)'
}
```

**Step 2**: Ensure parsing support (if needed)

Add parsing to `ast/parser.v`:

```v
fn (mut p Parser) parse_new_node() ?Expression {
    tok := p.current_token
    // parse logic
    return NewNode{
        token: tok
    }
}
```

**Step 3**: Add translation

Add visitor method in the appropriate translator module:

```v
// translator/expressions/expressions.v
fn (mut e ExprGen) visit_NewNode(node ast.NewNode) string {
    // Translate to V
    return 'v_code_for(${e.visit(node.child)})'
}
```

**Step 4**: Add tests

Create test files in `tests/cases/`:
- `new_feature.py` - Python input
- `new_feature.expected.v` - Expected V output

### 2. New Standard Library Mapping

**Step 1**: Add to mapper

```v
// stdlib_map/mapper.v
fn (mut m StdLibMapper) init_mappings() {
    // ... existing mappings ...
    
    m.mappings['new_module'] = {
        'function': 'v_function'
    }
}
```

**Step 2**: Add V import mapping (if needed)

```v
fn (mut m StdLibMapper) init_imports() {
    // ... existing imports ...
    
    m.v_imports['new_module'] = ['v_module']
}
```

**Step 3**: Add tests

```v
// tests/transpiler_test.v
fn test_new_module() {
    // Transpile Python code that uses new_module
    // Verify V output contains v_function
}
```

### 3. New Type Support

**Step 1**: Update type mapper

```v
// models/v_types.v
fn map_basic_type(name string) string {
    // ... existing mappings ...
    
    match name {
        'NewType': 'v_type'
        else: name
    }
}
```

**Step 2**: Handle in complex type mapping (if generic)

```v
fn map_complex_type(py_type string, ...) string {
    // Handle new generic type
    if base_type == 'NewGeneric' {
        return 'v_generic[${inner_types.join(", ")}]'
    }
}
```

## Debugging

### Enable Debug Output

Print the AST for debugging:

```v
module main

import ast

fn main() {
    source := 'def foo(): pass'
    mut lexer := ast.new_lexer(source, '')
    mut parser := ast.new_parser(lexer)
    mod := parser.parse_module()
    
    // Print AST
    println(mod.str())
}
```

### Type Inference Debug

Check type analysis:

```v
import analyzer

mut ana := analyzer.new_analyzer(map[string]string{})
ana.analyze(module_node)

// Check types
println(ana.type_map)
```

### Verbose Transpilation

```bash
# Enable warnings for dynamic types
./vnake script.py --warn-dynamic
```

### Test Individual Components

```bash
# Build and run a test program
v -g run debug_test.v
```

## Common Issues

### Issue: Parser Error

**Solution**: Check the lexer output and parser error messages:

```v
mut lexer := ast.new_lexer(source, filename)
mut parser := ast.new_parser(lexer)
mod := parser.parse_module()

// Check for errors
for err in parser.errors {
    eprintln('Parse error: ${err.message}')
}
```

### Issue: Type Inference Fails

**Solution**: Ensure the type mapper handles the construct:

```v
// Check if type is in the map
if type_name !in v_type_mapping {
    eprintln('Unknown type: ${type_name}')
}
```

### Issue: V Compilation Error

**Solution**: Check the generated V code for syntax errors:

```bash
# View generated code
cat script.v

# Try to compile manually
v build script.v
```

## Testing Guidelines

### Test Categories

1. **Unit Tests**: Test individual components in `ast/`, `analyzer/`, `translator/`
2. **Integration Tests**: Test full transpilation via `tests/transpiler_test.v`
3. **Regression Tests**: Test bug fixes with specific test cases

### Test Case Files

Test cases are pairs of files in `tests/cases/`:
- `name.py` - Python source
- `name.expected.v` - Expected V output

### Test Structure

```v
// tests/transpiler_test.v
module main

import os

fn test_feature_name() {
    // The test framework automatically finds .py and .expected.v pairs
    // Just ensure the files are in tests/cases/
}
```

## Documentation

### Update Documentation

When adding features, update:

1. **README.md**: Overview and quick start
2. **docs/supported-features.md**: Feature list
3. **docs/stdlib-mapping.md**: Library mappings
4. **docs/architecture.md**: Architecture overview

### Documentation Style

- Use clear, concise language
- Include code examples
- Note any limitations
- Link to related sections

## Performance Tips

### Optimize AST Traversal

```v
// Good: Single pass
for stmt in node.body {
    t.visit_stmt(stmt)
}

// Bad: Multiple walks - avoid this
for stmt in node.body {
    ast.walk_all(node)
}
```

### String Building

```v
// Good: Array accumulation
mut output := []string{}
for item in items {
    output << t.visit(item)
}
return output.join('\n')

// Bad: String concatenation - avoid this
mut output := ''
for item in items {
    output += t.visit(item)
}
return output
```

## Build System

### Building

```bash
# Build with optimizations
v -prod -o vnake .

# Build with debugging symbols
v -g -o vnake .

# Build and run
v run . script.py
```

### Running Tests

```bash
# Run all tests
v -enable-globals test tests

# Run with output
v -enable-globals test tests -stats

# Run specific test file
v -enable-globals test tests/transpiler_test.v
```

## Release Process

### Before Release

1. Update version in `v.mod`
2. Update `docs/changelog.md`
3. Run all tests
4. Build with `v -prod`

### Create Release

```bash
# Tag the release
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

## Contributing

### Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run tests
6. Submit PR

### Commit Messages

Follow conventional commits:

```
feat: Add support for new Python feature
fix: Fix type inference for generics
docs: Update installation instructions
test: Add tests for stdlib mapping
refactor: Improve translator structure
```

## Getting Help

- **Issues**: Open an issue on GitHub
- **Discussions**: Use GitHub Discussions for questions
- **Code Review**: Request review from maintainers

## Future Directions

See `TODO.md` and other planning documents for:

- Python 3.12+ syntax support
- Performance optimizations
- Better error messages with source locations
- More stdlib mappings
- Enhanced type inference
- Better async/await support