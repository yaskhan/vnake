class AuthMixin:
    is_authenticated: bool = False
    def login(self):
        pass

class LogMixin:
    log_level: int = 0
    def log(self, msg: str):
        pass

class SystemUser(AuthMixin, LogMixin):
    username: str
