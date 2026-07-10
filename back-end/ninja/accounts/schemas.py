from ninja import Schema


class UserOut(Schema):
    id: int
    email: str
    first_name: str
    last_name: str
    is_staff: bool
    is_superuser: bool


class MessageOut(Schema):
    detail: str
