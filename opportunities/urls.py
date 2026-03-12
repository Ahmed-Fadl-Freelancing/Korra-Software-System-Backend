from django.urls import path

from .views import OpportunityListView

# Mounted at /opportunities in core/urls.py
urlpatterns = [
    path("", OpportunityListView.as_view(), name="opportunities"),
]
