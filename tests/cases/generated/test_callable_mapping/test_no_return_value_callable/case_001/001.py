from typing import Callable
def execute(f: Callable[[], None]) -> None:
    f()
