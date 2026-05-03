"""
pdf_extraction/services.py

Business logic for extracting structured data from PDF documents.

This module is the single entry-point for all extraction work so that the
Celery task (tasks.py) stays thin.  Replace the stubs with real
implementations as the schema is confirmed.

Extraction pipeline
-------------------
1. ``fetch_pdf``          – download the raw PDF bytes from Supabase Storage.
2. ``parse_pdf``          – run the extraction algorithm and return a dict of
                           structured fields.
3. ``persist_result``     – write the extracted fields back to the DB
                           (``PdfExtractionJob.result``) and mark the job done.

Each function raises ``PdfExtractionError`` on failure so the Celery task can
catch it uniformly and mark the job as failed.
"""
import logging

logger = logging.getLogger(__name__)


class PdfExtractionError(Exception):
    """Raised when any step of the PDF extraction pipeline fails."""


def fetch_pdf(bucket: str, storage_path: str) -> bytes:
    """
    Download the PDF from Supabase Storage and return raw bytes.

    Parameters
    ----------
    bucket       : Supabase Storage bucket name.
    storage_path : Full object path inside the bucket.

    Returns
    -------
    bytes : Raw PDF content.

    Raises
    ------
    PdfExtractionError : If the download fails for any reason.
    """
    logger.info("fetch_pdf: bucket=%s path=%s", bucket, storage_path)
    # TODO: use supabase-py storage client to download the file
    #   from django.conf import settings
    #   from supabase import create_client
    #   client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)
    #   response = client.storage.from_(bucket).download(storage_path)
    #   return response
    raise PdfExtractionError("fetch_pdf not yet implemented")


def parse_pdf(pdf_bytes: bytes) -> dict:
    """
    Extract structured fields from raw PDF bytes.

    The exact fields depend on the document type (e.g. RFQ, BOM).  The
    returned dict will be stored verbatim in ``PdfExtractionJob.result``.

    Parameters
    ----------
    pdf_bytes : Raw PDF content returned by ``fetch_pdf``.

    Returns
    -------
    dict : Extracted fields, e.g. ``{"items": [...], "total": ...}``.

    Raises
    ------
    PdfExtractionError : If parsing fails (corrupt PDF, unsupported layout…).
    """
    logger.info("parse_pdf: received %d bytes", len(pdf_bytes))
    # TODO: integrate a PDF parsing library (e.g. pdfplumber, pypdf2, or an
    #       AI-based extraction service) and return structured data.
    raise PdfExtractionError("parse_pdf not yet implemented")


def persist_result(job_id: int, result: dict) -> None:
    """
    Save extraction results to the database and mark the job as done.

    Parameters
    ----------
    job_id : Primary key of the ``PdfExtractionJob`` record to update.
    result : Dict returned by ``parse_pdf``.

    Raises
    ------
    PdfExtractionError : If the DB update fails.
    """
    from .models import PdfExtractionJob  # local import to avoid circular deps

    logger.info("persist_result: job_id=%s", job_id)
    try:
        job = PdfExtractionJob.objects.get(pk=job_id)
        job.result = result
        job.status = PdfExtractionJob.Status.DONE
        job.save(update_fields=["result", "status", "updated_at"])
    except PdfExtractionJob.DoesNotExist as exc:
        raise PdfExtractionError(f"PdfExtractionJob {job_id} not found") from exc
    except Exception as exc:
        raise PdfExtractionError(f"Failed to persist result: {exc}") from exc
