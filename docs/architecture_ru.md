# Архитектура Vnake Transpiler

Этот документ описывает внутреннюю архитектуру Vnake — транcпилятора из Python в язык V.

## Обзор

Проект полностью написан на языке V и следует **pipeline-архитектуре** с чёткими фазами обработки:

```
Python Source → Лексер → Парсер → AST → Анализатор (mypy) → Typed AST → Транслятор → V AST → Генератор → V Source
```

Ключевое отличие от исходного Python-проекта: все компоненты переписаны на V, включая полный порт mypy и собственный Python-совместимый парсер.

## Компоненты

### 1. AST (`ast/`) — Python-совместимый парсер

Полноценный парсер Python, совместимый с CPython AST. Состоит из нескольких модулей:

**Структура модуля:**
```
ast/
├── ast.v          # Узлы AST (выражения, инструкции, паттерны)
├── lexer.v        # Лексер Python (токенизация)
├── parser.v       # Парсер (Pratt parser для выражений)
├── token.v        # Определения токенов
├── visitor.v      # Посетитель для AST
├── printer.v      # Вывод AST в читаемом виде
├── serialize.v    # Сериализация AST
├── errors.v       # Обработка ошибок парсинга
└── parser_test.v  # Тесты парсера
```

**Поддерживаемые конструкции:**
- Все выражения Python (бинарные, унарные, сравнения, вызовы, атрибуты, подписки)
- Все инструкции (def, class, if/elif/else, for, while, try/except, match/case, with)
- Декораторы, async/await, yield/yield from
- Lambda, comprehensions, generator expressions
- F-strings с форматированием
- Named expressions (walrus operator)
- Type parameters (PEP 695)
- Pattern matching (match/case)

**Ключевые структуры:**
```v
// Базовый интерфейс AST
pub interface ASTNode {
	get_token() Token
	str() string
}

// Модуль верхнего уровня
pub struct Module {
	token    Token
	body     []Statement
	filename string
}

// Выражения
pub struct Name { id string; ctx ExprContext }
pub struct Constant { value string }
pub struct BinaryOp { left Expression; op Token; right Expression }
pub struct Call { func Expression; args []Expression; keywords []KeywordArg }
pub struct Attribute { value Expression; attr string; ctx ExprContext }
pub struct Subscript { value Expression; slice Expression; ctx ExprContext }
// ... и многие другие

// Инструкции
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
// ... и многие другие
```

**Подход к парсингу:**
- Pratt parser для выражений с корректной обработкой приоритетов
- Рекурсивный спуск для инструкций
- Поддержка Indentation/Dedentation через лексер
- Обработка цепочек сравнений (a == b == c)

### 2. Mypy (`mypy/`) — Полный порт mypy

Полный порт модуля mypy на языке V для статического анализа типов.

**Структура модуля:**
```
mypy/
├── nodes.v           # Узлы семантического AST mypy
├── types.v           # Система типов mypy
├── checker.v         # Проверка типов
├── checkexpr.v       # Проверка выражений
├── checkmember.v     # Проверка членов классов
├── checkstrformat.v  # Проверка форматирования строк
├── semanal.v         # Семантический анализ
├── semanal_main.v    # Основной семантический анализатор
├── semanal_enum.v    # Обработка Enum
├── semanal_namedtuple.v   # Named tuple
├── seminvar_typeddict.v   # TypedDict
├── infer.v           # Вывод типов
├── solve.v           # Решение ограничений типов
├── subtypes.v        # Подтипы
├── join.v            # Объединение типов
├── meet.v            # Пересечение типов
├── constraints.v     # Ограничения
├── expandtype.v      # Развёртка типов
├── typeanal.v        # Анализ типов
├── typeops.v         # Операции с типами
├── visitor.v         # Посетитель
├── traverser.v       # Обход дерева
├── bridge.v          # Мост: V AST → Mypy AST
├── build.v           # Сборка и загрузка модулей
├── options.v         # Настройки mypy
├── errors.v          # Обработка ошибок
├── messages.v        # Сообщения об ошибках
├── plugin.v          # Плагины
├── binder.v          # Привязка типов
├── literals.v        # Литеральные типы
├── patterns.v        # Паттерны
├── ...
```

**Мост (bridge.v):**
Конвертирует V AST (из `ast/`) в Mypy AST для последующего анализа типов:

