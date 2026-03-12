"""
Celery tasks for the RPA / UiPath integration.

All tasks are currently stubbed – they log and will later update the DB
once the opportunities schema is finalised.
"""
import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(bind=True, name="rpa.pdf_extract")
def pdf_extract(self, opportunity_id: str):
    """
    Extract data from a PDF document for the given opportunity.

    Steps (stubbed):
      1. Fetch PDF from Supabase Storage
      2. Run extraction logic
      3. Update opportunity record in DB
    """
    logger.info(
        "pdf_extract task started for opportunity_id=%s (task_id=%s)",
        opportunity_id,
        self.request.id,
    )
    # TODO: implement extraction logic
    return {"status": "stubbed", "opportunity_id": opportunity_id}


@shared_task(bind=True, name="rpa.pricing_generate")
def pricing_generate(self, opportunity_id: str):
    """
    Generate a pricing offer PDF for the given opportunity.

    Steps (stubbed):
      1. Fetch opportunity data from DB
      2. Render pricing template
      3. Upload generated PDF to Supabase Storage
      4. Update opportunity record in DB
    """
    logger.info(
        "pricing_generate task started for opportunity_id=%s (task_id=%s)",
        opportunity_id,
        self.request.id,
    )
    # TODO: implement pricing generation logic
    return {"status": "stubbed", "opportunity_id": opportunity_id}


@shared_task(bind=True, name="rpa.uipath_trigger")
def uipath_trigger(self, opportunity_id: str):
    """
    Trigger a UiPath robot job for the given opportunity.

    Steps (stubbed):
      1. Build UiPath job payload
      2. Call UiPath Orchestrator API
      3. Store job reference in DB
    """
    logger.info(
        "uipath_trigger task started for opportunity_id=%s (task_id=%s)",
        opportunity_id,
        self.request.id,
    )
    # TODO: implement UiPath Orchestrator API call
    return {"status": "stubbed", "opportunity_id": opportunity_id}
