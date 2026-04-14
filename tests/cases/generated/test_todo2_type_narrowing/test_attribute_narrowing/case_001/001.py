class Base:
    pass

class Derived(Base):
    def derived_method(self) -> int:
        return 1

def test_func(obj: Base):
    if isinstance(obj, Derived):
        return obj.derived_method()
