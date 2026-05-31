"""
osteo_repo.py — Osteoporosis Assessment Data Access Layer
Follows BaseRepository pattern for clean architecture.
"""
import uuid
import logging
from typing import Dict, Any, List
from core.repositories.base_repository import BaseRepository

logger = logging.getLogger(__name__)


class OsteoporosisRepository(BaseRepository):
    """Manages osteoporosis assessment data in Supabase."""

    @staticmethod
    def save_assessment(
        patient_id: str,
        age: int,
        hba1c: float,
        duration: int,
        bmi: float,
        ca: float,
        vit_d: float,
        pth: float,
        phos: float,
        activity: int,
        smoke: bool,
        frac: bool,
        steroids: bool,
        risk_score: float,
        predicted_class: int,
        predicted_probability: float,
        severity: str,
    ) -> Dict[str, Any]:
        """Save osteoporosis assessment to database."""
        client = OsteoporosisRepository._client()
        if not client:
            return {}
        try:
            payload = {
                "id": str(uuid.uuid4()),
                "patient_id": patient_id,
                "age": age,
                "hba1c": hba1c,
                "duration": duration,
                "bmi": bmi,
                "ca": ca,
                "vit_d": vit_d,
                "pth": pth,
                "phos": phos,
                "activity": activity,
                "smoke": smoke,
                "frac": frac,
                "steroids": steroids,
                "risk_score": risk_score,
                "predicted_class": predicted_class,
                "predicted_probability": predicted_probability,
                "severity": severity,
            }
            res = client.table("osteoporosis_assessments").insert(payload).execute()
            result = (res.data or [{}])[0]
            logger.info(f"Osteoporosis assessment saved for patient {patient_id}")
            return result
        except Exception as e:
            logger.error(f"OsteoporosisRepository.save_assessment error: {e}")
            return {}

    @staticmethod
    def get_assessment(patient_id: str) -> Dict[str, Any]:
        """Fetch the latest osteoporosis assessment for a patient."""
        client = OsteoporosisRepository._client()
        if not client:
            return {}
        try:
            res = (
                client.table("osteoporosis_assessments")
                .select("*")
                .eq("patient_id", patient_id)
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
            data = res.data or []
            return data[0] if data else {}
        except Exception as e:
            logger.error(f"OsteoporosisRepository.get_assessment error: {e}")
            return {}

    @staticmethod
    def get_history(patient_id: str, limit: int = 5) -> List[Dict[str, Any]]:
        """Fetch osteoporosis assessment history for a patient."""
        client = OsteoporosisRepository._client()
        if not client:
            return []
        try:
            res = (
                client.table("osteoporosis_assessments")
                .select("*")
                .eq("patient_id", patient_id)
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            )
            return res.data or []
        except Exception as e:
            logger.error(f"OsteoporosisRepository.get_history error: {e}")
            return []
