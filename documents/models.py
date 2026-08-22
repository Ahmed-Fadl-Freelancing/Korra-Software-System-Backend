"""
Read-only-schema model mapping to the existing Supabase public.documents table.
managed=False — this table already exists in Supabase, Django never creates/alters it.
"""
import uuid

from django.db import models

from accounts.models import UserProfile


class Document(models.Model):
    """public.documents — metadata for a file physically stored in Supabase Storage."""

    class DocType(models.TextChoices):
        OFFER = "offer"
        SUBMITTAL = "submittal"
        RFQ = "rfq"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    # String reference avoids a circular import with opportunities.models (which FKs back here).
    project = models.ForeignKey(
        "opportunities.Project",
        on_delete=models.CASCADE,
        db_column="project_id",
        related_name="documents",
    )
    doc_type = models.CharField(max_length=20, choices=DocType.choices)
    version = models.PositiveIntegerField()
    bucket = models.CharField(max_length=255, default="documents")
    path = models.TextField()
    filename = models.CharField(max_length=255)
    content_type = models.CharField(max_length=100, default="application/pdf")
    created_by = models.ForeignKey(
        UserProfile,
        on_delete=models.PROTECT,
        db_column="created_by_user_id",
        related_name="uploaded_documents",
    )
    is_current = models.BooleanField(default=False)
    notes = models.TextField(null=True, blank=True)
    sha256 = models.CharField(max_length=64, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "documents"

    def __str__(self):
        return self.filename
