def check_val(x: object) -> str:
    match x:
        case int(n) if n > 10:
            return "Large int"
        case int(n):
            return "Small int"
        case _:
            return "Not an int"

def test_main():
    assert check_val(15) == "Large int"
    assert check_val(5) == "Small int"
    assert check_val("hi") == "Not an int"
