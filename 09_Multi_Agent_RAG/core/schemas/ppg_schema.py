from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, field_validator


class PPGSignalInput(BaseModel):
    """Raw red/IR PPG waveform input for optional neuropathy screening."""

    red: List[float] = Field(default_factory=list)
    ir: List[float] = Field(default_factory=list)
    sampling_rate: int = Field(default=100, ge=25, le=500)
    source: Optional[str] = None

    @field_validator("red", "ir")
    @classmethod
    def _non_empty_numeric(cls, values: List[float]) -> List[float]:
        if not values:
            raise ValueError("PPG signal channel cannot be empty")
        return [float(v) for v in values]


class PPGQualityResult(BaseModel):
    score: float = Field(ge=0.0, le=1.0)
    label: str
    is_acceptable: bool
    reasons: List[str] = Field(default_factory=list)
    metrics: Dict[str, float] = Field(default_factory=dict)


class PPGInferenceResult(BaseModel):
    neuropathy_probability: float = Field(ge=0.0, le=1.0)
    risk_level: str
    signal_quality: str
    features: Dict[str, float] = Field(default_factory=dict)
    confidence: float = Field(ge=0.0, le=1.0)
    status: str = "success"
    message: Optional[str] = None
    model_source: Optional[str] = None
    disclaimer: str = (
        "Experimental PPG screening only; it does not diagnose diabetic neuropathy "
        "or replace clinical examination, NCS/EMG, or clinician advice."
    )

    def to_tool_response(self) -> Dict[str, Any]:
        return self.model_dump()
