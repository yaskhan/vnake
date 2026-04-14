class Parent:
    def greet(self):
        pass

class Child(Parent):
    def greet(self):
        super().greet()

def check(x):
    if x is None:
        pass
    if x is not None:
        pass
    t = type(x)
    cls = x.__class__
    if isinstance(x, int):
        pass
