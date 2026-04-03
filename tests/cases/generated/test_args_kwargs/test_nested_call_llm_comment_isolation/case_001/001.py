def outer(x: int) -> int:
    return x

from some_external_module import unresolvable

d = {"x": 1}
result = outer(unresolvable(**d))
