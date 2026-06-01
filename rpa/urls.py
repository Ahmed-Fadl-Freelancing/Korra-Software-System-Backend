from django.urls import path

from .views import UiPathWebhookView

# Mounted at /webhooks/ in core/urls.py
urlpatterns = [
    path("uipath", UiPathWebhookView.as_view(), name="webhook-uipath"),
]
