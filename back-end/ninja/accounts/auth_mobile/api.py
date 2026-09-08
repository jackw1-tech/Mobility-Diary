from ninja import Router
from ninja.responses import Status

from ..schemas import MessageOut, UserOut
from . import services
from .auth import mobile_bearer_auth
from .schemas import LoginIn, LoginOut, RegisterIn

router = Router(tags=["auth"])


"""
Rotta di registrazione di un nuovo Utente
"""
@router.post(
    "/register",
    response={201: LoginOut, 400: MessageOut, 409: MessageOut},
    auth=None,
)
def register_user(request, payload: RegisterIn):
    try:
        result = services.register_user(
            email=payload.email,
            password=payload.password,
            first_name=payload.first_name,
            last_name=payload.last_name,
        )
    except services.AuthMobileServiceError as exc:
        return Status(exc.status_code, {"detail": exc.message})
    return Status(201, result)

"""
Rotta di login di un Utente, se trovato, va a creare un token di accesso che verrà insviato all utente
"""
@router.post(
    "/login",
    response={200: LoginOut, 401: MessageOut, 403: MessageOut},
    auth=None,
)
def login_user(request, payload: LoginIn):
    try:
        return services.login_user(
            request,
            email=payload.email,
            password=payload.password,
        )
    except services.AuthMobileServiceError as exc:
        return Status(exc.status_code, {"detail": exc.message})


"""
Rotta di login di logout, cancella il token di accesso in redis e lo segna come revocato nel db
"""
@router.post("/logout", response=MessageOut, auth=mobile_bearer_auth)
def logout_user(request):
    services.logout_user(request.user.token_hash)
    return {"detail": "Logout effettuato"}

@router.get("/me", response=UserOut, auth=mobile_bearer_auth)
def current_user(request):
    return request.user.as_payload()
