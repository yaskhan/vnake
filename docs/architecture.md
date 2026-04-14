# Vnake Transpiler Architecture

This document describes the internal architecture of Vnake — a Python to V language transpiler.

## Overview

The project is entirely written in V and follows a **pipeline architecture** with distinct processing phases:

```
Python Source → Lexer → Parser → AST → Analyzer (mypy) → Typed AST → Translator → V AST → Generator → V Source
```

Key difference from the original Python project: all components are rewritten in V, including a full mypy port and a custom Python-compatible parser.

## Components

### 1. AST (`ast/`) — Python-Compatible Parser

A full-featured Python parser compatible with CPython AST. Consists of multiple modules:

**Module Structure:**
```
ast/
├── ast.v          # AST nodes (expressions, statements, patterns)
├── lexer.v        # Python lexer (tokenization)
├── parser.v       # Parser (Pratt parser for expressions)
├── token.v        # Token definitions
├── visitor.v      # AST visitor
├── printer.v      # Human-readable AST output
├── serialize.v    # AST serialization
├── errors.v       # Parsing error handling
└── parser_test.v  # Parser tests
```

**Supported Constructs:**
- All Python expressions (binary, unary, comparisons, calls, attributes, subscripts)
- All statements (def, class, if/elif/else, for, while, try/except, match/case, with)
- Decorators, async/await, yield/yield from
- Lambda, comprehensions, generator expressions
- F-strings with formatting
- Named expressions (walrus operator)
- Type parameters (PEP 695)
- Pattern matching (match/case)

**Key Structures:**
```v
// Base AST interface
pub interface ASTNode {
	get_token() Token
	str() string
}

// Top-level module
pub struct Module {
	token    Token
	body     []Statement
	filename string
}

// Expressions
pub struct Name { id string; ctx ExprContext }
pub struct Constant { value string }
pub struct BinaryOp { left Expression; op Token; right Expression }
pub struct Call { func Expression; args []Expression; keywords []KeywordArg }
pub struct Attribute { value Expression; attr string; ctx ExprContext }
pub struct Subscript { value Expression; slice Expression; ctx ExprContext }
// ... and many more

// Statements
pub struct FunctionDef {
	name string; args Arguments; body []Statement
	decorator_list []Expression; returns ?Expression
	is_async bool; type_params []TypeParam
}
pub struct ClassDef {
	name string; bases []Expression; keywords []KeywordArg
	body []Statement; decorator_list []Expression; type_params []TypeParam
}
pub struct If { test Expression; body []Statement; orelse []Statement }
pub struct For { target Expression; iter Expression; body []Statement; orelse []Statement; is_async bool }
pub struct Try { body []Statement; handlers []ExceptHandler; orelse []Statement; finalbody []Statement }
// ... and many more
```

**Parsing Approach:**
- Pratt parser for expressions with correct precedence handling
- Recursive descent for statements
- Indentation/Dedentation support via lexer
- Comparison chain handling (a == b == c)

### 2. Mypy (`mypy/`) — Full mypy Port

A complete port of the mypy module in V for static type analysis.

**Module Structure:**
```
mypy/
├── nodes.v           # Mypy semantic AST nodes
├── types.v           # Mypy type system
├── checker.v         # Type checking
├── checkexpr.v       # Expression checking
├── checkmember.v     # Class member checking
├── checkstrformat.v  # String format checking
├── semanal.v         # Semantic analysis
├── semanal_main.v    # Main semantic analyzer
├── semanal_enum.v    # Enum handling
├── semanal_namedtuple.v   # Named tuple
├── seminvar_typeddict.v   # TypedDict
├── infer.v           # Type inference
├── solve.v           # Type constraint solving
├── subtypes.v        # Subtypes
├── join.v            # Type joining
├── meet.v            # Type meeting
├── constraints.v     # Type constraints
├── expandtype.v      # Type expansion
├── typeanal.v        # Type analysis
├── typeops.v         # Type operations
├── visitor.v         # Visitor
├── traverser.v       # Tree traversal
├── bridge.v          # Bridge: V AST → Mypy AST
├── build.v           # Module building and loading
├── options.v         # Mypy options
├── errors.v          # Error handling
├── messages.v        # Error messages
├── plugin.v          # Plugins
├── binder.v          # Type binding
├── literals.v        # Literal types
├── patterns.v        # Patterns
├── ...
```