```v
// bridge конвертирует V AST → Mypy AST
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

**Ключевые функции:**
- Конвертация V AST узлов в Mypy узлы
- Конвертация аргументов функций
- Конвертация блоков инструкций
- Конвертация выражений

### 3. Анализатор (`analyzer/`) — Анализ типов и кода

Модуль выполняет статический анализ Python кода, интегрируя результаты из mypy.

**Структура модуля:**
```
analyzer/
├── analyzer.v        # Главный анализатор
├── visitor.v         # Посетитель для вывода типов
├── base.v            # Базовые структуры анализа
├── inferers.v        # Инференс алиасов и типов
├── mypy_plugin.v     # Плагин mypy
├── mypy_bridge.v     # Мост к mypy
├── mypy_tips.v       # Подсказки mypy
├── compatibility.v   # Совместимость версий Python
├── coroutines.v      # Обработка корутин
├── decorators.v      # Обработка декораторов
├── dependencies.v    # Анализ зависимостей
├── pydantic_detector.v  # Детектор Pydantic
├── utils.v           # Утилиты
```

**Ключевые классы:**
```v
pub struct Analyzer {
	TypeInferenceVisitorMixin
pub mut:
	mypy_store MypyPluginStore
	context    string
	stack      []string
}

// Создание и запуск анализа
pub fn new_analyzer(type_data map[string]string) &Analyzer
pub fn (mut a Analyzer) analyze(node ast.Module)

// Работа с типами
pub fn (a Analyzer) get_type(name string) ?string
pub fn (a Analyzer) get_mypy_type(name string, loc string) ?string
pub fn (mut a Analyzer) set_type(name string, typ string)
pub fn (mut a Analyzer) set_raw_type(name string, typ string)

// Мутабельность
pub fn (a Analyzer) get_mutability(name string) ?MutabilityInfo
pub fn (mut a Analyzer) set_mutability(name string, info MutabilityInfo)

// Иерархия классов
pub fn (mut a Analyzer) add_class_to_hierarchy(class_name string, bases []string)
pub fn (a Analyzer) get_class_bases(class_name string) []string
```

**Вывод типов (TypeInferenceVisitorMixin):**
- Посещает все узлы AST
- Сохраняет типы для переменных и выражений
- Определяет возвращаемые типы функций
- Определяет мутабельность переменных
- Собирает сигнатуры вызовов
- Определяет TypedDict

**Инференс алиасов (alias_inferer):**
- Находит алиасы типов
- Определяет реальные типы для алиасов
- Заполняет type_map конкретными типами

**Сканнер мутабельности (function_mutability_scanner):**
- Определяет какие параметры функций мутируют
- Отслеживает переназначения переменных
- Отслеживает мутации через методы

### 4. Транслятор (`translator/`) — Перевод Python в V

Основной модуль, который преобразует типизированный AST Python в код V.

**Структура модуля:**
```
translator/
├── translator.v            # Главный транслятор
├── module.v                # Обработка модулей
├── imports.v               # Импорт
├── translator_statements.v # Инструкции
├── translator_control_flow.v # Управляющие конструкции
├── translator_decls.v      # Объявления
├── translator_analysis.v   # Аналитические функции
├── translator_helpers.v    # Вспомогательные функции
├── generator.v             # Генератор кода
├── vcode_emitter.v         # Эмиттер V кода
├── base/                   # Базовая инфраструктура
│   ├── __init__.v
│   ├── base.v              # Базовые операции
│   ├── state.v             # Состояние транслятора
│   ├── state_extra.v       # Дополнительное состояние
│   ├── expression_utils.v  # Утилиты выражений
│   ├── naming.v            # Именование
│   ├── precedence.v        # Приоритеты
│   ├── generics.v          # Обработка дженериков
│   ├── type_guessing.v     # Угадывание типов
│   ├── type_registration.v # Регистрация типов
│   └── type_utils.v        # Утилиты типов
├── classes/                # Обработка классов
├── control_flow/           # Управляющие конструкции
├── expressions/            # Выражения и операторы
├── functions/              # Обработка функций
├── variables/              # Обработка переменных
└── pydantic_support/       # Поддержка Pydantic
```

**Главный транслятор:**
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

**Процесс трансляции (`translate`):**
1. Создание нового состояния
2. Препроцессинг исходника (совместимость)
3. Лексирование и парсинг
4. Предварительный анализ `__all__`
5. Первый проход анализа (заполнение type_map для алиасов)
6. Запуск mypy-анализа
7. Второй проход анализа (уточнение типов)
8. Посещение всех инструкций модуля
9. Добавление вспомогательных функций
10. Вставка необходимых импортов

**Обработка аннотаций типов (`map_annotation`):**
- Рекурсивная обработка вложенных типов
- Обработка `Optional[T]` → `?T`
- Обработка `Union[A, B]` → `A | B` или `SumType_AB`
- Обработка `List[T]` → `[]T`
- Обработка `Dict[K, V]` → `map[K]V`
- Обработка `Self` → `&ClassName`
- Обработка `TypeGuard`/`TypeIs`
- Обработка `Literal` типов

#### Состояние транслятора (`TranslatorState`)

Структура, хранящая всю информацию о текущем процессе трансляции:

```v
pub struct TranslatorState {
pub mut:
	output                  []string    // Выходной код
	tail                    []string    // Хвостовой код
	indent_level            int         // Текущая глубина отступа
	in_main                 bool        // Флаг: в fn main()

