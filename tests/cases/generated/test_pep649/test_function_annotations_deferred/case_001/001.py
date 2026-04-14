from typing import get_type_hints

def func(x: 'Bar') -> 'Bar':
    return x

class Bar:
    pass

def main():
    print(get_type_hints(func))
