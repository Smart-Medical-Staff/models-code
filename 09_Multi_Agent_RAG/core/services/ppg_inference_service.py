from __future__ import annotations 
import logging
import pickle
from pathlib import Path
from typing import Any, Iterable, Optional

import numpy as np 

from core.schemas.ppg_schema import PPGInferenceResult, PPGSignalInput
from core.utils.signal_processing import extract_features, feature_vector, preprocess_signal
from tools.signal_quality_tool import SignalQualityTool

logger = logging.getLogger(__name__)


class PPGInferenceService:
    """Reusable PPG preprocessing, feature extraction, scaling, and inference."""

    def __init__(self, model_dir: Optional[Path] = None):
        self.model_dir = model_dir or Path(__file__).resolve().parents[1] / "models" / "ppg"
        self.quality_tool = SignalQualityTool()
        self._model: Any = None
        self._scaler: Any = None
        self._tflite: Any = None
        self._input_details: Any = None
        self._output_details: Any = None
        self._model_source: Optional[str] = None

    def _load_pickle(self, name: str) -> Any:
        path = self.model_dir / name
        if not path.exists():
            return None
        with path.open("rb") as fh:
            return pickle.load(fh)

    def load_artifacts(self) -> None:
        if self._model is not None or self._tflite is not None:
            return

        self.model_dir.mkdir(parents=True, exist_ok=True)
        self._scaler = self._load_pickle("scaler.pkl")
        for model_name in ("rf_model.pkl", "gb_model.pkl", "svm_model.pkl", "ppg_model.pkl"):
            model = self._load_pickle(model_name)
            if model is not None:
                self._model = model
                self._model_source = model_name
                logger.info("Loaded PPG sklearn artifact: %s", model_name)
                return

        tflite_path = self.model_dir / "ppg_to_risk_model.tflite"
        if tflite_path.exists():
            try:
                try:
                    from tflite_runtime.interpreter import Interpreter  # type: ignore
                except Exception:
                    from tensorflow.lite import Interpreter  # type: ignore

                self._tflite = Interpreter(model_path=str(tflite_path))
                self._tflite.allocate_tensors()
                self._input_details = self._tflite.get_input_details()[0]
                self._output_details = self._tflite.get_output_details()[0]
                self._model_source = "ppg_to_risk_model.tflite"
                logger.info("Loaded PPG TFLite artifact")
            except Exception as exc:
                logger.warning("Failed to load PPG TFLite artifact: %s", exc)

    def _scale(self, vector: np.ndarray) -> np.ndarray:
        if self._scaler is None:
            return vector.astype(np.float32)
        try:
            import pandas as pd
            from core.utils.signal_processing import FEATURE_NAMES
            df = pd.DataFrame(vector, columns=FEATURE_NAMES)
            return self._scaler.transform(df).astype(np.float32)
        except Exception:
            return self._scaler.transform(vector).astype(np.float32)

    def _predict_probability(self, scaled_features: np.ndarray) -> float:
        if self._model is not None:
            if hasattr(self._model, "predict_proba"):
                return float(self._model.predict_proba(scaled_features)[0, 1])
            pred = self._model.predict(scaled_features)
            return float(np.asarray(pred).reshape(-1)[0])

        if self._tflite is not None:
            self._tflite.set_tensor(self._input_details["index"], scaled_features.astype(np.float32))
            self._tflite.invoke()
            return float(self._tflite.get_tensor(self._output_details["index"])[0][0])

        raise FileNotFoundError(
            "No PPG model artifact found. Expected scaler.pkl plus one of "
            "rf_model.pkl, gb_model.pkl, svm_model.pkl, ppg_model.pkl, or ppg_to_risk_model.tflite"
        )

    @staticmethod
    def _risk_level(probability: float) -> str:
        if probability < 0.35:
            return "LOW RISK"
        if probability < 0.65:
            return "MODERATE RISK"
        return "HIGH RISK"

    def run(self, signal: PPGSignalInput) -> PPGInferenceResult:
        quality = self.quality_tool.validate(signal.red, signal.ir, signal.sampling_rate)
        if not quality.is_acceptable:
            return PPGInferenceResult(
                neuropathy_probability=0.0,
                risk_level="UNAVAILABLE",
                signal_quality=quality.label,
                features={},
                confidence=0.0,
                status="rejected",
                message="PPG signal rejected: " + "; ".join(quality.reasons),
                model_source=None,
            )

        try:
            red_clean, ir_clean = preprocess_signal(signal.red, signal.ir, fs=signal.sampling_rate)
            features = extract_features(red_clean, ir_clean, fs=signal.sampling_rate)
            self.load_artifacts()
            probability = max(0.0, min(1.0, self._predict_probability(self._scale(feature_vector(features)))))
            confidence = max(0.0, min(1.0, quality.score))
            return PPGInferenceResult(
                neuropathy_probability=round(probability, 4),
                risk_level=self._risk_level(probability),
                signal_quality=quality.label,
                features=features,
                confidence=round(confidence, 3),
                status="success",
                model_source=self._model_source,
            )
        except Exception as exc:
            logger.exception("PPG inference failed")
            return PPGInferenceResult(
                neuropathy_probability=0.0,
                risk_level="UNAVAILABLE",
                signal_quality=quality.label,
                features={},
                confidence=0.0,
                status="error",
                message=str(exc),
                model_source=self._model_source,
            )

    @classmethod
    def analyze(
        cls,
        red: Iterable[float],
        ir: Iterable[float],
        sampling_rate: int = 100,
        source: Optional[str] = None,
    ) -> PPGInferenceResult:
        return cls().run(PPGSignalInput(red=list(red), ir=list(ir), sampling_rate=sampling_rate, source=source))
