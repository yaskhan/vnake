from typing import Callable
def apply(f: Callable[[int], int], x: int) -> int:
    return f(x)