	// Текущий контекст
	current_class           string      // Текущий класс
	current_class_generics  []string    // Дженерики класса
	current_class_generic_map map[string]string // Карта дженериков
	current_class_bases     []string    // Базовые классы
	current_class_body      []ast.Statement

	// Импорты
	imported_modules        map[string]string
	imported_symbols        map[string]string

	// Классы и типы
	defined_classes         map[string]map[string]bool
	class_hierarchy         map[string][]string
	main_to_mixins          map[string][]string
	typed_dicts             map[string]bool
	type_vars               map[string]bool
	generated_sum_types     map[string]string
	generated_literal_enums map[string]string

	// Функции
	overloads               map[string][]ast.FunctionDef
	overloaded_signatures   map[string][]map[string]string
	abstract_methods        map[string][]string
	property_setters        map[string]map[string]bool
	type_guards             map[string]TypeGuardInfo

	// Утилиты
	used_builtins           map[string]bool  // Используемые встроенные функции
	zip_counter             int
	match_counter           int
	unique_id_counter       int
	warnings                []string

	// Экспорт
	module_all              []string
	include_all_symbols     bool
	strict_exports          bool

	// Анализ
	mapper                  voidptr    // StdLibMapper (stdlib_map/mapper.v)
	known_v_types           map[string]string
	// ... и многие другие поля
}
```

#### Сопоставление типов Python → V

Система типов Python отображается на V через `models/v_types.v`:

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
| `Union[A, B]` | `A \| B` или `SumType_AB` |
| `bytes`, `bytearray` | `[]u8` |
| `Callable[[], R]` | `fn () R` |
| `NoReturn` | `noreturn` |

Специальные типы V:
- `Optional[T]` конвертируется в `?T`
- `Union[A, B, None]` конвертируется в `?T` (если один не-none тип)
- `Union[A, B]` (множественный) конвертируется в sum type (`A | B`) или регистрируется как `SumType_AB`
- `TypeGuard[T]` / `TypeIs[T]` возвращается как `bool` с информацией о сужении типа

### 5. Стандартная библиотека (`stdlib_map/`) — Маппинг stdlib

Модуль содержит маппинги функций Python stdlib на эквиваленты V.

**Структура модуля:**
```
stdlib_map/
├── mapper.v    # Главный маппер stdlib
└── builtins.v  # Встроенные функции Python
```

**Ключевые классы:**
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

**Поддерживаемые библиотеки:**
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

**Типы маппингов:**
- **Прямой**: `math.sqrt` → `math.sqrt`
- **С аргументами**: `math.pow(a, b)` → `math.pow(f64(__ARG0__), f64(__ARG1__))`
- **С несколькими аргументами**: `os.cp(__ARGS__)` → `os.cp(arg1, arg2)`
- **С кастомной функцией**: `random.choice(seq)` → `py_random_choice(seq)`

### 6. Модели (`models/`) — Общие типы и контексты

Модуль содержит общие структуры данных, используемые другими модулями.

**Структура модуля:**
```
models/
├── models.v      # Общие модели
├── v_types.v     # Типы V и маппинг типов
└── contexts.v    # Контексты анализа
```

**Ключевые типы:**
```v
// Перечисление типов V
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

// Генерация имени struct для tuple
pub fn get_tuple_struct_name(types_str string) string

