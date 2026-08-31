from datetime import datetime

from ninja import Schema

from ..schemas import UserOut


class LoginIn(Schema):
    email: str
    password: str


class RegisterIn(Schema):
    email: str
    password: str
    first_name: str = ""
    last_name: str = ""


class LoginOut(Schema):
    user: UserOut
    access_token: str
    token_type: str
    expires_at: datetime
