def func(a: int, b: int) -> int:
    return a + b

k = "a"
result = func(**{k: 1, "b": 2})
