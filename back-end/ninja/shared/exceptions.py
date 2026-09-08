from __future__ import annotations

class ServiceError(Exception):
    status_code: int = 400
    def __init__(self, message: str):
        super().__init__(message)
        self.message = message
