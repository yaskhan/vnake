from pydantic import BaseModel, validator

class User(BaseModel):
    name: str

    @validator('name', pre=True)
    def validate_name(cls, v: str) -> str:
        if not v:
            raise ValueError('Empty name')
        return v
