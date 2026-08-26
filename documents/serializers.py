from rest_framework import serializers

from .models import Document


class DocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Document
        fields = [
            "id",
            "project",
            "doc_type",
            "version",
            "bucket",
            "path",
            "filename",
            "content_type",
            "is_current",
            "notes",
            "sha256",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "version", "is_current", "created_at", "updated_at"]


class DocumentCreateSerializer(serializers.Serializer):
    """POST /documents/ — registers metadata for a file already PUT to a signed upload URL."""

    project_id = serializers.UUIDField()
    doc_type = serializers.ChoiceField(choices=Document.DocType.choices)
    bucket = serializers.CharField(max_length=255, required=False, default="documents")
    path = serializers.CharField()
    filename = serializers.CharField(max_length=255)
    content_type = serializers.CharField(max_length=100, required=False, default="application/pdf")
    notes = serializers.CharField(required=False, allow_blank=True)


class DocumentSetCurrentSerializer(serializers.Serializer):
    """PATCH /documents/{id}/ — only {"is_current": true} is supported (see DocumentDetailView)."""

    is_current = serializers.BooleanField()

    def validate_is_current(self, value):
        if not value:
            raise serializers.ValidationError(
                "Only is_current=true is supported — promotes this version to current; "
                "there's no way to un-set it directly."
            )
        return value
