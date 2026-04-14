import collections.abc
def apply(f: collections.abc.Callable[[int], int], x: int) -> int:
    return f(x)
