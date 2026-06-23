from datetime import datetime

from ninja import Schema


class LoginIn(Schema):
    email: str
    password: str
    device_name: str = ""


class RegisterIn(Schema):
    email: str
    password: str
    first_name: str = ""
    last_name: str = ""
    device_name: str = ""


class UserOut(Schema):
    id: int
    email: str
    first_name: str
    last_name: str
    is_staff: bool
    is_superuser: bool


class LoginOut(Schema):
    user: UserOut
    access_token: str
    token_type: str
    expires_at: datetime


class MessageOut(Schema):
    detail: str


class PrivacySettingsIn(Schema):
    privacy_level: str


class PrivacySettingsOut(Schema):
    privacy_level: str
    is_first_login: bool
