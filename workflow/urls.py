from django.urls import path

from .views import TaskListView

# Mounted at /tasks in core/urls.py
urlpatterns = [
    path("", TaskListView.as_view(), name="tasks"),
]