**Bridge (bridge.v):**
Converts V AST (from `ast/`) to Mypy AST for subsequent type analysis:

```v
// bridge converts V AST → Mypy AST
pub fn bridge(v_mod ast.Module) !MypyFile {
    mut defs := []Statement{}
    for stmt in v_mod.body {
        if s := convert_statement(stmt) {
            defs << s
        }
    }
    return MypyFile{...}
}
```

**Key Functions:**
- V AST to Mypy node conversion
- Function argument conversion
- Statement block conversion
- Expression conversion

### 3. Analyzer (`analyzer/`) — Type and Code Analysis

The module performs static analysis of Python code, integrating results from mypy.

**Module Structure:**
```
analyzer/
├── analyzer.v        # Main analyzer
├── visitor.v         # Type inference visitor
├── base.v            # Base analysis structures
├── inferers.v        # Alias and type inference
├── mypy_plugin.v     # Mypy plugin
├── mypy_bridge.v     # Bridge to mypy
├── mypy_tips.v       # Mypy tips
├── compatibility.v   # Python version compatibility
├── coroutines.v      # Coroutine handling
├── decorators.v      # Decorator handling
├── dependencies.v    # Dependency analysis
├── pydantic_detector.v  # Pydantic detection
└── utils.v           # Utilities
```

**Key Classes:**
```v
pub struct Analyzer {
	TypeInferenceVisitorMixin
pub mut:
	mypy_store MypyPluginStore
	context    string
	stack      []string
}

// Creation and analysis
pub fn new_analyzer(type_data map[string]string) &Analyzer
pub fn (mut a Analyzer) analyze(node ast.Module)

// Type operations
pub fn (a Analyzer) get_type(name string) ?string
pub fn (a Analyzer) get_mypy_type(name string, loc string) ?string
pub fn (mut a Analyzer) set_type(name string, typ string)
pub fn (mut a Analyzer) set_raw_type(name string, typ string)

// Mutability
pub fn (a Analyzer) get_mutability(name string) ?MutabilityInfo
pub fn (mut a Analyzer) set_mutability(name string, info MutabilityInfo)

// Class hierarchy
pub fn (mut a Analyzer) add_class_to_hierarchy(class_name string, bases []string)
pub fn (a Analyzer) get_class_bases(class_name string) []string
```

**Type Inference (TypeInferenceVisitorMixin):**
- Visits all AST nodes
- Stores types for variables and expressions
- Determines function return types
- Determines variable mutability
- Collects call signatures
- Detects TypedDict

**Alias Inference (alias_inferer):**
- Finds type aliases
- Determines real types for aliases
- Fills type_map with concrete types

**Mutability Scanner (function_mutability_scanner):**
- Determines which function parameters mutate
- Tracks variable reassignments
- Tracks mutations through methods

### 4. Translator (`translator/`) — Python to V Translation

The main module that converts typed Python AST to V code.

**Module Structure:**
```
translator/
├── translator.v            # Main translator
├── module.v                # Module handling
├── imports.v               # Imports
├── translator_statements.v # Statements
├── translator_control_flow.v # Control flow
├── translator_decls.v      # Declarations
├── translator_analysis.v   # Analysis functions
├── translator_helpers.v    # Helper functions
├── generator.v             # Code generator
├── vcode_emitter.v         # V code emitter
├── base/                   # Base infrastructure
│   ├── __init__.v
│   ├── base.v              # Base operations
│   ├── state.v             # Translator state
│   ├── state_extra.v       # Extra state
│   ├── expression_utils.v  # Expression utilities
│   ├── naming.v            # Naming
│   ├── precedence.v        # Precedence
│   ├── generics.v          # Generics handling
│   ├── type_guessing.v     # Type guessing
│   ├── type_registration.v # Type registration
│   └── type_utils.v        # Type utilities
├── classes/                # Class handling
├── control_flow/           # Control flow
├── expressions/            # Expressions and operators
├── functions/              # Function handling
├── variables/              # Variable handling
└── pydantic_support/       # Pydantic support
```

**Main Translator:**
```v
pub struct Translator {
pub mut:
	state                 &base.TranslatorState
	analyzer              &analyzer.Analyzer
	model                 models.VType
	mutable_locals        map[string]bool
	current_function_name string
	classes_module        classes.ClassesModule
	functions_module      functions.FunctionsModule
	coroutine_handler     analyzer.CoroutineHandler
	control_flow_module   control_flow.ControlFlowModule
}

pub fn new_translator() &Translator
pub fn (mut t Translator) translate(source string, filename string) string
```

