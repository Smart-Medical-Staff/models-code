from __future__ import annotations

from typing import Iterable

import numpy as np

from core.schemas.ppg_schema import PPGQualityResult
from core.utils.signal_processing import as_float_array, find_ppg_peaks, signal_snr


class SignalQualityTool:
    """Validate PPG waveform safety before inference."""

    min_seconds: float = 10.0

    def validate(
        self,
        red: Iterable[float],
        ir: Iterable[float],
        sampling_rate: int = 100,
    ) -> PPGQualityResult:
        reasons: list[str] = []
        red_arr = as_float_array(red)
        ir_arr = as_float_array(ir)
        min_len = min(len(red_arr), len(ir_arr))

        if min_len < int(self.min_seconds * sampling_rate):
            reasons.append("Signal is too short for HRV-oriented PPG screening")
        if min_len == 0:
            return PPGQualityResult(
                score=0.0,
                label="invalid",
                is_acceptable=False,
                reasons=["Missing valid red/IR samples"],
                metrics={},
            )

        red_arr = red_arr[:min_len]
        ir_arr = ir_arr[:min_len]
        flatline_red = float(np.std(red_arr))
        flatline_ir = float(np.std(ir_arr))
        if flatline_red < 1e-6 or flatline_ir < 1e-6:
            reasons.append("Flatline or near-flat sensor input detected")

        if np.max(np.abs(red_arr)) > 1e9 or np.max(np.abs(ir_arr)) > 1e9:
            reasons.append("Sensor values are outside supported numeric range")

        peaks = find_ppg_peaks(red_arr, fs=sampling_rate)
        expected_peaks = min_len / sampling_rate * 1.2
        peak_rate = min(float(len(peaks)) / (expected_peaks + 1e-8), 1.0)
        snr_red = signal_snr(red_arr)
        snr_ir = signal_snr(ir_arr)
        diff = np.diff(red_arr)
        motion_ratio = (
            float(np.mean(np.abs(diff) > 3 * np.std(diff))) if len(diff) and np.std(diff) else 0.0
        )

        if peak_rate < 0.35:
            reasons.append("Insufficient pulse peaks detected")
        if snr_red < 3.0 or snr_ir < 3.0:
            reasons.append("Low signal-to-noise ratio")
        if motion_ratio >= 0.15:
            reasons.append("Likely motion artifact")

        score_parts = [
            min(max((snr_red + snr_ir) / 30.0, 0.0), 1.0),
            peak_rate,
            1.0 - min(motion_ratio / 0.15, 1.0),
            0.0 if reasons and "Flatline or near-flat sensor input detected" in reasons else 1.0,
        ]
        score = float(np.mean(score_parts))
        label = "good" if score >= 0.75 else "fair" if score >= 0.55 else "poor"
        is_acceptable = score >= 0.55 and not any(
            r in reasons
            for r in [
                "Missing valid red/IR samples",
                "Flatline or near-flat sensor input detected",
                "Sensor values are outside supported numeric range",
            ]
        )
        return PPGQualityResult(
            score=round(score, 3),
            label=label,
            is_acceptable=is_acceptable,
            reasons=reasons,
            metrics={
                "snr_red": round(snr_red, 3),
                "snr_ir": round(snr_ir, 3),
                "peak_success_rate": round(peak_rate, 3),
                "motion_ratio": round(motion_ratio, 3),
                "samples": float(min_len),
            },
        )
