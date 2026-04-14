from typing import Optional


class Data:
    id: int


def handle(data: Optional[Data]):
    if data is not None:
        print(data.id)
