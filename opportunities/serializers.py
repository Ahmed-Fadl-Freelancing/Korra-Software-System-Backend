from rest_framework import serializers

from .models import Project, Product


class PartySerializer(serializers.Serializer):
    """Shape for contractor / consultant / owner — matches frontend's ProjectParty type."""

    id = serializers.UUIDField()
    name = serializers.CharField()


class ProjectUserSerializer(serializers.Serializer):
    """Shape for sales_engineer / tech_engineer — matches frontend's ProjectUser type."""

    user_id = serializers.UUIDField(source="id")
    full_name = serializers.CharField()


class ProductSummarySerializer(serializers.Serializer):
    """Matches the inline product shape in frontend's Project type."""

    id = serializers.UUIDField()
    family = serializers.CharField()
    model_code = serializers.CharField()


class ProjectSerializer(serializers.ModelSerializer):
    contractor = PartySerializer(read_only=True, allow_null=True)
    consultant = PartySerializer(read_only=True, allow_null=True)
    owner = PartySerializer(read_only=True, allow_null=True)
    sales_engineer = ProjectUserSerializer(read_only=True)
    tech_engineer = ProjectUserSerializer(read_only=True, allow_null=True)
    product = ProductSummarySerializer(read_only=True, allow_null=True)

    class Meta:
        model = Project
        fields = [
            "id",
            "name",
            "contractor",
            "consultant",
            "owner",
            "sales_engineer",
            "tech_engineer",
            "application",
            "scope",
            "status",
            "product",
            "extracted_data",
            "created_at",
            "updated_at",
        ]


class ManualOpportunityCreateSerializer(serializers.Serializer):
    """POST /opportunities/manual — Path B (manual entry, no PDF extraction).

    Contractor/owner/consultant are accepted as plain names rather than lookup-table
    ids: there's no UI yet to browse/select existing rows, so we get-or-create by name.
    This is a deliberate simplification to exercise the real create -> Supabase write
    path end-to-end; a real picker (and de-duping UI) is a follow-up, not this task.
    """

    name = serializers.CharField(max_length=255)
    application = serializers.ChoiceField(choices=Project.Application.choices)
    scope = serializers.ChoiceField(choices=Project.Scope.choices)
    contractor_name = serializers.CharField(max_length=255, required=False, allow_blank=True)
    owner_name = serializers.CharField(max_length=255, required=False, allow_blank=True)
    consultant_name = serializers.CharField(max_length=255, required=False, allow_blank=True)
    product_family = serializers.ChoiceField(choices=Product.Family.choices, required=False)
    product_model_code = serializers.CharField(max_length=255, required=False, allow_blank=True)

    def validate(self, attrs):
        has_family = bool(attrs.get("product_family"))
        has_code = bool(attrs.get("product_model_code"))
        if has_family != has_code:
            raise serializers.ValidationError(
                "product_family and product_model_code must be provided together."
            )
        return attrs


class ProjectPatchSerializer(serializers.ModelSerializer):
    """PATCH /opportunities/{id}/ — status transitions only, for now."""

    class Meta:
        model = Project
        fields = ["status"]
