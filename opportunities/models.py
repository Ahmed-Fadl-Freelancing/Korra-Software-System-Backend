"""
Read-only-schema models mapping to existing Supabase tables (public.projects and its
lookup tables). managed=False everywhere — these tables already exist in Supabase,
Django never creates/alters them.
"""
import uuid

from django.db import models

from accounts.models import UserProfile


class Contractor(models.Model):
    """public.contractors"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    name = models.CharField(max_length=255, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "contractors"

    def __str__(self):
        return self.name


class Owner(models.Model):
    """public.owners"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    name = models.CharField(max_length=255, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "owners"

    def __str__(self):
        return self.name


class Consultant(models.Model):
    """public.consultants"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    name = models.CharField(max_length=255, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "consultants"

    def __str__(self):
        return self.name


class Product(models.Model):
    """public.products"""

    class Family(models.TextChoices):
        CHILLER = "Chiller"
        PUMP = "Pump"
        GENERATOR = "Generator"

    class CondenserMethod(models.TextChoices):
        AIR_COOLED = "AirCooled"
        WATER_COOLED = "WaterCooled"

    class CompressorType(models.TextChoices):
        CENTRIFUGAL = "Centrifugal"
        SCREW = "Screw"
        SCROLL = "Scroll"
        RECIPROCATING = "Reciprocating"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    family = models.CharField(max_length=20, choices=Family.choices)
    chiller_condenser = models.CharField(
        max_length=20, choices=CondenserMethod.choices, null=True, blank=True
    )
    chiller_compressor = models.CharField(
        max_length=20, choices=CompressorType.choices, null=True, blank=True
    )
    name = models.CharField(max_length=255, null=True, blank=True)
    model_code = models.CharField(max_length=255, unique=True)
    capacity_kw = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    capacity_tr = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    attributes = models.JSONField(default=dict, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "products"

    def __str__(self):
        return self.model_code


class Project(models.Model):
    """public.projects — the "Opportunity" entity shown in the UI."""

    class Application(models.TextChoices):
        INDUSTRIAL = "Industrial"
        COMMERCIAL = "Commercial"
        HEALTH = "Health"
        RESIDENTIAL = "Residential"

    class Scope(models.TextChoices):
        SUPPLY = "Supply"
        SUPPLY_INSTALLATION = "SupplyInstallation"
        MAINTENANCE = "Maintenance"
        RETROFIT = "Retrofit"
        OTHER = "Other"

    class Status(models.TextChoices):
        TENDERING_PHASE = "tenderingPhase"
        TECHNICAL_APPROVAL = "technicalApproval"
        FINAL_NEGOTIATION = "finalNegotiation"
        WON = "won"
        LOST = "lost"
        ON_HOLD = "onHold"
        WITH_DIFFERENT_CONTRACTOR = "withDifferentContractor"
        CANCELLED = "cancelled"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    name = models.CharField(max_length=255)
    contractor = models.ForeignKey(
        Contractor, null=True, blank=True, on_delete=models.SET_NULL, db_column="contractor_id"
    )
    consultant = models.ForeignKey(
        Consultant, null=True, blank=True, on_delete=models.SET_NULL, db_column="consultant_id"
    )
    owner = models.ForeignKey(
        Owner, null=True, blank=True, on_delete=models.SET_NULL, db_column="owner_id"
    )
    # sales_eng_id / tech_off_eng_id reference auth.users directly in Postgres; UserProfile's PK
    # is that same auth.users UUID (see accounts/models.py), so it's the right local FK target —
    # same convention accounts.UserRole already uses for its own auth.users-backed FKs.
    sales_engineer = models.ForeignKey(
        UserProfile,
        on_delete=models.PROTECT,
        db_column="sales_eng_id",
        related_name="sales_projects",
    )
    tech_engineer = models.ForeignKey(
        UserProfile,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="tech_off_eng_id",
        related_name="tech_projects",
    )
    # String references avoid a circular import with documents.models (which FKs back to Project).
    current_offer = models.ForeignKey(
        "documents.Document",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="current_offer_id",
        related_name="+",
    )
    current_submittal = models.ForeignKey(
        "documents.Document",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="current_submittal_id",
        related_name="+",
    )
    application = models.CharField(max_length=20, choices=Application.choices)
    scope = models.CharField(max_length=30, choices=Scope.choices)
    status = models.CharField(max_length=30, choices=Status.choices, default=Status.TENDERING_PHASE)
    product = models.ForeignKey(
        Product, null=True, blank=True, on_delete=models.SET_NULL, db_column="product_id"
    )
    extracted_data = models.JSONField(default=dict, blank=True)
    selection_data = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "projects"

    def __str__(self):
        return self.name
