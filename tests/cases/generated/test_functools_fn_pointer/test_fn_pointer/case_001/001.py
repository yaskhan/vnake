import typing
class Cached_property[T]:
    fn: typing.Callable[[typing.Any], T]
    attrname: typing.Optional[str]
