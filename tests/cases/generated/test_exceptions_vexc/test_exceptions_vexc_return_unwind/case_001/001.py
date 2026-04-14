def test_return():
    try:
        try:
            return 1
        except Exception:
            pass
    except Exception:
        pass
