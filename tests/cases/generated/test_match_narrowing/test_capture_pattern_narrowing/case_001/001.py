from typing import Union

class A:
    a: int

def test_match(x: object):
    match x:
        case A() as a_val:
            return a_val.a
