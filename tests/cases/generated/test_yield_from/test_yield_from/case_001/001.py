def sub_gen():
    yield 1
    yield 2

def gen():
    yield from sub_gen()
