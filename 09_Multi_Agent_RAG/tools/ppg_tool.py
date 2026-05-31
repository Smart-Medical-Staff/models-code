from __future__ import annotations

from typing import Any, Dict

from core.schemas.ppg_schema import PPGSignalInput
from core.services.ppg_inference_service import PPGInferenceService


class PPGTool:
    """PPG analysis tool facade used by services, graph nodes, and registry calls."""

    def __init__(self, service: PPGInferenceService | None = None):
        self.service = service or PPGInferenceService()

    def run(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        signal = PPGSignalInput(
            red=payload.get("red") or payload.get("red_signal") or [],
            ir=payload.get("ir") or payload.get("ir_signal") or [],
            sampling_rate=int(payload.get("sampling_rate", 100)),
            source=payload.get("source"),
        )
        return self.service.run(signal).to_tool_response()
