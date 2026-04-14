class Person:
    _name: str = "Unknown"

    def __init__(self):
        self._name = "Unknown"

    @property
    def name(self) -> str:
        return self._name

    @name.setter
    def name(self, value: str):
        self._name = value
