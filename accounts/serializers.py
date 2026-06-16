"""Request serializers for the auth proxy endpoints."""
from rest_framework import serializers

JOB_TITLE_CHOICES = [
    "Junior Engineer",
    "Senior Engineer",
    "Lead Engineer",
    "Section Head",
    "Department Manager",
    "General Manager",
    "Director",
    "Board Member",
]


class SignupSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(min_length=8, write_only=True, trim_whitespace=False)
    full_name = serializers.CharField(max_length=255)
    job_title = serializers.ChoiceField(choices=JOB_TITLE_CHOICES)


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, trim_whitespace=False)


class RefreshSerializer(serializers.Serializer):
    refresh_token = serializers.CharField()