// Маппинг Python типа → V тип (полная версия)
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

**Процесс маппинга типов:**
1. Очистка типа (удаление кавычек, `typing.`, `builtins.` префиксов)
2. Обработка union типов (`int | str`)
3. Обработка дженериков (`List[int]`, `Dict[str, int]`)
4. Обработка `Optional[T]` → `?T`
5. Обработка `Union[A, B]` → `A | B` или sum type
6. Обработка `Literal` типов
7. Рекурсивная обработка вложенных типов через `map_complex_type`

### 7. Генератор V кода (`VCodeEmitter`)

Структура для генерации финального V кода.

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

**Генерация финального файла:**
```v
// Формат выходного файла:
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
    // Глобальная инициализация
}

fn main() {
    // Точка входа
}
```

**Вспомогательные функции:**
`VCodeEmitter.emit_global_helpers()` генерирует вспомогательный файл `vnake_helpers.v`:
- `NoneType` struct
- `Template` struct (для f-strings)
- `Interpolation` struct
- `Any` type alias
- `PyAnnotationFormat` enum
- Вспомогательные функции (`py_get_type_hints`)
- Импортируемые V модули
- Структуры классов

### 8. Точка входа (`main.v`)

Главный модуль обрабатывает аргументы командной строки и запускает процесс транcпиляции.

**Конфигурация транcпилятора:**
```v
pub struct TranspilerConfig {
pub mut:
	warn_dynamic        bool       // Предупреждения о dynamic Any type
	no_helpers          bool       // Не генерировать helper файл
	helpers_only        bool       // Только генерировать helper файл
	include_all_symbols bool       // Включать все символы (не только __all__)
	strict_exports      bool       // Предупреждения о символах, отсутствующих в __all__
	experimental        bool       // Включить экспериментальные PEP функции
	run                 bool       // Компилировать и запустить V код после транcпиляции
	analyze_deps        bool       // Анализ зависимостей (для каталогов)
	skip_dirs           []string   // Пропускаемые каталоги
}
```

**Аргументы командной строки:**
| Опция | Описание |
|-------|----------|
| `-r, --recursive` | Рекурсивная обработка каталогов |
| `--analyze-deps` | Анализ зависимостей |
| `--warn-dynamic` | Предупреждения о dynamic Any type |
| `--no-helpers` | Не генерировать helper файл |
| `--helpers-only` | Только генерировать helper файл |
| `--include-all-symbols` | Включить все символы |
| `--strict-exports` | Строгий экспорт |
| `--experimental` | Экспериментальные PEP функции |
| `--run` | Компилировать и запустить V код |
| `--skip-dir <dir>` | Пропустить каталог |

**Процесс обработки:**

1. **Парсинг аргументов** (`parse_args`)
2. **Проверка типа пути**:
   - Файл → `transpile_file`
   - Каталог → `process_directory`
   - `--analyze-deps` → `print_dependency_report`
   - `--helpers-only` → `generate_all_helpers`
3. **Транcпиляция файла** (`transpile_file`):
   - Чтение исходного Python кода
   - Создание транслятора
   - Вызов `translator.translate(source, filename)`
   - Запись результата в `.v` файл
   - Запуск V кода (если `--run`)

**Интеграция с mypy:**
```v
fn run_mypy_analysis(source string, filename string) analyzer.MypyPluginStore {
	// Парсинг исходного кода
	mut lexer := ast.new_lexer(source, filename)
	mut parser := ast.new_parser(lexer)
	mod := parser.parse_module()

	// Создание mypy API
	mut options := mypy.Options.new()
	mut errors := mypy.new_errors(*options)
	mut api := mypy.new_api(options, &errors)

	// Конвертация V AST → Mypy AST
	mut file := mypy.bridge(mod) or { ... }

	// Запуск проверки типов
	tc := api.check(mut file, map[string]mypy.MypyFile{}) or { ... }

	// Сбор результатов
	mut plugin_analyzer := analyzer.new_mypy_plugin_analyzer()
	plugin_analyzer.collect_file_with_checker(file, &tc)
	return plugin_analyzer.store
}
```

## Поток данных

### 1. Фаза ввода
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

### 2. Фаза анализа
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
│ Typed AST   │ (type_map заполнен)
└──────┬──────┘
```

### 3. Фаза трансляции
```
       │
       ▼
