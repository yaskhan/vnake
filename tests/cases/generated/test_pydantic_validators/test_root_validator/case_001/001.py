from pydantic import BaseModel, root_validator

class User(BaseModel):
    a: int
    b: int

    @root_validator(pre=False)
    def check_sum(cls, values: dict) -> dict:
        if values.get('a', 0) + values.get('b', 0) > 10:
            raise ValueError('Sum too large')
        return values
