def test(x: str | int):
    if isinstance(x, str):
        print(x.upper())
        x = 1
        print(x + 1)
