import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import verify_internal_api_key
from app.db.postgres import get_db
from app.models.clinic import Clinic
from app.schemas.clinic import ClinicCreate, ClinicOut

router = APIRouter(prefix="/api/clinics", tags=["clinics"], dependencies=[Depends(verify_internal_api_key)])


@router.post("", response_model=ClinicOut, status_code=201)
async def create_clinic(payload: ClinicCreate, db: AsyncSession = Depends(get_db)) -> Clinic:
    clinic = Clinic(
        name=payload.name,
        timezone=payload.timezone,
        address=payload.address,
        contact_email=payload.contact_email,
        contact_phone=payload.contact_phone,
        config=payload.config.model_dump(),
        ai_receptionist_enabled=payload.ai_receptionist_enabled,
    )
    db.add(clinic)
    await db.commit()
    await db.refresh(clinic)
    return clinic


@router.get("/{clinic_id}", response_model=ClinicOut)
async def get_clinic(clinic_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> Clinic:
    clinic = await db.get(Clinic, clinic_id)
    if clinic is None:
        raise HTTPException(status_code=404, detail="Clinic not found")
    return clinic
