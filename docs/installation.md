# Installation

This guide covers the requirements and installation process for the Vnake Transpiler (Python to V).

## Prerequisites

- **V Compiler** - The V language compiler is required to build the transpiler
- **Git** - For cloning the repository
- **C Compiler** (optional) - Required by V for compilation (gcc, clang, tcc, or msvc)

## Installation Methods

### Build from Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yaskhan/vnake.git
   cd vnake
   ```

2. **Build the project:**
   ```bash
   v -o vnake .
   ```

3. **(Optional) Add to PATH:**
   ```bash
   # Linux/macOS - add to your shell config (~/.bashrc, ~/.zshrc)
   export PATH="$PATH:/path/to/vnake"
   
   # Windows - add the directory containing vnake.exe to your PATH
   # System Properties → Environment Variables → Path → Edit → New
   ```

### Quick Start with `v run`

For development or testing without building:

```bash
git clone https://github.com/yaskhan/vnake.git
cd vnake
v run . script.py
```

This will transpile `script.py` to `script.v` without creating a standalone binary.

## Verification

After building, verify the transpiler is working:

```bash
# Check if the command is available
./vnake --help

# Transpile a simple test
echo 'print("Hello, World!")' > test.py
./vnake test.py
cat test.v
```

## V Compiler Setup

If you don't have V installed:

1. **Install V:**
   ```bash
   # Using git (recommended)
   git clone https://github.com/vlang/v.git
   cd v
   make
   
   # Or using package managers:
   # macOS
   brew install vlang
   
   # Linux (some distributions)
   sudo apt install vlang
   ```

2. **Add V to your PATH:**
   ```bash
   # Linux/macOS - add to shell config
   export VROOT=/path/to/v
   export PATH=$VROOT:$PATH
   
   # Windows (PowerShell) - temporary for session
   $env:PATH = "C:\path\to\v;$env:PATH"
   ```

3. **Verify V installation:**
   ```bash
   v --version
   ```

## Usage After Installation

### Transpile a Single File

```bash
vnake script.py
```

### Transpile and Run

```bash
vnake script.py --run
```

This will transpile the Python file to V, then compile and execute the V code.

### Transpile a Directory

```bash
# Recursive transpilation
vnake src/ -r

# With dependency analysis
vnake src/ -r --analyze-deps
```

### Generate Helper File Only

```bash
vnake project/ --helpers-only
```

## Available Options

| Option | Description |
|--------|-------------|
| `-r, --recursive` | Recursively process directories |
| `--analyze-deps` | Analyze module dependencies |
| `--warn-dynamic` | Warn when falling back to dynamic `Any` type |
| `--no-helpers` | Do not generate helper V file |
| `--helpers-only` | Only generate the helper V file |
| `--include-all-symbols` | Include all symbols (not just `__all__`) |
| `--strict-exports` | Warn about symbols missing from `__all__` |
| `--experimental` | Enable experimental PEP features |
| `--run` | Compile and run V code after transpilation |
| `--skip-dir <dir>` | Skip specified directory |

## Project Structure

After cloning, the project structure looks like this:

```
vnake/
├── main.v              # Entry point
├── v.mod               # V module definition
├── ast/                # Python-compatible parser and AST
├── mypy/               # Full mypy port for type analysis
├── analyzer/           # Type inference and analysis
├── translator/         # Python to V translation
├── stdlib_map/         # Python stdlib to V mappings
├── models/             # Common types and structures
├── utils/              # Utilities
├── tests/              # Test suite
│   ├── cases/          # Test cases (.py + .expected.v)
│   ├── transpiler_test.v
│   └── remaining_expr_tests_test.v
└── docs/               # Documentation
```

## Running Tests

To verify everything works correctly:

```bash
# Run all tests
v -enable-globals test tests

# Run main transpiler tests
v -enable-globals test tests/transpiler_test.v

# Run expression tests
v -enable-globals test tests/remaining_expr_tests_test.v
```

## Examples

### Simple Function

**Input (Python):**
```python
def greet(name: str) -> str:
    return f"Hello, {name}!"

if __name__ == "__main__":
    print(greet("World"))
```

**Transpile and run:**
```bash
vnake example.py --run
```

### With Type Annotations

**Input (Python):**
```python
from typing import List

def sum_numbers(numbers: List[int]) -> int:
    return sum(numbers)

result: int = sum_numbers([1, 2, 3, 4, 5])
print(result)  # Output: 15
```

**Transpile:**
```bash
vnake types.py
```

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Linux | ✅ Supported | Primary development platform |
| macOS | ✅ Supported | Tested |
| Windows | ✅ Supported | Tested |

## Troubleshooting

### V compiler not found

```bash
# Verify V is installed and in PATH
v --version

# If not found, reinstall V
git clone https://github.com/vlang/v.git
cd v
make
```

### Transpilation errors

- Ensure your Python code uses valid syntax
- The transpiler supports Python 3.10+ syntax features
- Check for unsupported features in the [Supported Features](supported-features.md) document

### V compilation errors

- Ensure you have the latest V compiler version
- Check if the generated V code follows V syntax
- Some Python constructs may require manual adjustments

### Permission denied (Linux/macOS)

```bash
# Make the binary executable
chmod +x vnake

# Or run with ./ prefix
./vnake script.py
```

### Missing C compiler (V requirement)

V requires a C compiler for linking. Install one:

```bash
# Ubuntu/Debian
sudo apt install gcc

# Fedora
sudo dnf install gcc

# macOS (Xcode Command Line Tools)
xcode-select --install

# Windows
# Install MSVC (Visual Studio Build Tools) or MinGW-w64
```

## Updating

To update to the latest version:

```bash
cd vnake
git pull
v -o vnake .