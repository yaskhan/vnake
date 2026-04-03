import annotationlib

class Foo:
    x: int

def main():
    annos = annotationlib.get_annotations(Foo)
    print(annos)
