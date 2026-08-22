from django.urls import path

from .views import OpportunityDetailView, OpportunityListView, OpportunityManualCreateView

# Mounted at /opportunities/ in core/urls.py
urlpatterns = [
    path("", OpportunityListView.as_view(), name="opportunities"),
    path("manual", OpportunityManualCreateView.as_view(), name="opportunities-manual"),
    path("<uuid:pk>/", OpportunityDetailView.as_view(), name="opportunities-detail"),
]
