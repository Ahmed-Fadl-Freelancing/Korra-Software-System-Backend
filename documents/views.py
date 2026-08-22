"""
Supabase Storage signed URL endpoints, plus document metadata persistence.

POST /documents/signed-upload-url
  Body: { bucket, path, content_type }
  Returns: { signed_url, token, path }

GET  /documents/signed-download-url?bucket=&path=&expires_in=<seconds>
  Returns: { signed_url }

POST /documents/
  Body: { project_id, doc_type, bucket, path, filename, content_type?, notes? }
  Returns: the created Document row.
  Called after a file has been PUT to a signed upload URL, to record that the file
  now physically exists at bucket/path and associate it with a project.

The service role key is used server-side only and never returned to the client.
"""
import logging

from django.conf import settings
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from supabase import StorageException, create_client

from opportunities.models import Project

from .models import Document
from .serializers import DocumentCreateSerializer, DocumentSerializer

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


class DocumentCreateView(APIView):
    """POST /documents/ — record metadata for a file already uploaded to Supabase Storage."""

    def post(self, request):
        serializer = DocumentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        project = get_object_or_404(Project, pk=data["project_id"])
        version = (
            Document.objects.filter(project=project, doc_type=data["doc_type"]).count() + 1
        )

        with transaction.atomic():
            Document.objects.filter(
                project=project, doc_type=data["doc_type"], is_current=True
            ).update(is_current=False)
            document = Document.objects.create(
                project=project,
                doc_type=data["doc_type"],
                version=version,
                bucket=data.get("bucket") or "documents",
                path=data["path"],
                filename=data["filename"],
                content_type=data.get("content_type") or "application/pdf",
                notes=data.get("notes", ""),
                created_by_id=request.user.user_id,
                is_current=True,
            )

        return Response(DocumentSerializer(document).data, status=201)
