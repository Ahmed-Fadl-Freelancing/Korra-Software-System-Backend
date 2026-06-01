"""
/tasks endpoint – stub returning an empty task list.

Replace the stub implementation with real DB queries once
the workflow tables are finalised.
"""
import logging

from rest_framework.response import Response
from rest_framework.views import APIView

logger = logging.getLogger(__name__)


class TaskListView(APIView):
    """GET /tasks – return tasks assigned to / created by the current user."""

    def get(self, request):
        # TODO: query workflow_tasks table once schema is confirmed
        return Response({"tasks": [], "detail": "stub – not yet implemented"})
