from django.contrib.auth import authenticate, get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.db import IntegrityError, transaction
from django.utils import timezone
from ninja import Router

from .auth import mobile_bearer_auth
from .models import AccessToken, UserPrivacySettings
from .schemas import LoginIn, LoginOut, MessageOut, RegisterIn, UserOut
from .session_cache import cache_access_token, delete_cached_auth_context, user_payload

router = Router(tags=["auth"])


def _username_for_login(identifier: str) -> str:
    normalized = identifier.strip()
    UserModel = get_user_model()
    user = UserModel._default_manager.filter(email__iexact=normalized).first()
    if user is not None:
        return user.get_username()
    return normalized


def _issue_login_response(user, request, device_name: str) -> dict:
    raw_token, access_token = AccessToken.issue_for_user(
        user,
        request=request,
        device_name=device_name,
    )
    cache_access_token(raw_token, access_token)
    return {
        "user": user_payload(user),
        "access_token": raw_token,
        "token_type": "Bearer",
        "expires_at": access_token.expires_at,
    }


def _clean_email(email: str) -> str:
    normalized = email.strip().lower()
    validate_email(normalized)
    return normalized


@router.post(
    "/register",
    response={201: LoginOut, 400: MessageOut, 409: MessageOut},
    auth=None,
)
def register_user(request, payload: RegisterIn):
    UserModel = get_user_model()

    try:
        email = _clean_email(payload.email)
    except ValidationError:
        return 400, {"detail": "Email non valida"}

    if UserModel._default_manager.filter(email__iexact=email).exists():
        return 409, {"detail": "Email gia registrata"}

    try:
        validate_password(payload.password)
    except ValidationError as exc:
        return 400, {"detail": " ".join(exc.messages)}

    try:
        with transaction.atomic():
            user = UserModel._default_manager.create_user(
                username=email,
                email=email,
                password=payload.password,
                first_name=payload.first_name.strip(),
                last_name=payload.last_name.strip(),
            )
            UserPrivacySettings.objects.create(user=user)
    except IntegrityError:
        return 409, {"detail": "Email gia registrata"}

    return 201, _issue_login_response(user, request, payload.device_name)


@router.post(
    "/login",
    response={200: LoginOut, 401: MessageOut, 403: MessageOut},
    auth=None,
)
def login_user(request, payload: LoginIn):
    username = _username_for_login(payload.email)
    user = authenticate(request, username=username, password=payload.password)

    if user is None:
        return 401, {"detail": "Credenziali non valide"}
    if not user.is_active:
        return 403, {"detail": "Utente disabilitato"}

    return _issue_login_response(user, request, payload.device_name)


@router.post("/logout", response=MessageOut, auth=mobile_bearer_auth)
def logout_user(request):
    delete_cached_auth_context(request.auth.token_hash)
    AccessToken.objects.filter(id=request.auth.token_id).update(
        revoked_at=timezone.now()
    )
    return {"detail": "Logout effettuato"}


@router.get("/me", response=UserOut, auth=mobile_bearer_auth)
def current_user(request):
    return request.auth.user.as_payload()
