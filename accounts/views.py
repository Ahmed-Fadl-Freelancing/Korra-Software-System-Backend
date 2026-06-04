"""
/me endpoint – returns profile + department + roles for the authenticated user.
"""
import logging

from django.db import connection
from rest_framework.response import Response
from rest_framework.views import APIView

logger = logging.getLogger(__name__)


class MeView(APIView):
    """GET /me – returns user profile data joined from DB tables."""

    def get(self, request):
        user_id = request.user.user_id

        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    up.user_id         AS user_id,
                    up.employee_code,
                    up.full_name,
                    d.id               AS dept_id,
                    d.name             AS dept_name
                FROM public.user_profiles up
                LEFT JOIN public.departments d ON d.id = up.department_id
                WHERE up.user_id = %s
                """,
                [str(user_id)],
            )
            row = cursor.fetchone()

        if row is None:
            return Response(
                {"detail": "Profile not found."},
                status=404,
            )

        user_id_db, employee_code, full_name, dept_id, dept_name = row

        # Fetch roles
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT r.code
                FROM public.user_roles ur
                JOIN public.roles r ON r.id = ur.role_id
                WHERE ur.user_id = %s
                """,
                [str(user_id)],
            )
            role_rows = cursor.fetchall()

        roles = [r[0] for r in role_rows]

        return Response(
            {
                "user_id": str(user_id_db),
                "employee_code": employee_code,
                "full_name": full_name,
                "department": (
                    {"id": str(dept_id), "name": dept_name}
                    if dept_id
                    else None
                ),
                "roles": roles,
            }
        )
