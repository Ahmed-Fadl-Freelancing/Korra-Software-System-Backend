"""
pdf_extraction/tasks.py

Celery task that orchestrates the PDF extraction pipeline.

The task is intentionally thin: it delegates all real work to
``pdf_extraction.services`` so that the extraction logic can be tested
independently of Celery.

Task name : ``pdf_extraction.extract``
Triggered by: the ``documents`` app (or any other app) after a PDF has been
              uploaded to Supabase Storage.

Retry policy
------------
The task retries up to 3 times with a 60-second back-off before giving up and
marking the job as failed.
"""
import logging

from celery import shared_task

from .models import PdfExtractionJob
from .services import PdfExtractionError, fetch_pdf, parse_pdf, persist_result

logger = logging.getLogger(__name__)

# Maximum number of automatic retries before the task is marked failed.
_MAX_RETRIES = 3
# Seconds to wait before each retry.
_RETRY_COUNTDOWN = 60


@shared_task(bind=True, name="pdf_extraction.extract", max_retries=_MAX_RETRIES)
def extract_pdf(self, job_id: int):
    """
    Run the full PDF extraction pipeline for a single ``PdfExtractionJob``.

    Parameters
    ----------
    job_id : Primary key of the ``PdfExtractionJob`` record that holds
             the bucket / path of the PDF to process.

    Returns
    -------
    dict : ``{"status": "done", "job_id": <job_id>}`` on success.

    The task updates ``PdfExtractionJob.status`` throughout:
      - ``running``  when it starts
      - ``done``     on success (via ``persist_result``)
      - ``failed``   if all retries are exhausted
    """
    logger.info(
        "pdf_extraction.extract started: job_id=%s (celery_task_id=%s)",
        job_id,
        self.request.id,
    )

    # --- 1. Load job record ---------------------------------------------------
    try:
        job = PdfExtractionJob.objects.get(pk=job_id)
    except PdfExtractionJob.DoesNotExist:
        logger.error("PdfExtractionJob %s not found – aborting.", job_id)
        # Do not retry: the record simply doesn't exist.
        return {"status": "aborted", "reason": "job_not_found", "job_id": job_id}

    job.status = PdfExtractionJob.Status.RUNNING
    job.save(update_fields=["status", "updated_at"])

    # --- 2. Run pipeline ------------------------------------------------------
    try:
        pdf_bytes = fetch_pdf(job.bucket, job.storage_path)
        extracted = parse_pdf(pdf_bytes)
        persist_result(job_id, extracted)
    except PdfExtractionError as exc:
        logger.warning(
            "pdf_extraction.extract failed (attempt %s/%s): job_id=%s error=%s",
            self.request.retries + 1,
            _MAX_RETRIES,
            job_id,
            exc,
        )
        if self.request.retries < _MAX_RETRIES:
            raise self.retry(exc=exc, countdown=_RETRY_COUNTDOWN)

        # All retries exhausted – mark the job as failed.
        job.status = PdfExtractionJob.Status.FAILED
        job.error = str(exc)
        job.save(update_fields=["status", "error", "updated_at"])
        return {"status": "failed", "job_id": job_id, "error": str(exc)}

    logger.info("pdf_extraction.extract completed: job_id=%s", job_id)
    return {"status": "done", "job_id": job_id}
