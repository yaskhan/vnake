from pydantic import BaseModel

class User(BaseModel):
    name: str

    class Config:
        allow_mutation = False
        extra = 'forbid'
