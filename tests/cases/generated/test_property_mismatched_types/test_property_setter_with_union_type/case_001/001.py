class Config:
    _value: int = 0

    def __init__(self):
        self._value = 0

    @property
    def value(self) -> int:
        return self._value

    @value.setter
    def value(self, new_value: str | int):
        if isinstance(new_value, str):
            self._value = int(new_value)
        else:
            self._value = new_value
