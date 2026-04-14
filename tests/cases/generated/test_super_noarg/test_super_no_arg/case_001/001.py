class Parent:
    def foo(self):
        pass

class Child(Parent):
    def foo(self):
        super().foo()
