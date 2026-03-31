# Vnake Transpiler

**A robust tool to transpile Python source code into V code.**

This project bridges the gap between Python's ease of development and V's performance and safety. Built entirely in V, it provides fast and reliable Python to V translation.

## Quick Start

```bash
# Clone and build
git clone https://github.com/yaskhan/vnake.git
cd vnake
v -o vnake .

# Transpile a file
./vnake script.py

# Transpile and run
./vnake script.py --run

# Transpile a project recursively
./vnake my_project/ --recursive
```

## Key Features

- **Full mypy Port**: Complete static type analysis with a full port of mypy — no Python dependencies
- **Custom Python Parser**: Built-in Python-compatible parser with full AST support
- **Type Inference**: Intelligently infers types (int, float, bool, str, lists, dicts, tuples, sets, generics)
- **Control Flow**: `if`, `for`, `while`, `match`/`case`, `try`/`except`
- **Functions**: Definitions, arguments, return values, lambdas, decorators, overloads
- **OOP**: Classes, inheritance, operator overloading, dataclasses
- **Syntactic Sugar**: List comprehensions, f-strings, walrus operator (`:=`), slice notation
- **Standard Library**: `math`, `json`, `random`, `os`, `sys`, `datetime`, `re`, and many more
- **No External Dependencies**: Fully self-contained V binary

## Documentation Navigation

| Section | Description |
|---------|-------------|
| [Installation](installation.md) | Requirements and installation from source |
| [Usage](usage.md) | CLI options and usage examples |
| [Supported Features](supported-features.md) | Complete list of supported Python features |
| [Standard Library Mapping](stdlib-mapping.md) | Python to V standard library correspondence |
| [LLM Comments](llm-comments-en.md) ([Russian](llm-comments.md)) | Special `//##LLM@@` comments for AI-assisted code review |
| [Architecture](architecture.md) ([Russian](architecture_ru.md)) | Internal structure of the transpiler |
| [Development](development.md) | Developer guidelines |
| [Pydantic](pydantic.md) | Pydantic Support |
| [Dynamic Types & None](typing_and_none.md) | How the transpiler maps dynamic types, `None`, and boolean operators |
| [Changelog](changelog.md) | Release history and notable changes per version |

## Example

**Python (input.py):**
```python
from math import sqrt

def fibonacci(n: int) -> list[int]:
    """Generate Fibonacci sequence."""
    if n <= 0:
        return []
    elif n == 1:
        return [0]
    
    seq = [0, 1]
    for i in range(2, n):
        seq.append(seq[-1] + seq[-2])
    return seq

if __name__ == "__main__":
    print(fibonacci(10))
```

**V (output.v):**
```v
import math

pub fn fibonacci(n int) []int {
    // Generate Fibonacci sequence.
    if n <= 0 {
        return []int{}
    } else if n == 1 {
        return [0]
    }
    mut seq := [0, 1]
    for i in 2..n {
        seq << seq.last() + seq[seq.len - 2]
    }
    return seq
}

fn main() {
    // if __name__ == '__main__':
    println(fibonacci(10))
}
```

## Why Vnake?

| Feature | Description |
|---------|-------------|
| **Speed** | Native V binary — no Python interpreter needed |
| **Type Safety** | Full mypy integration for accurate type inference |
| **Self-Contained** | No external dependencies — just a single binary |
| **Active Development** | Regular updates and new feature support |

## License

[MIT License](../LICENSE)

## Links

- [GitHub Repository](https://github.com/yaskhan/vnake)
- [V Language](https://vlang.io)
- [V Documentation](https://modules.vlang.io)