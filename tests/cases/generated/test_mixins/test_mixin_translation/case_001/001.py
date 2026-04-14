class AuthMixin:
    is_authenticated: bool = False
    def login(self):
        self.is_authenticated = True

class User(AuthMixin):
    username: str

    def __init__(self, username: str):
        self.username = username
