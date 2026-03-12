from django.urls import path

from .views import MeView

# Mounted at /me in core/urls.py
urlpatterns = [
    path("", MeView.as_view(), name="me"),
]
