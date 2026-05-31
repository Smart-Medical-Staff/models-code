from __future__ import annotations

from typing import Any, Dict


def has_ppg_payload(patient_info: Dict[str, Any]) -> bool:
    payload = patient_info.get("ppg_payload") or patient_info.get("ppg")
    if not isinstance(payload, dict):
        return False
    return bool((payload.get("red") or payload.get("red_signal")) and (payload.get("ir") or payload.get("ir_signal")))


def format_ppg_rag_context(ppg_result: Dict[str, Any]) -> str:
    if not ppg_result:
        return ""
    if ppg_result.get("status") != "success":
        return (
            "Clinical Findings from optional PPG screening: "
            f"PPG analysis unavailable ({ppg_result.get('message', 'no result')})."
        )
    features = ppg_result.get("features") or {}
    findings = [
        "Clinical Findings from optional PPG screening:",
        f"- Neuropathy probability: {ppg_result.get('neuropathy_probability', 0):.1%}",
        f"- PPG risk level: {ppg_result.get('risk_level', 'N/A')}",
        f"- Signal quality: {ppg_result.get('signal_quality', 'N/A')}",
    ]
    if features.get("RMSSD") is not None:
        findings.append(f"- HRV marker RMSSD: {features['RMSSD']:.3f}")
    if features.get("Red_IR_Ratio_Mean") is not None:
        findings.append(f"- Peripheral perfusion Red/IR ratio: {features['Red_IR_Ratio_Mean']:.3f}")
    findings.append("- Experimental screening result; confirm clinically before action.")
    return "\n".join(findings)