**Translation Process (`translate`):**
1. Create new state
2. Preprocess source (compatibility)
3. Lex and parse
4. Preliminary `__all__` analysis
5. First analysis pass (fill type_map for aliases)
6. Run mypy analysis
7. Second analysis pass (refine types)
8. Visit all module statements
9. Add helper functions
10. Insert necessary imports

**Type Annotation Handling (`map_annotation`):**
- Recursive nested type processing
- `Optional[T]` → `?T`
- `Union[A, B]` → `A | B` or `SumType_AB`
- `List[T]` → `[]T`
- `Dict[K, V]` → `map[K]V`
- `Self` → `&ClassName`
- `TypeGuard`/`TypeIs`
- `Literal` types

#### Translator State (`TranslatorState`)

Structure holding all information about the current translation process:

```v
pub struct TranslatorState {
pub mut:
	output                  []string    // Output code
	tail                    []string    // Tail code
	indent_level            int         // Current indentation level
	in_main                 bool        // Flag: in fn main()

	// Current context
	current_class           string      // Current class
	current_class_generics  []string    // Class generics
	current_class_generic_map map[string]string // Generic map
	current_class_bases     []string    // Base classes
	current_class_body      []ast.Statement

	// Imports
	imported_modules        map[string]string
	imported_symbols        map[string]string

	// Classes and types
	defined_classes         map[string]map[string]bool
	class_hierarchy         map[string][]string
	main_to_mixins          map[string][]string
	typed_dicts             map[string]bool
	type_vars               map[string]bool
	generated_sum_types     map[string]string
	generated_literal_enums map[string]string

	// Functions
	overloads               map[string][]ast.FunctionDef
	overloaded_signatures   map[string][]map[string]string
	abstract_methods        map[string][]string
	property_setters        map[string]map[string]bool
	type_guards             map[string]TypeGuardInfo

	// Utilities
	used_builtins           map[string]bool  // Used built-in functions
	zip_counter             int
	match_counter           int
	unique_id_counter       int
	warnings                []string

	// Export
	module_all              []string
	include_all_symbols     bool
	strict_exports          bool

	// Analysis
	mapper                  voidptr    // StdLibMapper (stdlib_map/mapper.v)
	known_v_types           map[string]string
	// ... and many more fields
}
```

#### Python → V Type Mapping

Python type system maps to V via `models/v_types.v`:

| Python | V |
|--------|-----|
| `int` | `int` |
| `float`, `f64` | `f64` |
| `bool` | `bool` |
| `str`, `string`, `LiteralString` | `string` |
| `None` | `none` |
| `Any`, `object` | `Any` |
| `list[T]`, `List[T]` | `[]T` |
| `dict[K, V]`, `Dict[K, V]` | `map[K]V` |
| `set[T]`, `Set[T]` | `datatypes.Set[T]` |
| `tuple[A, B]`, `Tuple[A, B]` | `[A, B]` |
| `Optional[T]` | `?T` |
| `Union[A, B]` | `A \| B` or `SumType_AB` |
| `bytes`, `bytearray` | `[]u8` |
| `Callable[[], R]` | `fn () R` |
| `NoReturn` | `noreturn` |

Special V types:
- `Optional[T]` converts to `?T`
- `Union[A, B, None]` converts to `?T` (if one non-none type)
- `Union[A, B]` (multiple) converts to sum type (`A | B`) or registered as `SumType_AB`
- `TypeGuard[T]` / `TypeIs[T]` returns as `bool` with type narrowing info

### 5. Standard Library (`stdlib_map/`) — stdlib Mapping

Module contains mappings of Python stdlib functions to V equivalents.

**Module Structure:**
```
stdlib_map/
├── mapper.v    # Main stdlib mapper
└── builtins.v  # Python built-in functions
```

**Key Classes:**
```v
pub struct StdLibMapper {
pub mut:
	mappings  map[string]map[string]string
	v_imports map[string][]string
}

pub fn new_stdlib_mapper() &StdLibMapper
pub fn (m &StdLibMapper) get_mapping(mod_name string, func string, args []string) ?string
pub fn (m &StdLibMapper) get_constant_mapping(mod_name string, name string) ?string
pub fn (m &StdLibMapper) get_imports(mod_name string) ?[]string
```

