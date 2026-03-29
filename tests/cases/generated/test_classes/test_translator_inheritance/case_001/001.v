interface Base {
    x int
}
@[heap]
struct Base_Impl {
pub mut:
    x int
}
fn new_base_impl(x int) &Base_Impl {
    mut self := &Base_Impl{}
    self.x = x
    return self
}
pub const base_impl_new_base_impl_annotations = { 'x': 'int' }
fn (mut self Base_Impl) init(x int) {
    self.x = x
}
pub const base_impl_init_annotations = { 'x': 'int' }
@[heap]
struct Derived {
    Base_Impl
pub mut:
    y int
}
fn new_derived(x int, y int) &Derived {
    mut self := &Derived{}
    self.x = x
    self.y = y
    return self
}
pub const derived_new_derived_annotations = { 'x': 'int', 'y': 'int' }
fn (mut self Derived) init(x int, y int) {
    self.Base_Impl = *new_base_impl(x)
    self.y = y
}
pub const derived_init_annotations = { 'x': 'int', 'y': 'int' }