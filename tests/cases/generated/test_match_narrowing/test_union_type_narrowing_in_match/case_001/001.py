from typing import Union

class A:
    a: int

class B:
    b: str

def test_match(x: Union[A, B]):
    match x:
        case A():
            return x.a
        case B():
            return x.b
