class Drawable:
    def draw(self) -> str:
        return "generic"


class Circle(Drawable):
    def draw(self):
        print("drawing")
