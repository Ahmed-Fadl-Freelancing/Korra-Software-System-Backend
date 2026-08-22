"""
/opportunities endpoints — real Project (public.projects) reads and writes.

Path A (PDF-extraction-derived create, POST /opportunities) is deliberately not
implemented yet — real extraction is stubbed on the backend for now. Only Path B
(manual entry, POST /opportunities/manual) is wired up, so the create -> Supabase
write -> document-in-bucket flow can be exercised end-to-end without it.
"""
import logging

from django.shortcuts import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Consultant, Contractor, Owner, Product, Project
from .serializers import (
    ManualOpportunityCreateSerializer,
    ProjectPatchSerializer,
    ProjectSerializer,
)

logger = logging.getLogger(__name__)

_SELECT_RELATED = ("contractor", "consultant", "owner", "sales_engineer", "tech_engineer", "product")


def _resolve_me(request, value):
    return request.user.user_id if value == "me" else value


def _get_or_create_party(model, name):
    if not name:
        return None
    obj, _ = model.objects.get_or_create(name=name.strip())
    return obj


def _get_or_create_product(family, model_code):
    if not family or not model_code:
        return None
    obj, _ = Product.objects.get_or_create(
        model_code=model_code.strip(), defaults={"family": family}
    )
    return obj


class OpportunityListView(APIView):
    """GET /opportunities/ — list, optionally filtered by sales_eng_id / tech_eng_id (accepts "me")."""

    def get(self, request):
        qs = Project.objects.select_related(*_SELECT_RELATED).all()

        sales_eng_id = request.query_params.get("sales_eng_id")
        if sales_eng_id:
            qs = qs.filter(sales_engineer_id=_resolve_me(request, sales_eng_id))

        tech_eng_id = request.query_params.get("tech_eng_id")
        if tech_eng_id:
            qs = qs.filter(tech_engineer_id=_resolve_me(request, tech_eng_id))

        status_param = request.query_params.get("status")
        if status_param:
            qs = qs.filter(status=status_param)

        return Response(ProjectSerializer(qs, many=True).data)


class OpportunityManualCreateView(APIView):
    """POST /opportunities/manual — Path B: create from manually entered fields."""

    def post(self, request):
        serializer = ManualOpportunityCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        contractor = _get_or_create_party(Contractor, data.get("contractor_name"))
        owner = _get_or_create_party(Owner, data.get("owner_name"))
        consultant = _get_or_create_party(Consultant, data.get("consultant_name"))
        product = _get_or_create_product(data.get("product_family"), data.get("product_model_code"))

        project = Project.objects.create(
            name=data["name"],
            application=data["application"],
            scope=data["scope"],
            contractor=contractor,
            owner=owner,
            consultant=consultant,
            product=product,
            sales_engineer_id=request.user.user_id,
        )
        project = get_object_or_404(Project.objects.select_related(*_SELECT_RELATED), pk=project.pk)
        return Response(ProjectSerializer(project).data, status=201)


class OpportunityDetailView(APIView):
    """GET/PATCH /opportunities/<uuid:pk>/"""

    def get_object(self, pk):
        return get_object_or_404(Project.objects.select_related(*_SELECT_RELATED), pk=pk)

    def get(self, request, pk):
        return Response(ProjectSerializer(self.get_object(pk)).data)

    def patch(self, request, pk):
        project = self.get_object(pk)
        serializer = ProjectPatchSerializer(project, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        project = get_object_or_404(Project.objects.select_related(*_SELECT_RELATED), pk=pk)
        return Response(ProjectSerializer(project).data)
