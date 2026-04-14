class Box:
    item: object

class Point:
    x: int
    y: int

def test_match(box: Box):
    match box.item:
        case Point(x=x_val) as p:
            return x_val + p.y
