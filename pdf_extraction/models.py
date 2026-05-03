"""
pdf_extraction/models.py

Models that track extraction jobs and their results.
The schema is pending confirmation; all models are currently unmanaged stubs
that mirror the expected Supabase tables.
"""
from django.db import models


class PdfExtractionJob(models.Model):
    """
    Tracks the lifecycle of a single PDF extraction run.

    Fields
    ------
    opportunity_id : UUID of the related opportunity (FK to Supabase table).
    bucket         : Supabase Storage bucket that holds the source PDF.
    storage_path   : Full object path inside the bucket.
    status         : Current state of the job (pending → running → done/failed).
    result         : JSON blob returned by the extraction service (null until done).
    error          : Human-readable error message if the job failed.
    created_at     : When the job was enqueued.
    updated_at     : Last status change.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        RUNNING = "running", "Running"
        DONE = "done", "Done"
        FAILED = "failed", "Failed"

    opportunity_id = models.UUIDField(db_index=True)
    bucket = models.CharField(max_length=255)
    storage_path = models.TextField()
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
    )
    result = models.JSONField(null=True, blank=True)
    error = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"PdfExtractionJob({self.opportunity_id}, {self.status})"
