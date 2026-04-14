# Usage

This guide covers the command-line interface and usage patterns for the Vnake Transpiler (Python to V).

## Command-Line Interface

### Basic Usage

Transpile a single Python file:

```bash
vnake path/to/script.py
```

This generates `script.v` next to the source file.

### Transpile and Run

Transpile, compile with V, and run the resulting program:

```bash
vnake script.py --run
```

This is useful for quick testing and development iterations.

**Requirements:**
- V compiler installed and available in your PATH
- C compiler installed (required by V for linking)

**How it works:**
1. Transpiles `script.py` to `script.v`
2. Compiles the V code using `v run`
3. Executes the compiled program

### Recursive Directory Processing

Transpile all Python files in a directory recursively:

```bash
vnake path/to/project/ --recursive
```

### Skip Directories

Skip specific directories during recursive processing:

```bash
vnake path/to/project/ --recursive --skip-dir tests --skip-dir docs
```

### Dependency Analysis

Analyze imports and dependencies in a project:

```bash
vnake --analyze-deps path/to/project/
```

This shows the import graph and helps identify module dependencies.

### Generate Helpers Only

Generate only the helper functions file without transpiling source files:

```bash
vnake path/to/project/ --helpers-only
```

This creates `vnake_helpers.v` in the target directory with common helper functions needed by transpiled code.

## CLI Options

| Option | Short | Description |
|--------|-------|-------------|
| `--recursive` | `-r` | Process directories recursively |
| `--analyze-deps` | | Analyze import dependencies instead of transpiling |
| `--warn-dynamic` | | Emit warnings for variables that fell back to `Any` type |
| `--no-helpers` | | Don't generate helper functions file |
| `--helpers-only` | | Only generate helpers file, skip transpiled sources |
| `--include-all-symbols` | | Include all symbols as public (not just `__all__`) |
| `--strict-exports` | | Warn about symbols missing from `__all__` |
| `--experimental` | | Enable experimental PEP features |
| `--run` | | Transpile, compile with V, and run the resulting program |
| `--skip-dir <dir>` | | Skip specified directory during recursive processing |
| `--help` | `-h` | Show help message |

## Usage Examples

### Simple Script

```bash
# Transpile a single file
vnake hello.py

# Output: hello.v is created in the same directory
```

### Project with Multiple Files

```bash
# Transpile entire project recursively
vnake src/ --recursive

# Skip test directories
vnake src/ --recursive --skip-dir tests
```

### Type Analysis

```bash
# Enable dynamic type warnings
vnake script.py --warn-dynamic

# Output includes warnings like:
# WARNING: Variable 'x' at line 10 fell back to Any type
```

### Dependency Analysis

```bash
# Analyze project dependencies
vnake --analyze-deps myproject/

# Output shows import relationships
```

### Transpile and Run

```bash
# Transpile, compile, and run in one command
vnake script.py --run
```

### Generate Helpers

```bash
# Generate helper file for a project
vnake project/ --helpers-only

# Output: vnake_helpers.v is created
```

## Output Structure

By default, the transpiler generates:

1. **`<script>.v`** - The transpiled V source code
2. **`vnake_helpers.v`** (optional) - Common helper functions and types

### Example Output

```
my_project/
├── src/
│   ├── main.py      →  main.v
│   └── utils.py     →  utils.v
└── vnake_helpers.v   (common helpers)
```

## Python Code Patterns

### Supported Features

The transpiler supports a wide range of Python features:

#### Functions

```python
def greet(name: str) -> str:
    return f"Hello, {name}!"

result = greet("World")
print(result)
```

#### Classes

```python
class Person:
    def __init__(self, name: str, age: int):
        self.name = name
        self.age = age
    
    def get_info(self) -> str:
        return f"{self.name}, age {self.age}"

p = Person("Alice", 30)
print(p.get_info())
```

#### Type Annotations

```python
from typing import List, Dict, Optional

def process_data(
    items: List[int],
    config: Dict[str, str],
    mode: Optional[str] = None
) -> List[str]:
    result: List[str] = []
    for item in items:
        result.append(str(item))
    return result
```

#### Control Flow

```python
def categorize(value: int) -> str:
    if value > 100:
        return "large"
    elif value > 50:
        return "medium"
    else:
        return "small"
```

#### Loops

```python
# For loop
numbers = [1, 2, 3, 4, 5]
for n in numbers:
    print(n * 2)

# While loop
count = 0
while count < 10:
    print(count)
    count += 1
```

#### List Comprehensions

```python
squares = [x**2 for x in range(10) if x % 2 == 0]
```

#### Try/Except

```python
try:
    result = 10 / 0
except ZeroDivisionError as e:
    print(f"Error: {e}")
finally:
    print("Done")
```

#### Match/Case (Python 3.10+)

```python
def handle_command(cmd: str) -> str:
    match cmd:
        case "start":
            return "Starting..."
        case "stop":
            return "Stopping..."
        case _:
            return "Unknown command"
```

## Best Practices

1. **Add Type Hints**: Use type hints in your Python code for better V output
2. **Test Incrementally**: Transpile and test small modules first
3. **Check Warnings**: Use `--warn-dynamic` to identify type issues
4. **Review Generated Code**: Always review the generated V code before compilation
5. **Use `__all__`**: Define `__all__` in your modules to control exported symbols
6. **Avoid Dynamic Features**: Minimize use of `eval()`, `exec()`, and other dynamic features

## Limitations

- Some Python dynamic features may not translate perfectly
- Complex metaprogramming may require manual adjustment
- Some standard library modules have partial or approximate mappings
- Decorators with complex behavior may need manual implementation
- Async/await support may be limited depending on the use case

See [Supported Features](supported-features.md) for detailed compatibility information.

## Common Issues

### "Any" Type Warnings

When the transpiler cannot infer a type, it falls back to `Any`. To fix this:

```python
# Bad - will generate Any
x = some_function()

# Good - explicit type annotation
x: int = some_function()
```

### Unsupported Modules

If you import a module that isn't fully supported:

```python
# Try to use alternative approaches
# Instead of: import some_unsupported_module
# Use: manual implementation or helper function
```

### Complex Generics

For complex generic types:

```python
from typing import Generic, TypeVar

T = TypeVar('T')

class Container(Generic[T]):
    def __init__(self, value: T):
        self.value = value
```

## Integration with Build Systems

### Makefile

```makefile
transpile:
	vnake src/ --recursive

run: transpile
	v run main.v

test:
	v -enable-globals test tests/
```

### Shell Script

```bash
#!/bin/bash
# build.sh
vnake src/ --recursive --warn-dynamic
if [ $? -eq 0 ]; then
    echo "Transpilation successful"
    v run main.v
else
    echo "Transpilation failed"
    exit 1
fi