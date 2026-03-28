# Vnake Transpiler

**Python to V Language Compiler**

Vnake is a transpiler that converts Python code to the V programming language (Vlang). The project is written in V.

## Key Features

- **Python to V Transpilation**: Converts `.py` and `.pyi` files to `.v` files
- **Recursive Processing**: Transpiles entire directories while preserving structure
- **Type Analysis**: Integration with mypy for static type analysis of Python
- **Dependency Analysis**: Automatic detection of dependencies between modules
- **Helper File Generation**: Creates helper libraries for V code
- **Compilation and Execution**: Ability to immediately compile and execute generated V code

## Installation

### Prerequisites

- [V](https://vlang.io/) - V language compiler


### Building

```bash
# Clone the repository
git clone https://github.com/yaskhan/vnake.git
cd vnake

# Build the project
v -o vnake .
```

## Usage

### Transpiling a Single File

```bash
# Simple transpilation
vnake script.py

# Transpilation with automatic compilation and execution
vnake script.py --run
```

### Transpiling a Directory

```bash
# Recursive transpilation of all Python files
vnake src/ -r

# Transpilation with dependency analysis
vnake src/ -r --analyze-deps
```

### Generating Helper Files

```bash
# Only generate the helper file
vnake project/ --helpers-only
```

### Available Options

| Option | Description |
|--------|-------------|
| `-r, --recursive` | Recursive directory processing |
| `--analyze-deps` | Dependency analysis (for directories) |
| `--warn-dynamic` | Warn when using dynamic Any type |
| `--no-helpers` | Do not generate helper file |
| `--helpers-only` | Only generate helper file |
| `--include-all-symbols` | Include all symbols (not just __all__) |
| `--strict-exports` | Warn about symbols missing from __all__ |
| `--experimental` | Enable experimental PEP features |
| `--run` | Compile and run V code after transpilation |
| `--skip-dir <dir>` | Skip specified directory |

## Examples

### Simple Example

```python
# hello.py
def greet(name: str) -> str:
    return f"Hello, {name}!"

if __name__ == "__main__":
    print(greet("World"))
```

```bash
vnake hello.py --run
```

The generated V code (`hello.v`) will be automatically compiled and executed.





## Testing

### Running Tests

```bash
# Run all tests
v -enable-globals test vlangtr/tests

# Run main transpiler tests
v -enable-globals test vlangtr/tests/transpiler_test.v

# Run expression tests
v -enable-globals test vlangtr/tests/remaining_expr_tests_test.v
```

### Test Structure

Tests are located in the `tests/` directory:
- `transpiler_test.v` - main transpilation tests
- `remaining_expr_tests_test.v` - individual expression tests
- `cases/` - test cases (`.py` + `.expected.v` pairs)

The project includes over 500 tests translated from Python. Testing status is displayed in build logs.

## Development

### Adding New Tests

1. Create a Python file in `tests/cases/`
2. Create a corresponding `.expected.v` file with expected results
3. Run tests for verification

## Project History
 
This repository contains the history of the py2v project, migrated from the parent repository [pythontovlang](https://github.com/yaskhan/pythontovlang). All commits related to the transpiler are preserved with updated  messages in Conventional Commits format.

### Project Configuration

The project uses `v.mod` for configuration:
- Name: `vlangtr`
- Version: `0.1.0`
- License: MIT

## Contributing

Pull Requests and issues are welcome. When making changes:

1. Follow the project's code style
2. Add tests for new features
3. Update documentation as needed

## License

MIT License - see [LICENSE](LICENSE) file for details.