**Supported Libraries:**
- **math**: sqrt, sin, cos, tan, exp, log, pow, ceil, floor, pi, e, ...
- **random**: randint, random, choice, seed, sample, shuffle, uniform, gauss, ...
- **json**: loads, dumps
- **time**: time, sleep
- **datetime**: datetime.now, date.today, datetime, date
- **sys**: exit, argv, platform
- **os**: environ, getcwd, system, getenv, mkdir, makedirs, remove, listdir, path.*, ...
- **io**: StringIO
- **re**: match, search, compile
- **shutil**: copy, copy2, move, rmtree, copytree, which, chown
- **logging**: getLogger, info, warning, error, debug, critical
- **argparse**: ArgumentParser, add_argument
- **uuid**: uuid4
- **collections**: defaultdict, Counter
- **itertools**: chain, repeat, count, cycle
- **functools**: reduce
- **operator**: add, sub, mul, truediv, mod, pow, eq, ne, lt, le, gt, ge, not_, and_, or_, xor
- **threading**: Thread, Lock
- **socket**: socket, AF_INET, SOCK_STREAM
- **pathlib**: Path
- **urllib.request**: urlopen
- **http.client**: HTTPConnection
- **csv**: reader, writer
- **sqlite3**: connect
- **subprocess**: run, call
- **platform**: system, machine, python_implementation
- **hashlib**: sha256, md5
- **base64**: b64encode, b64decode
- **urllib.parse**: urlparse, quote, unquote, urlencode
- **zlib**: compress, decompress
- **gzip**: compress, decompress
- **copy**: copy, deepcopy
- **struct**: pack, unpack, calcsize
- **array**: array
- **fractions**: Fraction
- **statistics**: mean, median, mode, stdev, variance
- **decimal**: Decimal, localcontext, getcontext
- **pickle**: dumps, loads, dump, load
- **contextlib**: closing, nullcontext, suppress, redirect_stdout
- **typing**: cast, get_type_hints
- **annotationlib**: get_annotations, Format

**Mapping Types:**
- **Direct**: `math.sqrt` → `math.sqrt`
- **With Arguments**: `math.pow(a, b)` → `math.pow(f64(__ARG0__), f64(__ARG1__))`
- **With Multiple Arguments**: `os.cp(__ARGS__)` → `os.cp(arg1, arg2)`
- **With Custom Function**: `random.choice(seq)` → `py_random_choice(seq)`

### 6. Models (`models/`) — Common Types and Contexts

Module contains common data structures used by other modules.

**Module Structure:**
```
models/
├── models.v      # Common models
├── v_types.v     # V types and type mapping
└── contexts.v    # Analysis contexts
```

**Key Types:**
```v
// V type enum
pub enum VType {
	int
	float
	string
	bool
	void_
	list
	dict
	tuple
	none
	unknown
}

// Generate struct name for tuple
pub fn get_tuple_struct_name(types_str string) string

// Python type → V type mapping (full version)
pub fn map_python_type_to_v(
	py_type string,
	self_name string,
	allow_union bool,
	generic_map map[string]string,
	sum_type_registrar fn (string) string,
	literal_registrar fn ([]string) string,
	tuple_registrar fn (string) string
) string
```

**Type Mapping Process:**
1. Clean type (remove quotes, `typing.`, `builtins.` prefixes)
2. Handle union types (`int | str`)
3. Handle generics (`List[int]`, `Dict[str, int]`)
4. Handle `Optional[T]` → `?T`
5. Handle `Union[A, B]` → `A | B` or sum type
6. Handle `Literal` types
7. Recursive nested type processing via `map_complex_type`

### 7. V Code Generator (`VCodeEmitter`)

Structure for generating final V code.

```v
pub struct VCodeEmitter {
pub mut:
	module_name     string
	imports         []string
	structs         []string
	functions       []string
	main_body       []string
	init_body       []string
	globals         []string
	constants       []string
	helper_imports  []string
	helper_structs  []string
	helper_functions []string
}
```

**Final File Generation:**
```v
// Output file format:
module {module_name}

import {import1}
import {import2}

struct {struct1} {}
struct {struct2} {}

__global {global1}
__global {global2}

pub const {const1} = ...
pub const {const2} = ...

fn {fn1}() { ... }
fn {fn2}() { ... }

fn init() {
    // Global initialization
}

fn main() {
    // Entry point
}
```

