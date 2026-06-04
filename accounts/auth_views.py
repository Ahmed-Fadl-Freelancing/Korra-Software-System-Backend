"""
Auth proxy endpoints — Django forwards credentials to Supabase Auth (GoTrue)
and relays the Supabase-issued tokens. Django never mints its own JWT.

  POST /auth/signup   {email, password}              -> 201 {user, session?}
  POST /auth/login    {email, password}              -> 200 {access_token, ...}
  POST /auth/refresh  {refresh_token}                -> 200 {access_token, ...}
  POST /auth/logout   (Authorization: Bearer <jwt>)  -> 204
"""
import logging

from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from . import supabase_auth
from .serializers import LoginSerializer, RefreshSerializer, SignupSerializer

logger = logging.getLogger(__name__)


def _session_payload(data: dict) -> dict:
    """Normalize a GoTrue session response to a stable shape for the frontend."""
    return {
        "access_token": data.get("access_token"),
        "refresh_token": data.get("refresh_token"),
        "token_type": data.get("token_type", "bearer"),
        "expires_in": data.get("expires_in"),
        "expires_at": data.get("expires_at"),
        "user": data.get("user"),
    }


class SignupView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = SignupSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = supabase_auth.sign_up(
            serializer.validated_data["email"],
            serializer.validated_data["password"],
        )
        # When email confirmation is enabled, GoTrue returns the user without a
        # session (no access_token). Surface both cases plainly.
        if data.get("access_token"):
            body = _session_payload(data)
        else:
            body = {"user": data, "session": None}
        return Response(body, status=status.HTTP_201_CREATED)


class LoginView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = supabase_auth.sign_in(
            serializer.validated_data["email"],
            serializer.validated_data["password"],
        )
        return Response(_session_payload(data), status=status.HTTP_200_OK)


class RefreshView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = supabase_auth.refresh(serializer.validated_data["refresh_token"])
        return Response(_session_payload(data), status=status.HTTP_200_OK)


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        # request.auth is the raw bearer token set by SupabaseJWTAuthentication.
        token = request.auth
        if token:
            supabase_auth.sign_out(token)
        return Response(status=status.HTTP_204_NO_CONTENT)
