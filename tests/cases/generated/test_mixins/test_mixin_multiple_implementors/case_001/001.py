class BaseMixin:
    base_id = 42
    def get_id(self):
        return self.base_id

class ServiceA(BaseMixin):
    pass

class ServiceB(BaseMixin):
    pass