**Helper Functions:**
`VCodeEmitter.emit_global_helpers()` generates the helper file `vnake_helpers.v`:
- `NoneType` struct
- `Template` struct (for f-strings)
- `Interpolation` struct
- `Any` type alias
- `PyAnnotationFormat` enum
- Helper functions (`py_get_type_hints`)
- Importable V modules
- Class structures

### 8. Entry Point (`main.v`)

Main module handles command-line arguments and runs the transpilation process.

**Transpiler Configuration:**
```v
pub struct TranspilerConfig {
pub mut:
	warn_dynamic        bool       // Warnings about dynamic Any type
	no_helpers          bool       // Do not generate helper file
	helpers_only        bool       // Only generate helper file
	include_all_symbols bool       // Include all symbols (not just __all__)
	strict_exports      bool       // Warnings about symbols missing from __all__
	experimental        bool       // Enable experimental PEP features
	run                 bool       // Compile and run V code after transpilation
	analyze_deps        bool       // Dependency analysis (for directories)
	skip_dirs           []string   // Directories to skip
}
```

**Command-Line Arguments:**
| Option | Description |
|--------|-------------|
| `-r, --recursive` | Recursive directory processing |
| `--analyze-deps` | Dependency analysis |
| `--warn-dynamic` | Warnings about dynamic Any type |
| `--no-helpers` | Do not generate helper file |
| `--helpers-only` | Only generate helper file |
| `--include-all-symbols` | Include all symbols |
| `--strict-exports` | Strict export checking |
| `--experimental` | Experimental PEP features |
| `--run` | Compile and run V code |
| `--skip-dir <dir>` | Skip directory |

**Processing Flow:**

1. **Argument Parsing** (`parse_args`)
2. **Path Type Check**:
   - File → `transpile_file`
   - Directory → `process_directory`
   - `--analyze-deps` → `print_dependency_report`
   - `--helpers-only` → `generate_all_helpers`
3. **File Transpilation** (`transpile_file`):
   - Read Python source
   - Create translator
   - Call `translator.translate(source, filename)`
   - Write result to `.v` file
   - Run V code (if `--run`)

**Mypy Integration:**
```v
fn run_mypy_analysis(source string, filename string) analyzer.MypyPluginStore {
	// Parse source code
	mut lexer := ast.new_lexer(source, filename)
	mut parser := ast.new_parser(lexer)
	mod := parser.parse_module()

	// Create mypy API
	mut options := mypy.Options.new()
	mut errors := mypy.new_errors(*options)
	mut api := mypy.new_api(options, &errors)

	// Convert V AST → Mypy AST
	mut file := mypy.bridge(mod) or { ... }

	// Run type checking
	tc := api.check(mut file, map[string]mypy.MypyFile{}) or { ... }

	// Collect results
	mut plugin_analyzer := analyzer.new_mypy_plugin_analyzer()
	plugin_analyzer.collect_file_with_checker(file, &tc)
	return plugin_analyzer.store
}
```

## Data Flow

### 1. Input Phase
```
┌─────────────┐
│ Python File │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    Lexer    │ (ast/lexer.v)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Parser    │ (ast/parser.v)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Raw AST    │ (ast/ast.v)
└──────┬──────┘
```

### 2. Analysis Phase
```
       │
       ▼
┌─────────────┐
│ Analyzer    │ (analyzer/analyzer.v)
│   Pass 1    │   → type_map, aliases
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ mypy Bridge │ (mypy/bridge.v)
│   V AST →   │
│  MypyFile   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Mypy        │ (mypy/*.v)
│  Checker    │   → type checking
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Analyzer    │ (analyzer/mypy_plugin.v)
│   Pass 2    │   → refine types
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Typed AST   │ (type_map filled)
└──────┬──────┘
```

### 3. Translation Phase
```
       │
       ▼
┌─────────────┐
│ Translator  │ (translator/translator.v)
│             │
│ ┌─────────┐ │
│ │ map_    │ │  Type annotation handling
│ │ annot   │ │
│ └─────────┘ │
│ ┌─────────┐ │
│ │visitor  │ │  Visit AST nodes
│ │ stmts   │ │
│ └─────────┘ │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  V Code     │ ([]string buffer)
│  (output)   │
└──────┬──────┘
```

