class Base:
    def __init__(self, x: int):
        self.x = x

class Derived(Base):
    def __init__(self, x: int, y: int):
        Base.__init__(self, x)
        self.y = y
