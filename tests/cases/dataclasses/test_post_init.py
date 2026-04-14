from dataclasses import dataclass, InitVar

@dataclass
class Point:
    x: int
    y: int
    scale: InitVar[int] = 1
    offset: InitVar[int] = 0

    def __post_init__(self, scale: int, offset: int):
        self.x = self.x * scale + offset
        self.y = self.y * scale + offset

p1 = Point(10, 20)
p2 = Point(10, 20, 2)
p3 = Point(10, 20, scale=3, offset=5)

print(f"{p1.x}, {p1.y}")
print(f"{p2.x}, {p2.y}")
print(f"{p3.x}, {p3.y}")
