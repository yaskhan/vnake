class Outer:
                class Inner:
                    def __init__(self, val: int):
                        self.val = val
                def make_inner(self, v: int) -> Inner:
                    return self.Inner(v)
