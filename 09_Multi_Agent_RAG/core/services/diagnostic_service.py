import logging
from typing import Dict, Any, List, Optional
from core.repositories.patient_repo import PatientRepository
from core.repositories.clinical_repo import ClinicalRepository
from core.repositories.ml_repo import MLRepository
from core.repositories.memory_repo import MemoryRepository
from core.repositories.decision_repo import DecisionRepository
from core.questionnaire import (
    calculate_section_scores,
    ml_neuropathy_prediction,
    final_decision,
    ml_gestational_prediction,
    ml_heart_risk_prediction,
    ml_osteo_prediction,
    ml_shoulder_prediction,
    calculate_gestational_score,
    calculate_heart_risk_score,
    get_eligible_questions,
    _safe_float,
)
from core.repositories.gestational_repo import GestationalRepository
from core.repositories.heart_risk_repo import HeartRiskRepository
from core.repositories.osteo_repo import OsteoporosisRepository
from core.repositories.shoulder_repo import FrozenShoulderRepository
from core.repositories.ppg_repository import PPGRepository
from core.schemas.ppg_schema import PPGSignalInput

logger = logging.getLogger(__name__)

class DiagnosticService:
    """
    Business orchestration layer.
    Agents and UI must only call this service, never the database directly.
    """

    @staticmethod
    def load_patient_context(patient_id: str) -> Dict[str, Any]:
        """Loads all existing patient data from DB."""
        clinical = ClinicalRepository.get_clinical_data(patient_id)
        ml_res = MLRepository.get_ml_prediction(patient_id)
        decision = DecisionRepository.get_latest_decision(patient_id)
        
        return {
            "clinical_data": clinical,
            "ml_prediction": ml_res,
            "latest_decision": decision
        }

    @staticmethod
    def get_clinical_data(patient_id: str) -> Dict[str, Any]:
        return ClinicalRepository.get_clinical_data(patient_id)

    @staticmethod
    def get_ml_prediction(patient_id: str) -> Dict[str, Any]:
        return MLRepository.get_ml_prediction(patient_id)

    @staticmethod
    def get_recent_decisions(patient_id: str, limit: int = 5) -> List[Dict[str, Any]]:
        return DecisionRepository.get_decisions(patient_id, limit)

    @staticmethod
    def save_clinical_data(patient_id: str, answers: Dict[str, Any]) -> Dict[str, Any]:
        """Computes section scores from answers and saves them to DB."""
        if not answers:
            return {}
            
        scores = calculate_section_scores(answers)
        
        ClinicalRepository.save_nss_assessment(patient_id, scores.get("nss_score", 0))
        ClinicalRepository.save_nds_assessment(patient_id, scores.get("nds_score", 0))
        ClinicalRepository.save_gum_assessment(patient_id, scores.get("gum_score", 0))
        ClinicalRepository.save_ulcer_assessment(patient_id, scores.get("ulcer_score", 0))
        
        return scores

    @staticmethod
    def run_ml_inference(patient_id: str, answers: Dict[str, Any], nss_score: int, age: int) -> Dict[str, Any]:
        """Computes ML prediction and saves it to DB."""
        result = ml_neuropathy_prediction(answers, nss_score, age)
        
        features = result.get("features", {})
        
        # Fallback values for features not tracked in the current questionnaire
        heat_avg = float((_safe_float(answers.get("ml_heat_right"), 38.0) + _safe_float(answers.get("ml_heat_left"), 38.0)) / 2.0)
        cold_avg = float((_safe_float(answers.get("ml_cold_right"), 20.0) + _safe_float(answers.get("ml_cold_left"), 20.0)) / 2.0)
        
        MLRepository.save_ml_prediction(
            patient_id=patient_id,
            nss_score=features.get("nss", nss_score),
            bmi_baseline=float(features.get("bmi", 22.0)),
            age_baseline=int(features.get("age", age)),
            hba1c_baseline=float(features.get("hba1c", 7.0)),
            heat_avg=heat_avg,
            cold_avg=cold_avg,
            predicted_class=result["predicted_class"],
            predicted_probability=result["predicted_probability"]
        )
        
        return result

    @staticmethod
    def compute_fusion(patient_id: str, ai_prediction: str, nds_score: int, nss_score: int) -> Dict[str, Any]:
        """Computes final fusion decision and saves it to DB."""
        result = final_decision(ai_prediction, nds_score, nss_score)
        
        DecisionRepository.save_final_decision(
            patient_id=patient_id,
            ai_prediction=ai_prediction,
            nds_score=nds_score,
            nss_score=nss_score,
            calculated_score=result["fusion_score"],
            final_decision=result["final_decision"]
        )
        
        return result

    @staticmethod
    def store_memory(patient_id: str, session_id: str, role: str, content: str, embedding: Optional[List[float]] = None) -> None:
        """Saves interaction to memory RAG layer."""
        MemoryRepository.save_conversation_memory(patient_id, session_id, role, content, embedding)

    @staticmethod
    def retrieve_memory(patient_id: str, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        """Retrieves semantic memory records."""
        from core.rag_engine import generate_embedding

        embedding = generate_embedding(query)
        if not embedding:
            return []
        return MemoryRepository.match_memory(patient_id, embedding, limit)

    @staticmethod
    def run_ppg_assessment(payload: Dict[str, Any]) -> Dict[str, Any]:
        """Run optional PPG-based neuropathy screening from raw red/IR waveform data."""
        from tools.ppg_tool import PPGTool

        red = payload.get("red") or payload.get("red_signal") or []
        ir  = payload.get("ir")  or payload.get("ir_signal")  or []

        if not red or not ir:
            return {
                "status": "error",
                "message": "PPG payload is missing red/IR signal data.",
            }

        try:
            signal = PPGSignalInput(
                red=red,
                ir=ir,
                sampling_rate=int(payload.get("sampling_rate", 100)),
                source=payload.get("source"),
            )
            return PPGTool().service.run(signal).to_tool_response()
        except Exception as exc:
            logger.error("DiagnosticService.run_ppg_assessment validation error: %s", exc)
            return {"status": "error", "message": str(exc)}


    @staticmethod
    def save_ppg_assessment(
        patient_id: Optional[str],
        session_id: Optional[str],
        ppg_result: Dict[str, Any],
        ppg_payload: Dict[str, Any],
        reasoning_summary: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Persist optional PPG screening output and signal metadata.

        This is intentionally non-throwing so database outages never interrupt
        the diagnostic workflow.
        """
        if not ppg_result or ppg_result.get("status") != "success":
            return {}
        try:
            saved = PPGRepository.save_assessment(
                patient_id=patient_id,
                session_id=session_id,
                neuropathy_probability=float(ppg_result.get("neuropathy_probability", 0.0)),
                risk_level=str(ppg_result.get("risk_level", "")),
                signal_quality=str(ppg_result.get("signal_quality", "")),
                confidence=float(ppg_result.get("confidence", 0.0)),
                features=ppg_result.get("features") or {},
                reasoning_summary=reasoning_summary,
            )
            assessment_id = saved.get("id") if saved else None
            if assessment_id:
                red = ppg_payload.get("red") or ppg_payload.get("red_signal") or []
                ir = ppg_payload.get("ir") or ppg_payload.get("ir_signal") or []
                PPGRepository.save_signal_metadata(
                    assessment_id=assessment_id,
                    signal_length=min(len(red), len(ir)),
                    sampling_rate=ppg_payload.get("sampling_rate"),
                    upload_source=ppg_payload.get("source"),
                )
            return saved or {}
        except Exception as e:
            logger.error("DiagnosticService.save_ppg_assessment error: %s", e)
            return {}

    @staticmethod
    def get_ppg_assessment_history(patient_id: str, limit: int = 5) -> List[Dict[str, Any]]:
        return PPGRepository.get_assessment_history(patient_id, limit)

    @staticmethod
    def get_recent_ppg_assessments(limit: int = 10) -> List[Dict[str, Any]]:
        return PPGRepository.get_recent_assessments(limit)
        
    @staticmethod
    def get_all_patients() -> List[Dict[str, Any]]:
        """Retrieves all patients for UI."""
        return PatientRepository.get_all_patients()
        
    @staticmethod
    def create_new_patient(name: str, age: int, gender: str, diabetes_type: Optional[str] = None, diabetes_duration: Optional[int] = None) -> Dict[str, Any]:
        """Creates a new patient."""
        return PatientRepository.create_patient(name, age, gender, diabetes_type, diabetes_duration)

    # ═══════════════════════════════════════════════════════════════
    # GESTATIONAL DIABETES ASSESSMENT METHODS (NEW)
    # ═══════════════════════════════════════════════════════════════

    @staticmethod
    def save_gestational_assessment(patient_id: str, answers: Dict[str, Any], patient_info: Dict[str, Any]) -> Dict[str, Any]:
        """Computes gestational diabetes risk score and saves it to DB."""
        # Only process for female patients
        if patient_info.get("gender") != "Female":
            return {"error": "Gestational diabetes assessment only applicable for female patients"}
        
        gd_scores = calculate_gestational_score(answers)
        bmi = _safe_float(answers.get("gd_bmi"), _safe_float(patient_info.get("bmi"), 25.0))
        pregnancy_week = int(_safe_float(answers.get("gd_pregnancy_week"), 0.0))
        glucose_level = _safe_float(answers.get("gd_fasting_glucose"), 0.0) * 30.0
        fasting_glucose = _safe_float(answers.get("gd_fasting_glucose"), 0.0) * 30.0
        insulin_resistance = bmi / 10.0
        family_history = bool(_safe_float(answers.get("gd_family_history"), 0.0) > 0.0)
        
        # Run ML prediction
        ml_result = ml_gestational_prediction(answers, gd_scores["gd_score"], bmi, patient_info.get("age", 25))
        
        # Save to database
        db_result = GestationalRepository.save_gestational_assessment(
            patient_id=patient_id,
            pregnancy_week=pregnancy_week,
            glucose_level=glucose_level,
            fasting_glucose=fasting_glucose,
            insulin_resistance=insulin_resistance,
            bmi=bmi,
            family_history=family_history,
            risk_score=ml_result["predicted_probability"],
            predicted_class=ml_result["predicted_class"],
            predicted_probability=ml_result["predicted_probability"],
        )
        
        return {
            "gd_scores": gd_scores,
            "ml_result": ml_result,
            "db_result": db_result,
        }

    @staticmethod
    def get_gestational_assessment(patient_id: str) -> Dict[str, Any]:
        """Fetch the latest gestational diabetes assessment for a patient."""
        return GestationalRepository.get_gestational_assessment(patient_id)

    @staticmethod
    def get_gestational_history(patient_id: str, limit: int = 5) -> list:
        """Fetch gestational diabetes assessment history for a patient."""
        return GestationalRepository.get_gestational_history(patient_id, limit)

    # ═══════════════════════════════════════════════════════════════
    # HEART RISK ASSESSMENT METHODS (NEW)
    # ═══════════════════════════════════════════════════════════════

    @staticmethod
    def save_heart_risk_assessment(patient_id: str, answers: Dict[str, Any], patient_info: Dict[str, Any]) -> Dict[str, Any]:
        """Computes heart risk score and saves it to DB."""
        hr_scores = calculate_heart_risk_score(answers)
        
        # Extract heart risk features
        cholesterol = _safe_float(answers.get("hr_cholesterol"), 0.0) * 60.0 + 150.0
        bp_score = int(_safe_float(answers.get("hr_blood_pressure"), 0.0))
        blood_pressure_systolic = 120.0 + bp_score * 15.0
        blood_pressure_diastolic = 80.0 + bp_score * 10.0
        resting_heart_rate = int(60.0 + _safe_float(answers.get("hr_resting_heart_rate"), 0.0) * 15.0)
        smoking_status = {0: "Never", 1: "Former (>1y)", 2: "Former (<1y)", 3: "Current"}.get(
            int(_safe_float(answers.get("hr_smoking_status"), 0.0)), "Unknown"
        )
        bmi = _safe_float(answers.get("hr_bmi"), _safe_float(patient_info.get("bmi"), 25.0))
        exercise_frequency = int(_safe_float(answers.get("hr_exercise_frequency"), 0.0))
        diabetes_duration = int(_safe_float(patient_info.get("diabetes_duration"), 0.0))
        
        # Run ML prediction
        ml_result = ml_heart_risk_prediction(
            answers,
            hr_scores["hr_score"],
            patient_info.get("age", 50),
            diabetes_duration
        )
        
        # Save to database
        db_result = HeartRiskRepository.save_heart_risk_assessment(
            patient_id=patient_id,
            cholesterol=cholesterol,
            blood_pressure_systolic=blood_pressure_systolic,
            blood_pressure_diastolic=blood_pressure_diastolic,
            resting_heart_rate=resting_heart_rate,
            smoking_status=smoking_status,
            bmi=bmi,
            diabetes_duration=diabetes_duration,
            exercise_frequency=exercise_frequency,
            risk_score=ml_result["predicted_probability"],
            predicted_class=ml_result["predicted_class"],
            predicted_probability=ml_result["predicted_probability"],
        )
        
        return {
            "hr_scores": hr_scores,
            "ml_result": ml_result,
            "db_result": db_result,
        }

    @staticmethod
    def get_heart_risk_assessment(patient_id: str) -> Dict[str, Any]:
        """Fetch the latest heart risk assessment for a patient."""
        return HeartRiskRepository.get_heart_risk_assessment(patient_id)

    @staticmethod
    def get_heart_risk_history(patient_id: str, limit: int = 5) -> list:
        """Fetch heart risk assessment history for a patient."""
        return HeartRiskRepository.get_heart_risk_history(patient_id, limit)

    @staticmethod
    def save_osteo_assessment(patient_id: str, answers: Dict[str, Any], patient_info: Dict[str, Any]) -> Dict[str, Any]:
        """Computes osteoporosis risk score and saves it to DB."""
        scores = calculate_section_scores(answers)
        osteo_score = scores.get("osteo_score", 0)

        age = int(_safe_float(patient_info.get("age"), 50.0))
        duration = int(_safe_float(patient_info.get("diabetes_duration"), 5.0))
        
        # Run ML prediction
        ml_result = ml_osteo_prediction(answers, osteo_score, age, duration)
        
        # Extract features
        hba1c = _safe_float(answers.get("osteo_hba1c"), 7.0)
        bmi = _safe_float(answers.get("osteo_bmi"), 22.0)
        ca = _safe_float(answers.get("osteo_ca"), 9.5)
        vit_d = _safe_float(answers.get("osteo_vit_d"), 30.0)
        pth = _safe_float(answers.get("osteo_pth"), 35.0)
        phos = _safe_float(answers.get("osteo_phos"), 3.5)
        activity = int(_safe_float(answers.get("osteo_activity"), 4.0))
        smoke = bool(_safe_float(answers.get("osteo_smoke"), 0.0) > 0.0)
        frac = bool(_safe_float(answers.get("osteo_frac"), 0.0) > 0.0)
        steroids = bool(_safe_float(answers.get("osteo_steroids"), 0.0) > 0.0)

        # Save to database
        db_result = OsteoporosisRepository.save_assessment(
            patient_id=patient_id,
            age=age,
            hba1c=hba1c,
            duration=duration,
            bmi=bmi,
            ca=ca,
            vit_d=vit_d,
            pth=pth,
            phos=phos,
            activity=activity,
            smoke=smoke,
            frac=frac,
            steroids=steroids,
            risk_score=ml_result["predicted_probability"],
            predicted_class=ml_result["predicted_class"],
            predicted_probability=ml_result["predicted_probability"],
            severity="High Risk" if ml_result["predicted_class"] == 1 else "Low Risk",
        )
        
        return {
            "score": osteo_score,
            "ml_result": ml_result,
            "db_result": db_result,
        }

    @staticmethod
    def save_shoulder_assessment(patient_id: str, answers: Dict[str, Any], patient_info: Dict[str, Any]) -> Dict[str, Any]:
        """Computes frozen shoulder risk score and saves it to DB."""
        scores = calculate_section_scores(answers)
        shoulder_score = scores.get("shoulder_score", 0)

        age = int(_safe_float(patient_info.get("age"), 50.0))
        
        # Run ML prediction
        ml_result = ml_shoulder_prediction(answers, shoulder_score, age)
        
        # Extract features
        hba1c = _safe_float(answers.get("shoulder_hba1c"), 7.0)
        crp = _safe_float(answers.get("shoulder_crp"), 1.5)
        flex = _safe_float(answers.get("shoulder_flex"), 150.0)
        abd = _safe_float(answers.get("shoulder_abd"), 130.0)
        ext_rot = _safe_float(answers.get("shoulder_ext_rot"), 45.0)
        int_rot = _safe_float(answers.get("shoulder_int_rot"), 45.0)
        pain = int(_safe_float(answers.get("shoulder_pain"), 2.0))
        weeks = int(_safe_float(answers.get("shoulder_weeks"), 2.0))
        thyroid = bool(_safe_float(answers.get("shoulder_thyroid"), 0.0) > 0.0)
        night_pain = bool(_safe_float(answers.get("shoulder_night_pain"), 0.0) > 0.0)
        bilateral = bool(_safe_float(answers.get("shoulder_bilateral"), 0.0) > 0.0)

        # Save to database
        db_result = FrozenShoulderRepository.save_assessment(
            patient_id=patient_id,
            hba1c=hba1c,
            age=age,
            crp=crp,
            flex=flex,
            abd=abd,
            ext_rot=ext_rot,
            int_rot=int_rot,
            pain=pain,
            weeks=weeks,
            thyroid=thyroid,
            night_pain=night_pain,
            bilateral=bilateral,
            risk_score=ml_result["predicted_probability"],
            predicted_class=ml_result["predicted_class"],
            predicted_probability=ml_result["predicted_probability"],
            severity="High Risk" if ml_result["predicted_class"] == 1 else "Low Risk",
        )
        
        return {
            "score": shoulder_score,
            "ml_result": ml_result,
            "db_result": db_result,
        }

    @staticmethod
    def run_secondary_assessments(
        patient_id: str,
        answers: Dict[str, Any],
        patient_info: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Run post-fusion secondary assessments (gestational + heart risk + osteo + shoulder).
        Gestational runs only for Female patients; heart risk, osteo, and shoulder run for all.
        """
        gender = patient_info.get("gender", "")
        result: Dict[str, Any] = {
            "gestational": {},
            "heart_risk": {},
            "osteo": {},
            "shoulder": {},
            "skipped_assessments": [],
        }

        if gender == "Female":
            result["gestational"] = DiagnosticService.save_gestational_assessment(
                patient_id, answers, patient_info
            )
            logger.info({
                "event": "gestational_saved",
                "patient_id": patient_id,
                "node": "secondary_assessment_node",
            })
        else:
            result["skipped_assessments"].append("gestational_diabetes")
            result["gestational"] = {
                "skipped": True,
                "reason": "Not applicable — gestational screening is for female patients only",
            }

        result["heart_risk"] = DiagnosticService.save_heart_risk_assessment(
            patient_id, answers, patient_info
        )
        logger.info({
            "event": "heart_risk_saved",
            "patient_id": patient_id,
            "node": "secondary_assessment_node",
        })

        result["osteo"] = DiagnosticService.save_osteo_assessment(
            patient_id, answers, patient_info
        )
        logger.info({
            "event": "osteo_saved",
            "patient_id": patient_id,
            "node": "secondary_assessment_node",
        })

        result["shoulder"] = DiagnosticService.save_shoulder_assessment(
            patient_id, answers, patient_info
        )
        logger.info({
            "event": "shoulder_saved",
            "patient_id": patient_id,
            "node": "secondary_assessment_node",
        })

        return result
