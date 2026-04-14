class User:
    def __init__(self, name: str):
        self.name = name

def check_user(u: object) -> str:
    match u:
        case User(name=n) if len(n) > 5:
            return "Long: " + n
        case User(name=n):
            return "Short: " + n
        case str(s) if s.startswith("a"):
            return "Starts with a: " + s
        case _:
            return "Other"

def test_main():
    assert check_user(User("Alice")) == "Short: Alice"
    assert check_user(User("Bob")) == "Short: Bob"
    assert check_user(User("Alexander")) == "Long: Alexander"
    assert check_user("apple") == "Starts with a: apple"
    assert check_user("banana") == "Other"
    assert check_user(123) == "Other"

if __name__ == "__main__":
    test_main()
