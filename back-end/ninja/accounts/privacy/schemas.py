from ninja import Schema


class PrivacySettingsIn(Schema):
    privacy_level: str


class PrivacySettingsOut(Schema):
    privacy_level: str
    is_first_login: bool
