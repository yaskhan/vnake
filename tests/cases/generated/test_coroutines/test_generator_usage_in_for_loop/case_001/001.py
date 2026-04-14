def gen(max):
    for i in range(max):
        yield i

def main():
    for x in gen(5):
        print(x)