┌─────────────┐
│ Translator  │ (translator/translator.v)
│             │
│ ┌─────────┐ │
│ │ map_    │ │  Обработка аннотаций
│ │ annot   │ │
│ └─────────┘ │
│ ┌─────────┐ │
│ │visitor  │ │  Посещение AST узлов
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

### 4. Фаза вывода
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
│  Import     │   → Добавление импортов
│  Insert     │     (math, rand, os, ...)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   V File    │   → Запись .v файла
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Compile &  │   → v run output.v
│   Execute   │
└─────────────┘
```

## Обработка ошибок

### Python исключения → V ошибки

Обработка исключений Python маппируется на V error handling:

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

## Вспомогательные функции

Транcпилятор генерирует helper-функции для функций Python без прямых аналогов в V.

**Локация:** генерируется как `vnake_helpers.v`

**Генерируемые helpers:**
- `py_random_choice()` — случайный выбор из последовательности
- `py_get_type_hints()` — получение аннотаций типов
- `py_copy()` / `py_deepcopy()` — копирование
- `py_struct_*` — работа с бинарными структурами
- `py_array()` — массивы
- `py_hash_sha256` / `py_hash_md5` — хэши
- `py_path_new()` — работа с путями
- `py_urlparse()` / `py_urlopen()` — URL операции
- Множество других функций для Python stdlib

**Условная генерация:**
- Включаются только используемые helpers
- Отслеживаются через `used_builtins` map в трансляторе

## Конфигурация

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
	warn_dynamic        bool       // Предупреждения о dynamic Any type
	no_helpers          bool       // Не генерировать helper файл
	helpers_only        bool       // Только генерировать helper файл
	include_all_symbols bool       // Включать все символы
	strict_exports      bool       // Строгая проверка экспорта
	experimental        bool       // Экспериментальные PEP функции
	run                 bool       // Компилировать и запустить V
	analyze_deps        bool       // Анализ зависимостей
	skip_dirs           []string   // Пропускаемые каталоги
}
```

## Расширение

### Добавление новых маппингов

1. **Stdlib Mapping**: Добавить в `stdlib_map/mapper.v`
```v
m.mappings['new_module'] = {
    'function': 'v_function'
}
```

2. **Type Mapping**: Добавить в `models/v_types.v`
```v
fn map_basic_type(name string) string {
    // ... существующие маппинги ...
    'NewType': 'v_type'
}
```

3. **AST Node**: Добавить метод в транслятор
```v
fn (mut t Translator) visit_stmt(node ast.Statement) {
    match node {
        ast.NewNode { ... }
    }
}
```

### Добавление поддержки новых Python конструкций

1. Добавить узел в `ast/ast.v`
2. Добавить парсинг в `ast/parser.v`
3. Добавить логику в `translator/translator_statements.v` или другой модуль
4. Добавить тесты в `tests/cases/`

## Тестирование

```
tests/
├── transpiler_test.v         # Основные тесты трансляции
├── remaining_expr_tests_test.v  # Тесты отдельных выражений
└── cases/                    # Тест-кейсы (.py + .expected.v пары)
```

**Запуск тестов:**
```bash
# Запуск всех тестов
v -enable-globals test vlangtr/tests

# Запуск основных тестов
v -enable-globals test vlangtr/tests/transpiler_test.v

# Запуск тестов выражений
v -enable-globals test vlangtr/tests/remaining_expr_tests_test.v
```

**Паттерн тестов:**
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
    // Транспиляция Python кода
    // Сравнение с ожидаемым V кодом
}
```

## Ключевые отличия от Python-версии

| Аспект | Python-версия | V-версия (vnake) |
|--------|---------------|-------------------|
| Язык реализации | Python | V |
| Парсер | `ast` module Python | Собственный парсер (`ast/`) |
| Анализ типов | mypy API (Python) | Полный порт mypy (`mypy/`) |
| Производительность | Медленнее (Python) | Быстрее (V, нативный) |
| Зависимости | mypy (Python пакет) | Нет внешних зависимостей |
| Структура | Модули Python | Модули V |
| Тестирование | pytest | V test framework |

## Примечания

- Проект полностью самодостаточен и не зависит от внешних пакетов
- Mypy портирован полностью, включая все внутренние модули
- Парсер совместим с Python AST (соответствует `ast` модулю CPython)
- Транcпиляция использует двухпроходный анализ для точного вывода типов
- Поддерживается широкий набор Python конструкций и stdlib функций