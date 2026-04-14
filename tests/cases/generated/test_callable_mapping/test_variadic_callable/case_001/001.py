from typing import Callable, Any
def call_any(f: Callable[..., Any], *args: Any) -> Any:
    return f(*args)
