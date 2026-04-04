module main

@[heap]
struct MyClass[U] {
}

const my_func_annotations = { "x": "T" }
const my_func_type_params = [ "T" ]
pub const my_class_type_params = [ 'U' ]

fn my_func[T](x T) {
}

fn new_my_class[U]() &MyClass[U] {
    mut self := &MyClass[U]{}
    return self
}

fn main() {
    println("Func: ${my_func_type_params}")
    println("Class: ${my_class_type_params}")
}