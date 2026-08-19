"""Medication list management (dose tracking lives in routes/doses.py)."""
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from shared.models import Medication
from shared.schemas import MedicationIn, MedicationOut, MedicationPatchIn

router = APIRouter(prefix="/v1/medications", tags=["medications"])


@router.get("/", response_model=list[MedicationOut])
def list_medications(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[MedicationOut]:
    meds = session.scalars(
        select(Medication).where(Medication.household_id == uuid.UUID(user.household_id))
    ).all()
    return [MedicationOut.model_validate(m) for m in meds]


@router.post("/", response_model=MedicationOut, status_code=status.HTTP_201_CREATED)
def create_medication(
    body: MedicationIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> MedicationOut:
    med = Medication(
        id=uuid.uuid4(),
        household_id=uuid.UUID(user.household_id),
        name_he=body.name_he,
        dosage=body.dosage,
        schedule={"dosing_times": body.dosing_times},
        form=body.form,
        usage_instructions=body.usage_instructions,
        stock_count=body.stock_count,
        low_stock_threshold=body.low_stock_threshold,
    )
    session.add(med)
    session.commit()
    return MedicationOut.model_validate(med)


@router.patch("/{medication_id}", response_model=MedicationOut)
def patch_medication(
    medication_id: str,
    body: MedicationPatchIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> MedicationOut:
    med = session.scalar(
        select(Medication).where(
            Medication.id == medication_id,
            Medication.household_id == uuid.UUID(user.household_id),
        )
    )
    if not med:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Medication not found")

    for field in ("name_he", "dosage", "form", "usage_instructions",
                  "stock_count", "low_stock_threshold"):
        value = getattr(body, field)
        if value is not None:
            setattr(med, field, value)
    if body.dosing_times is not None:
        med.schedule = {"dosing_times": body.dosing_times}

    session.commit()
    return MedicationOut.model_validate(med)


@router.delete("/{medication_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_medication(
    medication_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> None:
    med = session.scalar(
        select(Medication).where(
            Medication.id == medication_id,
            Medication.household_id == uuid.UUID(user.household_id),
        )
    )
    if not med:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Medication not found")
    session.delete(med)
    session.commit()
