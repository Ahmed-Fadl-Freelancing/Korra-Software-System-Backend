from django.urls import path

from .auth_views import LoginView, LogoutView, RefreshView, SignupView

# Mounted at /auth/ in core/urls.py
urlpatterns = [
    path("signup", SignupView.as_view(), name="auth-signup"),
    path("login", LoginView.as_view(), name="auth-login"),
    path("logout", LogoutView.as_view(), name="auth-logout"),
    path("refresh", RefreshView.as_view(), name="auth-refresh"),
]
