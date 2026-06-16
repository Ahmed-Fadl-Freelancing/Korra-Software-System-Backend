from django.contrib import admin
from django.urls import include, path
from django.http import JsonResponse


def health(request):
    return JsonResponse({"status": "ok"})


urlpatterns = [
    path("health", health, name="health"),
    path("auth/", include("accounts.auth_urls")),
    path("me", include("accounts.urls")),
    path("tasks", include("workflow.urls")),
    path("opportunities", include("opportunities.urls")),
    path("documents/", include("documents.urls")),
    path("webhooks/", include("rpa.urls")),
    path("pdf-extraction/", include("pdf_extraction.urls")),
]
