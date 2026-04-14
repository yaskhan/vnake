from typing import Callable
def apply_function(f: Callable[[int], int], values: list[int]) -> list[int]:
    return [f(v) for v in values]
