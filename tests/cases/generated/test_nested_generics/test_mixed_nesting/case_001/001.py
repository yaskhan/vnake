class Outer[T]:
    def method[U](self, x: T, y: U):
        def inner[V](z: V) -> T:
            return x
        return inner
