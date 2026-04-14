from pydantic import BaseModel, field_validator

class User(BaseModel):
    name: str

    @field_validator('name')
    @classmethod
    def validate_name(cls, v: str) -> str:
        if len(v) < 2:
            raise ValueError('Name too short')
        return v.title()
