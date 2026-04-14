class IdleTaskRec:
            count: int = 10000
            _private: int = 0

            def decrement(self):
                self.count -= 1
                self._private += 1
