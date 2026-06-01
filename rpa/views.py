"""
/webhooks/uipath  – receives callback results from UiPath Orchestrator.

Security: The endpoint validates an HMAC-SHA256 signature supplied in the
X-UiPath-Signature header.  The shared secret is read from the
UIPATH_WEBHOOK_SECRET environment variable (settings.UIPATH_WEBHOOK_SECRET).
Requests without a valid signature are rejected with HTTP 401.
"""
import hashlib
import hmac
import logging

from django.conf import settings
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

logger = logging.getLogger(__name__)


def _verify_uipath_signature(request) -> bool:
    """Return True if the request carries a valid HMAC-SHA256 signature.

    Expected header: X-UiPath-Signature: sha256=<hex_digest>

    If UIPATH_WEBHOOK_SECRET is not configured the check is skipped and the
    function returns True so that development environments without the secret
    still work. A warning is logged in that case.
    """
    secret = getattr(settings, "UIPATH_WEBHOOK_SECRET", "")
    if not secret:
        logger.warning(
            "UIPATH_WEBHOOK_SECRET is not set – skipping signature validation."
        )
        return True

    signature_header = request.META.get("HTTP_X_UIPATH_SIGNATURE", "")
    if not signature_header.startswith("sha256="):
        return False

    expected_hex = signature_header[len("sha256="):]
    body = request.body  # raw bytes
    computed = hmac.new(
        secret.encode(), body, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(computed, expected_hex)


class UiPathWebhookView(APIView):
    """POST /webhooks/uipath – receive UiPath job result callbacks."""

    # Webhook endpoints use HMAC-based auth, not JWT.
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        if not _verify_uipath_signature(request):
            logger.warning("UiPath webhook request failed signature validation.")
            return Response({"detail": "Invalid signature."}, status=401)

        payload = request.data
        logger.info("Received UiPath webhook payload: %s", payload)
        # TODO: update DB, trigger follow-up Celery tasks
        return Response({"received": True})
