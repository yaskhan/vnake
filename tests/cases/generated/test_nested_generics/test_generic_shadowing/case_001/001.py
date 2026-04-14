def outer[T](x: T):
    def inner[T](y: T) -> T:
        return y
    return inner
