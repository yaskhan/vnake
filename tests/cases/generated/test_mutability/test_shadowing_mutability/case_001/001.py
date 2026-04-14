def foo():
            x = 1
            if True:
                x = 2 # Shadows or reassigns? In Python it reassigns.
            return x
