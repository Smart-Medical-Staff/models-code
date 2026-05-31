"""
multi_agent/state.py — Shared state object for the Multi-Agent Diagnostic System.
All agents read from and write to this single source of truth.
"""
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Literal


# ── Graph Node Names ───────────────────────────────────────────────
NODE_PLANNER            = "planner_node"
NODE_MEMORY             = "memory_node"
NODE_REASONING          = "reasoning_node"
NODE_TOOL               = "tool_node"
NODE_ML                 = "ml_node"
NODE_FUSION             = "fusion_node"
NODE_PPG                = "ppg_node"
NODE_REFLECTION         = "reflection_node"
NODE_REPORT             = "report_node"
NODE_SECONDARY          = "secondary_assessment_node"
NODE_ASSESSMENT_SELECT  = "assessment_select_node"   # NEW — initial module picker
NODE_ASSESSMENT_RUN     = "assessment_run_node"       # NEW — runs current module Q&A
NODE_ASSESSMENT_PARTIAL = "assessment_partial_node"  # NEW — show partial result + choice
NODE_WAIT               = "patient_wait"
NODE_END                = "END"


@dataclass
class AuditEntry:
    """Single entry in the agent audit log."""
    timestamp: str
    agent: str
    node: str
    action: str
    details: Any
    iteration: int


@dataclass
class ReflectionEntry:
    """Self-critique from Reflection Agent."""
    iteration: int
    issues: list[str]
    suggestions: list[str]
    is_consistent: bool
    should_replan: bool


