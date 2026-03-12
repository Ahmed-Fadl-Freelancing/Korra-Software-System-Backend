from django.urls import path

from .views import SignedDownloadUrlView, SignedUploadUrlView

# Mounted at /documents/ in core/urls.py
urlpatterns = [
    path("signed-upload-url", SignedUploadUrlView.as_view(), name="signed-upload-url"),
    path(
        "signed-download-url",
        SignedDownloadUrlView.as_view(),
        name="signed-download-url",
    ),
]
