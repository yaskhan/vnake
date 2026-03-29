interface Base {
    __init__(x int)
}
@[heap]
struct Base_Impl {
pub mut:
    x int
}
fn (mut self Base_Impl) init(x int) {
    self.x = x
}
pub const base_impl_init_annotations = { 'x': 'int' }
@[heap]
struct Derived {
pub mut:
    Base_Impl
    y int
}
fn new_derived(x int, y int) Derived {
    mut self := Derived{}
    self.init(x, y)
    return self
}
fn (mut self Derived) init(x int, y int) {
    self.Base_Impl = new_base_impl(x)
    self.y = y
}
pub const derived_init_annotations = { 'x': 'int', 'y': 'int' }