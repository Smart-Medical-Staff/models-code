"""
shoulder_repo.py — Frozen Shoulder Assessment Data Access Layer
Follows BaseRepository pattern for clean architecture.
"""
import uuid
import logging
from typing import Dict, Any, List
from core.repositories.base_repository import BaseRepository

logger = logging.getLogger(__name__)


class FrozenShoulderRepository(BaseRepository):
    """Manages frozen shoulder assessment data in Supabase."""

    @staticmethod
    def save_assessment(
        patient_id: str,
        hba1c: float,
        age: int,
        crp: float,
        flex: float,
        abd: float,
        ext_rot: float,
        int_rot: float,
        pain: int,
        weeks: int,
        thyroid: bool,
        night_pain: bool,
        bilateral: bool,
        risk_score: float,
        predicted_class: int,
        predicted_probability: float,
        severity: str,
    ) -> Dict[str, Any]:
        """Save frozen shoulder assessment to database."""
        client = FrozenShoulderRepository._client()
        if not client:
            return {}
        try:
            payload = {
                "id": str(uuid.uuid4()),
                "patient_id": patient_id,
                "hba1c": hba1c,
                "age": age,
                "crp": crp,
                "flex": flex,
                "abd": abd,
                "ext_rot": ext_rot,
                "int_rot": int_rot,
                "pain": pain,
                "weeks": weeks,
                "thyroid": thyroid,
                "night_pain": night_pain,
                "bilateral": bilateral,
                "risk_score": risk_score,
                "predicted_class": predicted_class,
                "predicted_probability": predicted_probability,
                "severity": severity,
            }
            res = client.table("frozen_shoulder_assessments").insert(payload).execute()
            result = (res.data or [{}])[0]
            logger.info(f"Frozen shoulder assessment saved for patient {patient_id}")
            return result
        except Exception as e:
            logger.error(f"FrozenShoulderRepository.save_assessment error: {e}")
            return {}

    @staticmethod
    def get_assessment(patient_id: str) -> Dict[str, Any]:
        """Fetch the latest frozen shoulder assessment for a patient."""
        client = FrozenShoulderRepository._client()
        if not client:
            return {}
        try:
            res = (
                client.table("frozen_shoulder_assessments")
                .select("*")
                .eq("patient_id", patient_id)
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
            data = res.data or []
            return data[0] if data else {}
        except Exception as e:
            logger.error(f"FrozenShoulderRepository.get_assessment error: {e}")
            return {}

    @staticmethod
    def get_history(patient_id: str, limit: int = 5) -> List[Dict[str, Any]]:
        """Fetch frozen shoulder assessment history for a patient."""
        client = FrozenShoulderRepository._client()
        if not client:
            return []
        try:
            res = (
                client.table("frozen_shoulder_assessments")
                .select("*")
                .eq("patient_id", patient_id)
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            )
            return res.data or []
        except Exception as e:
            logger.error(f"FrozenShoulderRepository.get_history error: {e}")
            return []
