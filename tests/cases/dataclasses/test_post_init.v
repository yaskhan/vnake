module main

// @dataclass
@[heap]
struct Point {
pub mut:
    x int
    y int
}

const point_post_init_annotations = { "scale": "int", "offset": "int" }

fn new_point(x int, y int, scale int, offset int) &Point {
    mut self := &Point{x: x, y: y}
    self.post_init(scale, offset)
    return self
}

fn (mut self Point) post_init(scale int, offset int) {
    self.x = self.x * scale + offset
    self.y = self.y * scale + offset
}

fn main() {
    p1 := new_point(10, 20)
    p2 := new_point(10, 20, 2)
    p3 := new_point(10, 20)
    println("${p1.x}, ${p1.y}")
    println("${p2.x}, ${p2.y}")
    println("${p3.x}, ${p3.y}")
}