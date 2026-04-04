import translator

fn main() {
    source := 'l = [1, 2, 3]
l[1:2] = [4]'
    mut t := translator.new_translator()
    res := t.translate(source, 'test.py')
    println(res)
}
