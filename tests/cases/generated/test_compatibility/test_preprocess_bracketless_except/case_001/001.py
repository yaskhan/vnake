try:
    x = 1 / 0
except ValueError, ZeroDivisionError as e:
    print(e)
