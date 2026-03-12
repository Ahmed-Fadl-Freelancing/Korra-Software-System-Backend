"""
Role-based permission helpers.

All helpers query the DB (user_roles + roles) using the JWT user_id.
Results are NOT cached per-request; add caching if needed in production.
"""
from rest_framework.permissions import BasePermission

from .models import UserRole


def _get_role_codes(user_id: str, request=None) -> list[str]:
    """Return list of role code strings for the given user_id.

    Caches the result on the request object for the lifetime of the request
    to avoid repeated DB hits when multiple permission classes are applied.
    """
    cache_attr = "_korra_role_codes"
    if request is not None:
        cached = getattr(request, cache_attr, None)
        if cached is not None:
            return cached

    rows = UserRole.objects.filter(user_id=user_id).select_related("role")
    codes = [ur.role.code for ur in rows]

    if request is not None:
        setattr(request, cache_attr, codes)

    return codes


class IsSales(BasePermission):
    def has_permission(self, request, view):
        return "sales" in _get_role_codes(request.user.user_id, request)


class IsEngineer(BasePermission):
    def has_permission(self, request, view):
        return "engineer" in _get_role_codes(request.user.user_id, request)


class IsManager(BasePermission):
    def has_permission(self, request, view):
        return "manager" in _get_role_codes(request.user.user_id, request)


class IsAdmin(BasePermission):
    def has_permission(self, request, view):
        return "admin" in _get_role_codes(request.user.user_id, request)
