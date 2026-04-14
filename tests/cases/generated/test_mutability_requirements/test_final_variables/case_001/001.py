from typing import Final
        def test():
            CONST: Final = 42
            # Even if we try to "mutate" it (though mypy would complain),
            # the transpiler should respect Final.
            return CONST
