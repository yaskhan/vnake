def foo():
    b = bytearray(5)
    b[0] = 65
    b = b + b"abc"
    return b
