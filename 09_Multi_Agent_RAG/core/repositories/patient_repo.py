import uuid
import logging
from typing import List, Dict, Any, Optional
from core.repositories.base_repository import BaseRepository

logger = logging.getLogger(__name__)

class PatientRepository(BaseRepository):
    
    @staticmethod
    def get_all_patients() -> List[Dict[str, Any]]:
        client = PatientRepository._client()
        if not client:
            return []
        try:
            res = client.table("patients").select("*").execute()
            return res.data or []
        except Exception as e:
            logger.error(f"PatientRepository.get_all_patients error: {e}")
            return []

    @staticmethod
    def create_patient(
        name: str,
        age: int,
        gender: str,
        diabetes_type: Optional[str] = None,
        diabetes_duration: Optional[int] = None
    ) -> Dict[str, Any]:
        import traceback
        client = PatientRepository._client()
        if not client:
            logger.error("PatientRepository.create_patient: Supabase client is None")
            return {}
        patient_id = str(uuid.uuid4())
        payload = {
            "id": patient_id,
            "name": name.strip(),
            "age": age,
            "gender": gender,
            "owner_user_id": "00000000-0000-0000-0000-000000000000"
        }
        logger.info(f"PatientRepository.create_patient: Attempting insert with payload: {payload}")
        try:
            res = client.table("patients").insert(payload).execute()
            logger.info(f"PatientRepository.create_patient: Response data: {res.data}")
            patient = (res.data or [{}])[0]
            if not patient:
                logger.error("PatientRepository.create_patient: Empty patient data returned in response")
                return {}
            
            patient["diabetes_type"] = diabetes_type
            patient["diabetes_duration"] = diabetes_duration
            return patient
        except Exception as e:
            logger.error(f"PatientRepository.create_patient exception type: {type(e).__name__}")
            logger.error(f"PatientRepository.create_patient message: {str(e)}")
            logger.error(f"PatientRepository.create_patient traceback:\n{traceback.format_exc()}")
            return {}
