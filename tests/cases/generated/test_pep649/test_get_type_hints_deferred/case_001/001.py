from typing import get_type_hints

class Foo:
    x: 'Bar'

class Bar:
    y: int

def main():
    hints = get_type_hints(Foo)
    print(hints)
