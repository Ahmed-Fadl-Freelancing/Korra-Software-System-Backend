"""
Read-only models mapping to existing Supabase tables.

All models use managed=False so Django never creates/alters these tables.
The underlying tables live in the public schema of the Supabase Postgres DB.
"""
import uuid

from django.db import models


class Department(models.Model):
    """public.departments"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    name = models.CharField(max_length=255)

    class Meta:
        managed = False
        db_table = "departments"

    def __str__(self):
        return self.name


class UserProfile(models.Model):
    """public.user_profiles – keyed by auth.users.id (UUID from Supabase Auth)."""

    id = models.UUIDField(primary_key=True)  # = auth.users.id / JWT sub
    employee_code = models.CharField(max_length=50, blank=True)
    full_name = models.CharField(max_length=255, blank=True)
    department = models.ForeignKey(
        Department,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="department_id",
    )

    class Meta:
        managed = False
        db_table = "user_profiles"

    def __str__(self):
        return self.full_name or str(self.id)


class Role(models.Model):
    """public.roles"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    code = models.CharField(max_length=50)
    name = models.CharField(max_length=255, blank=True)

    class Meta:
        managed = False
        db_table = "roles"

    def __str__(self):
        return self.code


class UserRole(models.Model):
    """public.user_roles  (join table)"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(
        UserProfile,
        on_delete=models.CASCADE,
        db_column="user_id",
        related_name="user_roles",
    )
    role = models.ForeignKey(
        Role,
        on_delete=models.CASCADE,
        db_column="role_id",
        related_name="user_roles",
    )

    class Meta:
        managed = False
        db_table = "user_roles"
