def to_bytes(msg: str):
            b1 = bytes(msg, "utf8")
            b2 = bytes(msg, encoding="utf-8")
            print(b1, b2)
