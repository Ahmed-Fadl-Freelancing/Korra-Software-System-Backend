"""
Thin proxy to the Supabase Auth (GoTrue) REST API.

Django never mints its own JWTs. These helpers forward credentials to Supabase
Auth, and Supabase issues the access/refresh tokens. Subsequent requests are then
verified locally by ``SupabaseJWTAuthentication`` using ``SUPABASE_JWT_SECRET`` —
no network call per request.

Endpoints used (GoTrue):
  - POST {SUPABASE_URL}/auth/v1/signup
  - POST {SUPABASE_URL}/auth/v1/token?grant_type=password
  - POST {SUPABASE_URL}/auth/v1/token?grant_type=refresh_token
  - POST {SUPABASE_URL}/auth/v1/logout
"""
import logging

import httpx
from django.conf import settings
from rest_framework.exceptions import APIException

logger = logging.getLogger(__name__)

_TIMEOUT = httpx.Timeout(10.0)


class SupabaseAuthError(APIException):
    """Raised when Supabase Auth rejects or fails a request.

    Carries through a sanitized status code and message; the raw GoTrue body is
    logged but never returned to the client.
    """

    status_code = 502
    default_detail = "Authentication service error."
    default_code = "supabase_auth_error"

    def __init__(self, detail=None, status_code=None):
        if status_code is not None:
            self.status_code = status_code
        super().__init__(detail or self.default_detail)


def _base_url() -> str:
    url = (settings.SUPABASE_URL or "").rstrip("/")
    if not url:
        logger.error("SUPABASE_URL is not configured")
        raise SupabaseAuthError("Server authentication configuration error.", status_code=500)
    return url


def _headers() -> dict:
    apikey = settings.SUPABASE_ANON_KEY or settings.SUPABASE_SERVICE_ROLE_KEY
    if not apikey:
        logger.error("SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY is not configured")
        raise SupabaseAuthError("Server authentication configuration error.", status_code=500)
    return {"apikey": apikey, "Content-Type": "application/json"}


def _post(path: str, *, json: dict, extra_headers: dict | None = None) -> httpx.Response:
    headers = _headers()
    if extra_headers:
        headers.update(extra_headers)
    url = f"{_base_url()}/auth/v1/{path}"
    try:
        return httpx.post(url, json=json, headers=headers, timeout=_TIMEOUT)
    except httpx.HTTPError as exc:
        logger.error("Supabase Auth request to %s failed: %s", path, exc)
        raise SupabaseAuthError("Authentication service unavailable.", status_code=503)


def _error_message(resp: httpx.Response) -> str:
    """Extract a human-readable message from a GoTrue error body (best effort)."""
    try:
        body = resp.json()
    except ValueError:
        return "Authentication failed."
    if isinstance(body, dict):
        return (
            body.get("error_description")
            or body.get("msg")
            or body.get("message")
            or body.get("error")
            or "Authentication failed."
        )
    return "Authentication failed."


def _raise_for_status(resp: httpx.Response, *, default_status: int = 400) -> None:
    if resp.is_success:
        return
    logger.warning("Supabase Auth %s -> %s: %s", resp.request.url, resp.status_code, resp.text)
    # Map upstream auth rejections to client-friendly codes.
    status = resp.status_code if resp.status_code in (400, 401, 403, 422, 429) else default_status
    raise SupabaseAuthError(_error_message(resp), status_code=status)


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------
def sign_up(email: str, password: str, full_name: str = "", job_title: str = "") -> dict:
    """Register a new user. Returns the GoTrue JSON (user + session if auto-confirmed).

    full_name and job_title are stored in auth.users.raw_user_meta_data so the
    PostgreSQL trigger can copy them into public.user_profiles on INSERT.
    """
    resp = _post("signup", json={
        "email": email,
        "password": password,
        "data": {
            "full_name": full_name,
            "job_title": job_title,
        },
    })
    _raise_for_status(resp)
    return resp.json()


def sign_in(email: str, password: str) -> dict:
    """Password grant. Returns access_token, refresh_token, expires_in, user, ..."""
    resp = _post("token?grant_type=password", json={"email": email, "password": password})
    _raise_for_status(resp, default_status=401)
    return resp.json()


def refresh(refresh_token: str) -> dict:
    """Exchange a refresh token for a fresh session."""
    resp = _post("token?grant_type=refresh_token", json={"refresh_token": refresh_token})
    _raise_for_status(resp, default_status=401)
    return resp.json()


def sign_out(access_token: str) -> None:
    """Revoke the session associated with the given access token."""
    resp = _post("logout", json={}, extra_headers={"Authorization": f"Bearer {access_token}"})
    # GoTrue returns 204 on success. Treat 401 (already-invalid token) as success.
    if resp.is_success or resp.status_code == 401:
        return
    _raise_for_status(resp)
