"""
ppg_repository.py - PPG Neuropathy Assessment Data Access Layer.

Stores derived screening outputs and signal metadata only. Raw waveform arrays
are intentionally not persisted here.
"""
from __future__ import annotations

import logging
import uuid
from typing import Any, Dict, List, Optional

from core.repositories.base_repository import BaseRepository

logger = logging.getLogger(__name__)


class PPGRepository(BaseRepository):
    """Manages optional PPG neuropathy screening data in Supabase."""

    @staticmethod
    def save_assessment(
        patient_id: Optional[str],
        session_id: Optional[str],
        neuropathy_probability: float,
        risk_level: str,
        signal_quality: str,
        confidence: float,
        features: Dict[str, Any],
        reasoning_summary: Optional[str] = None,
    ) -> Dict[str, Any]:
        client = PPGRepository._client()
        if not client:
            return {}
        try:
            payload = {
                "id": str(uuid.uuid4()),
                "patient_id": patient_id,
                "session_id": session_id,
                "neuropathy_probability": neuropathy_probability,
                "risk_level": risk_level,
                "signal_quality": signal_quality,
                "confidence": confidence,
                "features": features or {},
                "reasoning_summary": reasoning_summary,
            }
            res = client.table("ppg_assessments").insert(payload).execute()
            result = (res.data or [{}])[0]
            logger.info("PPG assessment saved for patient %s", patient_id)
            return result
        except Exception as e:
            logger.error("PPGRepository.save_assessment error: %s", e)
            return {}

    @staticmethod
    def save_signal_metadata(
        assessment_id: str,
        signal_length: int,
        sampling_rate: Optional[int] = None,
        upload_source: Optional[str] = None,
    ) -> Dict[str, Any]:
        client = PPGRepository._client()
        if not client or not assessment_id:
            return {}
        try:
            payload = {
                "id": str(uuid.uuid4()),
                "assessment_id": assessment_id,
                "signal_length": signal_length,
                "sampling_rate": sampling_rate,
                "upload_source": upload_source,
            }
            res = client.table("ppg_signal_metadata").insert(payload).execute()
            return (res.data or [{}])[0]
        except Exception as e:
            logger.error("PPGRepository.save_signal_metadata error: %s", e)
            return {}

    @staticmethod
    def get_latest_assessment(patient_id: str) -> Dict[str, Any]:
        return PPGRepository.select_latest_by_patient("ppg_assessments", patient_id)

    @staticmethod
    def get_assessment_history(patient_id: str, limit: int = 5) -> List[Dict[str, Any]]:
        return PPGRepository.select_many_by_patient("ppg_assessments", patient_id, limit)

    @staticmethod
    def get_recent_assessments(limit: int = 10) -> List[Dict[str, Any]]:
        client = PPGRepository._client()
        if not client:
            return []
        try:
            res = (
                client.table("ppg_assessments")
                .select("*")
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            )
            return res.data or []
        except Exception as e:
            logger.error("PPGRepository.get_recent_assessments error: %s", e)
            return []
