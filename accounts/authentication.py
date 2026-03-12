"""
Supabase JWT authentication for Django REST Framework.

Validates the JWT issued by Supabase Auth:
  - Algorithm : HS256
  - Secret    : SUPABASE_JWT_SECRET (settings)
  - Claims    : exp (validated by PyJWT), sub (→ user_id UUID), email
  - Attaches  : request.user as an AuthenticatedUser (lightweight object)

No network call is made to Supabase – everything is verified locally.
"""
import logging

import jwt
from django.conf import settings
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed

logger = logging.getLogger(__name__)


class AuthenticatedUser:
    """Lightweight user object attached to request.user after JWT verification."""

    is_authenticated = True
    is_anonymous = False
    is_active = True

    def __init__(self, user_id: str, email: str = ""):
        self.user_id = user_id  # UUID string (JWT sub)
        self.pk = user_id
        self.id = user_id
        self.email = email
        # Profile data – populated lazily by get_profile() or /me view
        self._profile = None

    # ------------------------------------------------------------------
    # Django / DRF compatibility
    # ------------------------------------------------------------------
    @property
    def is_staff(self):
        return False

    def __str__(self):
        return self.email or self.user_id


class SupabaseJWTAuthentication(BaseAuthentication):
    """DRF authentication class that validates Supabase-issued JWTs."""

    def authenticate(self, request):
        auth_header = request.META.get("HTTP_AUTHORIZATION", "")
        if not auth_header.startswith("Bearer "):
            return None  # Let other authenticators / anonymous access proceed

        token = auth_header.split(" ", 1)[1].strip()
        if not token:
            return None

        secret = settings.SUPABASE_JWT_SECRET
        if not secret:
            logger.error("SUPABASE_JWT_SECRET is not configured")
            raise AuthenticationFailed("Server authentication configuration error.")

        try:
            payload = jwt.decode(
                token,
                secret,
                algorithms=["HS256"],
                options={"require": ["exp", "sub"]},
            )
        except jwt.ExpiredSignatureError:
            raise AuthenticationFailed("Token has expired.")
        except jwt.InvalidTokenError as exc:
            raise AuthenticationFailed(f"Invalid token: {exc}")

        user_id = payload.get("sub")
        if not user_id:
            raise AuthenticationFailed("Token missing sub claim.")

        email = payload.get("email", "")
        user = AuthenticatedUser(user_id=user_id, email=email)
        return (user, token)

    def authenticate_header(self, request):
        return "Bearer"