### 4. Output Phase
```
       │
       ▼
┌─────────────┐
│  Helpers    │ (VCodeEmitter)
│  Append     │   → py2v_helpers.v
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Import     │   → Insert imports
│  Insert     │     (math, rand, os, ...)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   V File    │   → Write .v file
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Compile &  │   → v run output.v
│   Execute   │
└─────────────┘
```

## Error Handling

### Python Exceptions → V Errors

Python exception handling is mapped to V error handling:

```python
# Python
try:
    risky_operation()
except ValueError as e:
    print(f"Error: {e}")
```

```v
// V
result := risky_operation() or {
    println('Error: ${err}')
    return
}
```

## Helper Functions

The transpiler generates helper functions for Python features without direct V equivalents.

**Location:** Generated as `vnake_helpers.v`

**Generated Helpers:**
- `py_random_choice()` — random choice from sequence
- `py_get_type_hints()` — get type annotations
- `py_copy()` / `py_deepcopy()` — copying
- `py_struct_*` — binary structure handling
- `py_array()` — arrays
- `py_hash_sha256` / `py_hash_md5` — hashing
- `py_path_new()` — path operations
- `py_urlparse()` / `py_urlopen()` — URL operations
- Many other Python stdlib functions

**Conditional Generation:**
- Only used helpers are included
- Tracked via `used_builtins` map in translator

## Configuration

### v.mod

```
Module {
	name: 'vlangtr'
	description: 'Python to V'
	version: '0.1.0'
	license: 'MIT'
	dependencies: []
}
```

### TranspilerConfig

```v
pub struct TranspilerConfig {
pub mut:
	warn_dynamic        bool       // Warnings about dynamic Any type
	no_helpers          bool       // Do not generate helper file
	helpers_only        bool       // Only generate helper file
	include_all_symbols bool       // Include all symbols
	strict_exports      bool       // Strict export checking
	experimental        bool       // Experimental PEP features
	run                 bool       // Compile and run V
	analyze_deps        bool       // Dependency analysis
	skip_dirs           []string   // Directories to skip
}
```

## Extending

### Adding New Mappings

1. **Stdlib Mapping**: Add to `stdlib_map/mapper.v`
```v
m.mappings['new_module'] = {
    'function': 'v_function'
}
```

2. **Type Mapping**: Add to `models/v_types.v`
```v
fn map_basic_type(name string) string {
    // ... existing mappings ...
    'NewType': 'v_type'
}
```

3. **AST Node**: Add method to translator
```v
fn (mut t Translator) visit_stmt(node ast.Statement) {
    match node {
        ast.NewNode { ... }
    }
}
```

### Adding Support for New Python Constructs

1. Add node to `ast/ast.v`
2. Add parsing to `ast/parser.v`
3. Add logic to `translator/translator_statements.v` or another module
4. Add tests to `tests/cases/`

## Testing

```
tests/
├── transpiler_test.v         # Main transpilation tests
├── remaining_expr_tests_test.v  # Individual expression tests
└── cases/                    # Test cases (.py + .expected.v pairs)
```

**Running Tests:**
```bash
# Run all tests
v -enable-globals test vlangtr/tests

# Run main tests
v -enable-globals test vlangtr/tests/transpiler_test.v

# Run expression tests
v -enable-globals test vlangtr/tests/remaining_expr_tests_test.v
```

**Test Pattern:**
```v
fn test_feature() {
    python_code := """
def foo() -> int:
    return 42
"""
    expected_v := """
fn foo() int {
    return 42
}
"""
    // Transpile Python code
    // Compare with expected V code
}
```

## Key Differences from Python Version

| Aspect | Python Version | V Version (vnake) |
|--------|---------------|-------------------|
| Implementation Language | Python | V |
| Parser | Python `ast` module | Custom parser (`ast/`) |
| Type Analysis | mypy API (Python) | Full mypy port (`mypy/`) |
| Performance | Slower (Python) | Faster (V, native) |
| Dependencies | mypy (Python package) | No external dependencies |
| Structure | Python modules | V modules |
| Testing | pytest | V test framework |

## Notes

- The project is fully self-contained with no external dependencies
- Mypy is fully ported including all internal modules
- Parser is compatible with Python AST (matches CPython `ast` module)
- Transpilation uses two-pass analysis for accurate type inference
- Supports a wide range of Python constructs and stdlib functions