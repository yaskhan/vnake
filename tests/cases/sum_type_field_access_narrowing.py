from typing import Union


class MyStruct:
    value: int


class Other:
    other: int


def process(obj: Union[MyStruct, Other]):
    if isinstance(obj, MyStruct):
        print(obj.value)
