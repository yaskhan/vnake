from typing import Callable
def process(f: Callable[[int, str], bool], x: int, s: str) -> bool:
    return f(x, s)
