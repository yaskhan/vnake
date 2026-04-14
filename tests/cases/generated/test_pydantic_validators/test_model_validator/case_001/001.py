from pydantic import BaseModel, model_validator

class User(BaseModel):
    password: str
    confirm_password: str

    @model_validator(mode='after')
    def check_passwords(self) -> 'User':
        if self.password != self.confirm_password:
            raise ValueError('Passwords do not match')
        return self
