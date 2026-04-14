class Descriptor:
    def __get__(self, instance, owner) -> int:
        return 42

class MyClass:
    desc: Descriptor

def test_func():
    m = MyClass()
    return m.desc
