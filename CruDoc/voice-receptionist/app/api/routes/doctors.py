import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import verify_internal_api_key
from app.db.postgres import get_db
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.schemas.doctor import DoctorCreate, DoctorOut

router = APIRouter(
    prefix="/api/clinics/{clinic_id}/doctors", tags=["doctors"], dependencies=[Depends(verify_internal_api_key)]
)


@router.post("", response_model=DoctorOut, status_code=201)
async def add_doctor(clinic_id: uuid.UUID, payload: DoctorCreate, db: AsyncSession = Depends(get_db)) -> Doctor:
    clinic = await db.get(Clinic, clinic_id)
    if clinic is None:
        raise HTTPException(status_code=404, detail="Clinic not found")

    doctor = Doctor(clinic_id=clinic_id, **payload.model_dump())
    db.add(doctor)
    await db.commit()
    await db.refresh(doctor)
    return doctor


@router.get("", response_model=list[DoctorOut])
async def list_doctors(clinic_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> list[Doctor]:
    from sqlalchemy import select

    rows = (await db.execute(select(Doctor).where(Doctor.clinic_id == clinic_id))).scalars().all()
    return list(rows)
