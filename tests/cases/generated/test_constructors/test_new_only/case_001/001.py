class Decimal:
    def __new__(cls, value: str) -> "Decimal":
        return object.__new__(cls)
