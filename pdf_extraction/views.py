"""
pdf_extraction/views.py

REST API endpoints for managing PDF extraction jobs.

Endpoints
---------
POST   /pdf-extraction/jobs/         – enqueue a new extraction job.
GET    /pdf-extraction/jobs/<id>/    – poll the status of an existing job.
"""
import logging

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import PdfExtractionJob
from .tasks import extract_pdf

logger = logging.getLogger(__name__)


class PdfExtractionJobCreateView(APIView):
    """
    POST /pdf-extraction/jobs/

    Enqueue a PDF extraction job for an uploaded document.

    Request body (JSON)
    -------------------
    opportunity_id : str  – UUID of the related opportunity.
    bucket         : str  – Supabase Storage bucket containing the PDF.
    path           : str  – Full object path inside the bucket.

    Returns
    -------
    201 : ``{"job_id": <int>, "status": "pending"}``
    400 : Validation error.
    """

    def post(self, request):
        opportunity_id = request.data.get("opportunity_id", "").strip()
        bucket = request.data.get("bucket", "").strip()
        path = request.data.get("path", "").strip()

        if not opportunity_id or not bucket or not path:
            return Response(
                {"detail": "opportunity_id, bucket, and path are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        job = PdfExtractionJob.objects.create(
            opportunity_id=opportunity_id,
            bucket=bucket,
            storage_path=path,
        )

        # Enqueue the Celery task asynchronously.
        extract_pdf.delay(job.pk)

        logger.info(
            "Enqueued pdf_extraction.extract: job_id=%s opportunity_id=%s",
            job.pk,
            opportunity_id,
        )
        return Response(
            {"job_id": job.pk, "status": job.status},
            status=status.HTTP_201_CREATED,
        )


class PdfExtractionJobDetailView(APIView):
    """
    GET /pdf-extraction/jobs/<id>/

    Poll the current status and result of an extraction job.

    The ``error`` field in the response is a boolean indicating whether the
    job failed; the raw error message is kept internally in the DB only and
    is never exposed to API clients.

    Returns
    -------
    200 : ``{"job_id": <int>, "status": "...", "result": {...}, "failed": bool}``
    404 : Job not found.
    """

    def get(self, request, job_id: int):
        try:
            job = PdfExtractionJob.objects.get(pk=job_id)
        except PdfExtractionJob.DoesNotExist:
            return Response(
                {"detail": "Job not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        return Response(
            {
                "job_id": job.pk,
                "opportunity_id": str(job.opportunity_id),
                "status": job.status,
                "result": job.result,
                # Expose only whether the job failed, not the raw exception
                # string, to avoid leaking internal details to API clients.
                "failed": job.status == PdfExtractionJob.Status.FAILED,
                "created_at": job.created_at.isoformat(),
                "updated_at": job.updated_at.isoformat(),
            }
        )
