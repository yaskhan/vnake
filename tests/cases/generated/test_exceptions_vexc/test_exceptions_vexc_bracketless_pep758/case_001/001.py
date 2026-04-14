def test_bracketless():
    try:
        pass
    except (ValueError, TypeError, OsError, IoError) as e:
        pass
