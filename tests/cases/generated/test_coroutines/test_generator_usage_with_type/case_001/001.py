from typing import Iterator

def gen() -> Iterator[str]:
    yield "a"

def main():
    for x in gen():
        print(x)
