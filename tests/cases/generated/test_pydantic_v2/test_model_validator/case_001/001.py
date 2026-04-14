from pydantic import BaseModel, model_validator

class MyModel(BaseModel):
    x: int
    y: int

    @model_validator(mode='after')
    def check_sum(self) -> "MyModel":
        if self.x + self.y > 100:
            raise ValueError('sum too large')
        return self
