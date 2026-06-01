from django.urls import path

from .views import PdfExtractionJobCreateView, PdfExtractionJobDetailView

# Mounted at /pdf-extraction/ in core/urls.py
urlpatterns = [
    path("jobs/", PdfExtractionJobCreateView.as_view(), name="pdf-extraction-create"),
    path("jobs/<int:job_id>/", PdfExtractionJobDetailView.as_view(), name="pdf-extraction-detail"),
]
