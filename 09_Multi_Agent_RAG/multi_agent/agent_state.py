"""
multi_agent/agent_state.py — Legacy compatibility AgentState for tool execution.
"""
from typing import Any, Dict, List, Optional

class AgentState:
    def __init__(
        self,
        patient_id: str = "",
        patient_info: Optional[Dict] = None,
        answers: Optional[Dict] = None,
        clinical_data: Optional[Dict] = None,
        ml_results: Optional[Dict] = None,
        retrieved_memory: Optional[List] = None,
    ):
        self.patient_id = patient_id
        self.patient_info = patient_info or {}
        self.answers = answers or {}
        self.clinical_data = clinical_data or {}
        self.ml_results = ml_results or {}
        self.retrieved_memory = retrieved_memory or []
        self.fusion_results = {}
        self.waiting_for_patient = False
        self.pending_question = {}
        self.iteration = 0

    def add_observation(self, tool_name: str, result: Any):
        """No-op or logs the observation for trace."""
        pass