@dataclass
class MultiAgentState:
    # ── Patient Identity ───────────────────────────────────────────
    patient_id: str = ""
    patient_info: dict = field(default_factory=dict)

    # ── Memory Layers ──────────────────────────────────────────────
    short_term: list[dict] = field(default_factory=list)     # conversation history
    long_term: list[dict] = field(default_factory=list)      # RAG vector results
    episodic: list[dict] = field(default_factory=list)       # past sessions

    # ── Clinical Data ──────────────────────────────────────────────
    answers: dict = field(default_factory=dict)              # patient questionnaire answers
    questionnaire_step: int = 0                              # current question index
    clinical_scores: dict = field(default_factory=dict)      # NSS, NDS, Gum, Ulcer
    ml_results: dict = field(default_factory=dict)           # ML prediction output
    fusion_results: dict = field(default_factory=dict)       # final weighted decision
    ppg_results: dict = field(default_factory=dict)
    ppg_assessment_id: str | None = None
    ppg_analysis_complete: bool = False
    gestational_results: dict = field(default_factory=dict)
    heart_risk_results: dict = field(default_factory=dict)
    osteo_results: dict = field(default_factory=dict)
    shoulder_results: dict = field(default_factory=dict)
    secondary_assessments_complete: bool = False
    skipped_assessments: list = field(default_factory=list)

    # ── On-Demand Assessment Flow ──────────────────────────────────
    selected_assessments: list = field(default_factory=list)   # chosen by patient
    completed_assessments: list = field(default_factory=list)  # successfully finished
    assessment_queue: list = field(default_factory=list)       # remaining to run
    current_assessment: str = ""                               # assessment running now
    partial_results: dict = field(default_factory=dict)        # keyed by assessment name
    waiting_for_assessment_selection: bool = False             # paused at picker screen
    waiting_for_assessment_choice: bool = False                # paused at "add more / report" screen

    # ── Agent Planning ─────────────────────────────────────────────
    plan: list[str] = field(default_factory=list)
    plan_version: int = 0

    # ── Reasoning Chain ────────────────────────────────────────────
    reasoning_chain: list[dict] = field(default_factory=list)
    pending_tool_call: dict = field(default_factory=dict)
    last_tool_observation: dict = field(default_factory=dict)

    # ── Reflections ────────────────────────────────────────────────
    reflections: list[ReflectionEntry] = field(default_factory=list)
    reflection_count: int = 0

    # ── Graph Control ──────────────────────────────────────────────
    current_node: str = NODE_PLANNER
    next_node: str = NODE_PLANNER
    iteration: int = 0
    max_iterations: int = 12
    consecutive_reasoning: int = 0  # prevent reasoning loops

    # ── Patient Interaction ────────────────────────────────────────
    waiting_for_patient: bool = False
    pending_question: dict = field(default_factory=dict)
    pending_assessment_choice: dict = field(default_factory=dict)  # options for between-assessment screen

    # ── Output ────────────────────────────────────────────────────
    confidence: float = 0.0
    is_complete: bool = False
    final_report: str = ""
    decision_path: list[str] = field(default_factory=list)

    # ── Audit Log ──────────────────────────────────────────────────
    audit_log: list[AuditEntry] = field(default_factory=list)

    # ── Streaming Events ───────────────────────────────────────────
    stream_events: list[dict] = field(default_factory=list)

    # ═══════════════════════════════════════════════════════════════
    # STATE HELPERS
    # ═══════════════════════════════════════════════════════════════

    def log(self, agent: str, action: str, details: Any = None):
        """Append a traceable audit entry."""
        entry = AuditEntry(
            timestamp=datetime.now(timezone.utc).isoformat(),
            agent=agent,
            node=self.current_node,
            action=action,
            details=details,
            iteration=self.iteration
        )
        self.audit_log.append(entry)
        self.stream_events.append({
            "type": "audit",
            "agent": agent,
            "action": action,
            "details": str(details)[:200] if details else "",
            "iteration": self.iteration
        })

    def emit(self, event_type: str, content: str, agent: str = "system"):
        """Emit a UI-visible streaming event."""
        self.stream_events.append({
            "type": event_type,
            "agent": agent,
            "content": content,
            "iteration": self.iteration
        })

    def add_message(self, role: str, content: str):
        self.short_term.append({
            "role": role, "content": content,
            "iteration": self.iteration,
            "timestamp": datetime.now(timezone.utc).isoformat()
        })

    def add_reasoning(self, thought: str, action: dict, observation: Any = None):
        self.reasoning_chain.append({
            "iteration": self.iteration,
            "thought": thought,
            "action": action,
            "observation": observation
        })

    def get_confidence(self) -> float:
        """Estimate current diagnostic confidence based on available data."""
        score = 0.0
        if self.clinical_scores.get("nss_score") is not None: score += 0.2
        if self.clinical_scores.get("nds_score") is not None: score += 0.2
        if self.ml_results.get("predicted_class") is not None: score += 0.3
        if self.fusion_results.get("fusion_score") is not None: score += 0.3
        self.confidence = score
        return score

    def is_data_sufficient(self) -> bool:
        """Check if we have enough data to proceed to fusion."""
        return (
            len(self.answers) >= 8 or
            (self.clinical_scores.get("nss_score") is not None and
             self.clinical_scores.get("nds_score") is not None)
        )

    def has_ml_data(self) -> bool:
        return bool(self.ml_results.get("predicted_class") is not None)

    def has_fusion(self) -> bool:
        return bool(self.fusion_results.get("fusion_score") is not None)

    def has_ppg_payload(self) -> bool:
        payload = self.patient_info.get("ppg_payload") or self.patient_info.get("ppg")
        return isinstance(payload, dict) and bool(
            (payload.get("red") or payload.get("red_signal"))
            and (payload.get("ir") or payload.get("ir_signal"))
        )

    def to_summary(self) -> str:
        """Compact summary string for LLM context."""
        lines = [
            f"Patient: {self.patient_info.get('name')} | Age: {self.patient_info.get('age')}",
            f"Iteration: {self.iteration}/{self.max_iterations} | Confidence: {self.get_confidence():.0%}",
            f"Plan: {' → '.join(self.plan[:4])}" if self.plan else "No plan yet",
            f"Answers collected: {len(self.answers)}",
        ]
        if self.clinical_scores:
            lines.append(f"NSS: {self.clinical_scores.get('nss_score','?')}/14 | NDS: {self.clinical_scores.get('nds_score','?')}/23")
        if self.ml_results:
            lines.append(f"ML: class={self.ml_results.get('predicted_class')} prob={self.ml_results.get('predicted_probability',0):.2f}")
        if self.fusion_results:
            lines.append(f"Fusion: {self.fusion_results.get('fusion_score','?')} → {self.fusion_results.get('final_decision','?')}")
        if self.ppg_results:
            lines.append(
                "PPG: "
                f"{self.ppg_results.get('risk_level', 'N/A')} "
                f"prob={self.ppg_results.get('neuropathy_probability', 0):.2f} "
                f"quality={self.ppg_results.get('signal_quality', 'N/A')}"
            )
        if self.osteo_results:
            ml_o = self.osteo_results.get("ml_result", {})
            lines.append(f"Osteo: {ml_o.get('risk_level', 'N/A')} risk prob={ml_o.get('predicted_probability', 0):.2f}")
        if self.shoulder_results:
            ml_s = self.shoulder_results.get("ml_result", {})
            lines.append(f"Shoulder: {ml_s.get('risk_level', 'N/A')} risk prob={ml_s.get('predicted_probability', 0):.2f}")
        if self.reflections:
            last = self.reflections[-1]
            lines.append(f"Last reflection: {'OK' if last.is_consistent else 'ISSUES: ' + '; '.join(last.issues[:2])}")
        if self.long_term:
            lines.append(f"RAG memory: {len(self.long_term)} records retrieved")
        recent = self.reasoning_chain[-2:]
        if recent:
            lines.append("Recent reasoning:")
            for r in recent:
                lines.append(f"  [{r['iteration']}] {r['thought'][:100]}")
        return "\n".join(lines)
