from pydantic import BaseModel

class User(BaseModel):
    name: str

    class Config:
        min_anystr_length = 3
        max_anystr_length = 20
