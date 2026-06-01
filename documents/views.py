"""
Supabase Storage signed URL endpoints.

POST /documents/signed-upload-url
  Body: { bucket, path, content_type }
  Returns: { signed_url, token, path }

GET  /documents/signed-download-url?bucket=&path=&expires_in=<seconds>
  Returns: { signed_url }

The service role key is used server-side only and never returned to the client.
"""
import logging

from django.conf import settings
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from supabase import StorageException, create_client

logger = logging.getLogger(__name__)

_EXPIRES_IN_MIN = 60       # 1 minute
_EXPIRES_IN_MAX = 604_800  # 7 days


def _get_supabase_client():
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)


def _parse_expires_in(raw, default=3600):
    """Parse and validate the expires_in value (seconds)."""
    try:
        value = int(raw) if raw is not None else default
    except (TypeError, ValueError):
        raise ValidationError(
            {"expires_in": "Must be an integer number of seconds."}
        )
    if not (_EXPIRES_IN_MIN <= value <= _EXPIRES_IN_MAX):
        raise ValidationError(
            {
                "expires_in": (
                    f"Must be between {_EXPIRES_IN_MIN} and {_EXPIRES_IN_MAX} seconds."
                )
            }
        )
    return value


class SignedUploadUrlView(APIView):
    """POST /documents/signed-upload-url"""

    def post(self, request):
        bucket = request.data.get("bucket")
        path = request.data.get("path")

        if not bucket or not path:
            return Response(
                {"detail": "bucket and path are required."},
                status=400,
            )

        try:
            client = _get_supabase_client()
            result = client.storage.from_(bucket).create_signed_upload_url(path)
            return Response(result)
        except StorageException as exc:
            logger.error("Supabase StorageException (upload): %s", exc)
            return Response(
                {"detail": "Could not create signed upload URL.", "error": str(exc)},
                status=502,
            )
        except Exception as exc:
            logger.exception("Unexpected error creating signed upload URL: %s", exc)
            return Response(
                {"detail": "Could not create signed upload URL."},
                status=502,
            )


class SignedDownloadUrlView(APIView):
    """GET /documents/signed-download-url?bucket=&path="""

    def get(self, request):
        bucket = request.query_params.get("bucket")
        path = request.query_params.get("path")
        expires_in = _parse_expires_in(request.query_params.get("expires_in"))

        if not bucket or not path:
            return Response(
                {"detail": "bucket and path query params are required."},
                status=400,
            )

        try:
            client = _get_supabase_client()
            result = client.storage.from_(bucket).create_signed_url(path, expires_in)
            return Response(result)
        except StorageException as exc:
            logger.error("Supabase StorageException (download): %s", exc)
            return Response(
                {"detail": "Could not create signed download URL.", "error": str(exc)},
                status=502,
            )
        except Exception as exc:
            logger.exception("Unexpected error creating signed download URL: %s", exc)
            return Response(
                {"detail": "Could not create signed download URL."},
                status=502,
            )
