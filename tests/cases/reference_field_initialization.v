module main

@[heap]
struct Node {
pub mut:
    next NoneType
}

fn new_node() &Node {
    mut self := &Node{next: none}
    self.next = none
    return self
}