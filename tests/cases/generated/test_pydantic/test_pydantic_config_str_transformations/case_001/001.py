from pydantic import BaseModel

class User(BaseModel):
    name: str
    email: str

    class Config:
        str_strip_whitespace = True
        str_to_lower = True
