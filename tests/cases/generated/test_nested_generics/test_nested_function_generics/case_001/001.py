def outer[T](x: T):
    def inner[U](y: U) -> T:
        return x
    return inner
