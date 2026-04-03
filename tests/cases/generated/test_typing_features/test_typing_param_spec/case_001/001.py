from typing import ParamSpec, TypeVar, Callable

P = ParamSpec("P")
R = TypeVar("R")

def foo(f: Callable[P, R]) -> Callable[P, R]:
    return f
