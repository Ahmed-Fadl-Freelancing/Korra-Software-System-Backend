"""
Middleware that attaches a unique request ID to every request and response.

The ID is read from the X-Request-ID header when provided by the client,
otherwise a new UUID4 is generated.  The ID is available as
``request.request_id`` and is echoed back in the X-Request-ID response header.
"""
import logging
import uuid

logger = logging.getLogger(__name__)


class RequestIdMiddleware:
    """Attach a unique request ID to every request."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request_id = request.META.get("HTTP_X_REQUEST_ID") or str(uuid.uuid4())
        request.request_id = request_id

        logger.info(
            "Incoming %s %s",
            request.method,
            request.get_full_path(),
            extra={"request_id": request_id},
        )

        response = self.get_response(request)
        response["X-Request-ID"] = request_id
        return response
