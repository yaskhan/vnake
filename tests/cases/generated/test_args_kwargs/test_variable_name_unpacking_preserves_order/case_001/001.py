def func(x: int, y: int) -> int:
    return x + y

params = {"y": 2, "x": 1}
result = func(**params)
