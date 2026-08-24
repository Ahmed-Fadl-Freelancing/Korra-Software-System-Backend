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

PATCH /documents/<uuid:pk>/
  Body: { is_current: true }
  Returns: the updated Document row.
  Promotes an existing (older) document version to current — see DocumentDetailView
  for the exact semantics (flips the flag on the existing row, doesn't create a new version).

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
from .serializers import DocumentCreateSerializer, DocumentSerializer, DocumentSetCurrentSerializer

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
    """POST /documents/ — record metadata for a file already uploaded to Supabase Storage.

    version and is_current are computed by the documents_set_version_and_current DB trigger
    (DB data/migrations/0001_fix_documents_before_insert_trigger.sql), not here — it owns that
    logic authoritatively (and atomically, inside the same INSERT, so two concurrent uploads for
    the same project+doc_type can't race to compute the same version number the way a separate
    count-then-insert from application code could). refresh_from_db() picks up what the trigger
    set, since Django's own INSERT has no visibility into a BEFORE trigger's changes to NEW.
    """

    def post(self, request):
        serializer = DocumentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        project = get_object_or_404(Project, pk=data["project_id"])

        document = Document.objects.create(
            project=project,
            doc_type=data["doc_type"],
            bucket=data.get("bucket") or "documents",
            path=data["path"],
            filename=data["filename"],
            content_type=data.get("content_type") or "application/pdf",
            notes=data.get("notes", ""),
            created_by_id=request.user.user_id,
        )
        document.refresh_from_db()

        return Response(DocumentSerializer(document).data, status=201)


class DocumentDetailView(APIView):
    """PATCH /documents/<uuid:pk>/ — promote an existing (older) document version to current.

    Only {"is_current": true} is supported — there's no un-set; "no version is current" isn't a
    meaningful state here. Promoting one version demotes whichever was current before it, as a
    side effect, same as a fresh upload would. This *flips the flag on the existing row* rather
    than creating a new version copy — "revert" semantics, not "restore as a new version" — a
    deliberate default since the product's intended behavior isn't documented anywhere; flag it if
    you'd rather promoting an old version bumped a new version number instead.

    Unlike DocumentCreateView, this can't rely on a BEFORE INSERT trigger (this is an UPDATE, and
    no equivalent AFTER UPDATE trigger exists for the current_offer_id/current_submittal_id sync),
    so it does that sync explicitly here.
    """

    def patch(self, request, pk):
        document = get_object_or_404(Document, pk=pk)
        serializer = DocumentSetCurrentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        with transaction.atomic():
            Document.objects.filter(
                project_id=document.project_id, doc_type=document.doc_type, is_current=True
            ).exclude(pk=document.pk).update(is_current=False)
            document.is_current = True
            document.save(update_fields=["is_current"])

            if document.doc_type == Document.DocType.OFFER:
                Project.objects.filter(pk=document.project_id).update(current_offer_id=document.pk)
            elif document.doc_type in (Document.DocType.SUBMITTAL, Document.DocType.RFQ):
                Project.objects.filter(pk=document.project_id).update(current_submittal_id=document.pk)

        return Response(DocumentSerializer(document).data)
