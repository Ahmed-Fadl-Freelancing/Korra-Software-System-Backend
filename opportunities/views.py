"""
/opportunities endpoint – stub.

Replace with real DB queries once the opportunities schema is confirmed.
"""
import logging

from rest_framework.response import Response
from rest_framework.views import APIView

logger = logging.getLogger(__name__)


class OpportunityListView(APIView):
    """GET /opportunities – list opportunities."""

    def get(self, request):
        # TODO: query opportunities table once schema is confirmed
        return Response(
            {"opportunities": [], "detail": "stub – not yet implemented"}
        )
