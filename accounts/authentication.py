"""
Supabase JWT authentication for Django REST Framework.

Validates the JWT issued by Supabase Auth:
  - Algorithm : ES256 (asymmetric — Supabase's current default for new projects)
  - Key       : SUPABASE_JWT_PUBLIC_KEY (settings) — a public key, safe to hold in Django;
                Django never needs (or has) the private key Supabase signs with. Accepts either
                a PEM string or the JWK JSON Supabase's dashboard shows under Settings → API →
                JWT Settings → "Key Details" (a single JWK object, or a whole `{"keys": [...]}`
                JWKS — the first key is used either way). Paste whichever one Supabase gives you;
                no manual conversion needed.
  - Claims    : exp (validated by PyJWT), sub (→ user_id UUID), email, aud (must be "authenticated")
  - Attaches  : request.user as an AuthenticatedUser (lightweight object)

No network call is made to Supabase – everything is verified locally, using the public key alone.

Was HS256 + SUPABASE_JWT_SECRET (a shared secret) until this was found live: every real Supabase-
issued token for this project is actually signed ES256, so the HS256 path rejected every real
request outright (`InvalidAlgorithmError`) — confirmed by decoding a live token's header
(`{"alg":"ES256",...}`) and by testing HS256 verification against it, which failed exactly as
expected. Switching to ES256 + the public key was then verified two ways against that same real
token: signature accepted when valid, `InvalidSignatureError` correctly raised when the token was
tampered with. SUPABASE_JWT_SECRET is no longer used here — it may still be Supabase's legacy
shared secret for other purposes, but it isn't what signs session JWTs for this project.
"""
import json
import logging
from functools import lru_cache

import jwt
from django.conf import settings
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _load_public_key(raw: str):
    """Parse SUPABASE_JWT_PUBLIC_KEY as either a JWK (Supabase dashboard's native format,
    JSON starting with '{') or a PEM string (legacy/manual format). Cached — the value comes
    from settings and doesn't change at runtime, and parsing a JWK builds an EC key object
    that's wasteful to redo on every request."""
    raw = raw.strip()
    if raw.startswith("{"):
        jwk_dict = json.loads(raw)
        if "keys" in jwk_dict:
            jwk_dict = jwk_dict["keys"][0]
        return jwt.PyJWK(jwk_dict).key
    return raw


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

        raw_key = settings.SUPABASE_JWT_PUBLIC_KEY
        if not raw_key:
            logger.error("SUPABASE_JWT_PUBLIC_KEY is not configured")
            raise AuthenticationFailed("Server authentication configuration error.")

        try:
            public_key = _load_public_key(raw_key)
        except (ValueError, KeyError, json.JSONDecodeError) as exc:
            logger.error("SUPABASE_JWT_PUBLIC_KEY is malformed: %s", exc)
            raise AuthenticationFailed("Server authentication configuration error.")

        try:
            payload = jwt.decode(
                token,
                public_key,
                algorithms=["ES256"],
                audience="authenticated",
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
