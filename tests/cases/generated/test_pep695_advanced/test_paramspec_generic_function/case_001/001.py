def call_func[**P, R](func: Callable[P, R]) -> R:
    return func()
