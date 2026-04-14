class Outer:
                class Inner:
                    def __init__(self, x: int):
                        self.x = x
                    def get_x(self) -> int:
                        return self.x
