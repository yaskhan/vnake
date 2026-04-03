class Decimal:
    def __new__(cls, value: str) -> "Decimal":
        return Decimal()

    def __init__(self, value: str):
        self.value = value
