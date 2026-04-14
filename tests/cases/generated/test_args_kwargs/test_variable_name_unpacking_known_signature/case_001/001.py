def func(a: int, b: int, c: int) -> int:
    return a + b + c

kwargs = {"a": 1, "b": 2, "c": 3}
result = func(**kwargs)
