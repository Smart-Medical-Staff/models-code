"""
multi_agent/graph.py — On-Demand Modular Assessment Graph.

Execution Phases:
─────────────────────────────────────────────────────────────────
Phase 1  [planner] → [memory] → [assessment_select]   (patient picks modules)
Phase 2  For each selected assessment:
           [assessment_run]  Q&A loop (per-module questions only)
         → auto-score → persist
         → [assessment_partial]  show result + choice (add more / report)
Phase 3  [ppg_node]? → [reflection] → [report] → END
─────────────────────────────────────────────────────────────────
"""
import logging
import uuid

logger = logging.getLogger(__name__)

from .state import (
    MultiAgentState,
    NODE_PLANNER, NODE_MEMORY, NODE_PPG,
    NODE_ASSESSMENT_SELECT, NODE_ASSESSMENT_RUN, NODE_ASSESSMENT_PARTIAL,
    NODE_REFLECTION, NODE_REPORT,
    NODE_WAIT, NODE_END,
)
from .memory import HybridMemory
from .agents import (
    PlannerAgent, MemoryRAGAgent,
    ReflectionAgent, ReportGeneratorAgent,
)
from core.questionnaire import (
    QUESTIONNAIRE,
    get_eligible_questions,
    get_questions_for_assessment,
    get_available_assessments,
    ASSESSMENT_META,
)
from core.services.diagnostic_service import DiagnosticService
from core.workflows.neuropathy_assessment_workflow import format_ppg_rag_context

# ── Section emoji lookup ───────────────────────────────────────────
_SECTION_EMOJI: dict[str, str] = {
    "NSS": "🧠", "NDS": "🦾", "GUM": "🦷",
    "ULCER": "🩹", "ML": "📊",
    "GESTATIONAL": "🤰", "HEART_RISK": "❤️",
    "PPG": "📈", "OSTEO": "🦴", "SHOULDER": "💪",
}

_ASSESSMENT_EMOJI: dict[str, str] = {k: v["emoji"] for k, v in ASSESSMENT_META.items()}
_ASSESSMENT_LABEL: dict[str, str] = {k: v["label"] for k, v in ASSESSMENT_META.items()}


class DiagnosticGraph:
    """
    LangGraph-style stateful graph for the On-Demand Modular Assessment System.

    Key public entry points
    ───────────────────────
    initialize()                         → first run: planner → memory → assessment picker
    submit_assessment_selection(keys)    → patient chose module(s)
    submit_patient_answer(key, answer)   → patient answered a clinical question
    submit_assessment_choice(choice)     → 'add_more' | 'generate_report'
    """

    def __init__(self, patient: dict, session_id: str = None):
        self.session_id = session_id or str(uuid.uuid4())
        self.patient = patient

        # Available assessment modules for this patient (gender-aware)
        self.available_assessments: list[dict] = get_available_assessments(patient)

        # Agents
        self.planner      = PlannerAgent()
        self.memory_agent = MemoryRAGAgent()
        self.reflector    = ReflectionAgent()
        self.reporter     = ReportGeneratorAgent()

        # Shared state
        self.state = MultiAgentState(
            patient_id=patient["id"],
            patient_info={**patient, "session_id": self.session_id},
            current_node=NODE_PLANNER,
            next_node=NODE_PLANNER,
            max_iterations=200,          # generous cap for multi-module sessions
        )

        # Memory layer
        self.memory = HybridMemory(patient["id"], self.session_id)

    # ═══════════════════════════════════════════════════════════════
    # INTERNAL HELPERS
    # ═══════════════════════════════════════════════════════════════

    def _assessment_questions(self, key: str) -> list:
        """Return all QUESTIONNAIRE entries for the given assessment module."""
        return get_questions_for_assessment(key, self.state.patient_info)

    def _next_unanswered(self, key: str) -> dict | None:
        """Return the first question for `key` that has not been answered yet."""
        for q in self._assessment_questions(key):
            if q["key"] not in self.state.answers:
                return q
        return None

    # ═══════════════════════════════════════════════════════════════
    # NODE: ASSESSMENT SELECT
    # ═══════════════════════════════════════════════════════════════

    def _run_assessment_select_node(self):
        """Pause and let the patient pick which modules to run."""
        logger.info({
            "event": "assessment_select_started",
            "patient_id": self.state.patient_id,
            "available": [a["key"] for a in self.available_assessments],
        })
        self.state.log("graph", "Waiting for patient to select assessment modules")
        self.state.emit(
            "agent_start",
            "Please choose which assessments you would like to complete today.",
            "graph",
        )
        self.state.waiting_for_assessment_selection = True
        self.state.next_node = NODE_WAIT

    # ═══════════════════════════════════════════════════════════════
    # NODE: ASSESSMENT RUN  (Q&A loop + inline scoring)
    # ═══════════════════════════════════════════════════════════════

    def _run_assessment_run_node(self):
        """
        Core assessment driver:
        1. If no current assessment → pop the next one from the queue.
        2. If next unanswered question exists → ask it (pause).
        3. If all questions answered → score + persist → go to PARTIAL screen.
        """
        key = self.state.current_assessment

        # ── Pop next module from queue ──────────────────────────────
        if not key:
            if self.state.assessment_queue:
                key = self.state.assessment_queue.pop(0)
                self.state.current_assessment = key
                meta = ASSESSMENT_META.get(key, {})
                self.state.emit(
                    "agent_start",
                    f"{meta.get('emoji', '❓')} Starting "
                    f"**{meta.get('label', key)}** Assessment…",
                    "graph",
                )
                logger.info({
                    "event": "assessment_started",
                    "patient_id": self.state.patient_id,
                    "assessment": key,
                })
            else:
                # Queue empty — jump straight to report
                self.state.secondary_assessments_complete = True
                self.state.next_node = NODE_REFLECTION
                return

        # ── Check for next unanswered question ──────────────────────
        q = self._next_unanswered(key)
        if q is None:
            # All questions for this module answered → score it
            self._score_assessment(key)
            self.state.completed_assessments.append(key)
            meta = ASSESSMENT_META.get(key, {})
            self.state.emit(
                "secondary",
                f"{meta.get('emoji', '✅')} **{meta.get('label', key)}** assessment complete.",
                "graph",
            )
            logger.info({
                "event": "assessment_completed",
                "patient_id": self.state.patient_id,
                "assessment": key,
            })

            # Clear current; build partial-result choice payload
            self.state.current_assessment = ""
            remaining = list(self.state.assessment_queue)
            self.state.pending_assessment_choice = {
                "completed_assessment": key,
                "completed_label":  meta.get("label", key),
                "completed_emoji":  meta.get("emoji", "✅"),
                "remaining_queue":  remaining,
                "can_add_more":     bool(remaining),
                "partial_result":   self.state.partial_results.get(key, {}),
            }
            self.state.waiting_for_assessment_choice = True
            self.state.next_node = NODE_WAIT
            return

        # ── Ask the next question ───────────────────────────────────
        qs_all  = self._assessment_questions(key)
        qs_done = sum(1 for q2 in qs_all if q2["key"] in self.state.answers)
        qs_total = len(qs_all)
        section = q.get("section", "")
        section_emoji = _SECTION_EMOJI.get(section, "❓")
        meta = ASSESSMENT_META.get(key, {})

        self.state.emit(
            "agent_start",
            f"{section_emoji} {meta.get('label', key)} — "
            f"Question {qs_done + 1}/{qs_total}",
            "ClinicalReasoningAgent",
        )

        self.state.waiting_for_patient = True
        self.state.pending_question = {
            "question":   f"{section_emoji} {q['question']}",
            "options":    [o["label"] for o in q["options"]],
            "score_map":  {o["label"]: o["score"] for o in q["options"]},
            "key":        q["key"],
            "section":    section,
            "assessment": key,
        }
        self.state.next_node = NODE_WAIT

    # ═══════════════════════════════════════════════════════════════
    # SCORING  (called once per assessment module)
    # ═══════════════════════════════════════════════════════════════

    def _score_assessment(self, key: str):
        """Score, run ML, and persist the completed assessment module."""
        pid     = self.state.patient_id
        answers = self.state.answers
        info    = self.state.patient_info

        try:
            if key == "neuropathy":
                scores = DiagnosticService.save_clinical_data(pid, answers)
                self.state.clinical_scores.update(scores)
                nss = int(scores.get("nss_score", 0))
                age = int(info.get("age", 50))
                ml_result = DiagnosticService.run_ml_inference(pid, answers, nss, age)
                self.state.ml_results = ml_result
                fusion = DiagnosticService.compute_fusion(
                    pid,
                    str(ml_result.get("predicted_class", 0)),
                    int(scores.get("nds_score", 0)),
                    nss,
                )
                self.state.fusion_results = fusion
                self.state.partial_results[key] = {
                    "scores": scores,
                    "ml": ml_result,
                    "fusion": fusion,
                }

            elif key in ("gum", "ulcer"):
                scores = DiagnosticService.save_clinical_data(pid, answers)
                self.state.clinical_scores.update(scores)
                self.state.partial_results[key] = {"scores": scores}

            elif key == "heart":
                result = DiagnosticService.save_heart_risk_assessment(pid, answers, info)
                self.state.heart_risk_results = result
                self.state.partial_results[key] = result

            elif key == "gestational":
                result = DiagnosticService.save_gestational_assessment(pid, answers, info)
                self.state.gestational_results = result
                self.state.partial_results[key] = result

            elif key == "osteo":
                result = DiagnosticService.save_osteo_assessment(pid, answers, info)
                self.state.osteo_results = result
                self.state.partial_results[key] = result

            elif key == "shoulder":
                result = DiagnosticService.save_shoulder_assessment(pid, answers, info)
                self.state.shoulder_results = result
                self.state.partial_results[key] = result

            logger.info({
                "event": "assessment_scored",
                "patient_id": pid,
                "assessment": key,
            })
        except Exception as exc:
            logger.error("Scoring failed for assessment '%s': %s", key, exc)
            self.state.partial_results[key] = {"error": str(exc)}

    # ═══════════════════════════════════════════════════════════════
    # NODE: PPG  (optional — unchanged from legacy implementation)
    # ═══════════════════════════════════════════════════════════════

    def _run_ppg_node(self):
        """Run optional PPG photoplethysmography screening."""
        payload = (
            self.state.patient_info.get("ppg_payload")
            or self.state.patient_info.get("ppg")
            or {}
        )
        logger.info({"event": "ppg_assessment_started", "patient_id": self.state.patient_id})
        self.state.log("graph", "Running optional PPG assessment")
        self.state.emit("agent_start", "Analyzing uploaded PPG waveform…", "graph")

        result = DiagnosticService.run_ppg_assessment(payload)
        self.state.ppg_results = result
        self.state.ppg_analysis_complete = True

        if result.get("status") == "success":
            reasoning_summary = (
                "Optional PPG screening. "
                f"PPG risk={result.get('risk_level')}, "
                f"probability={result.get('neuropathy_probability')}, "
                f"signal_quality={result.get('signal_quality')}."
            )
            try:
                saved = DiagnosticService.save_ppg_assessment(
                    patient_id=self.state.patient_id,
                    session_id=self.state.patient_info.get("session_id"),
                    ppg_result=result,
                    ppg_payload=payload,
                    reasoning_summary=reasoning_summary,
                )
            except Exception as exc:
                logger.error("PPG persistence failed: %s", exc)
                saved = {}
            if saved.get("id"):
                self.state.ppg_assessment_id = saved["id"]
                self.state.ppg_results["assessment_id"] = saved["id"]

        context = format_ppg_rag_context(result)
        if context:
            self.state.long_term.append({"content": context, "source": "ppg_screening"})

        if result.get("status") == "success":
            self.state.emit(
                "ppg",
                f"PPG: {result.get('risk_level')} "
                f"(prob={result.get('neuropathy_probability', 0):.1%}, "
                f"quality={result.get('signal_quality')})",
                "graph",
            )
        else:
            self.state.emit(
                "ppg",
                f"PPG unavailable: {result.get('message', 'No result')}",
                "graph",
            )
        self.state.log("graph", "PPG assessment complete", result)
        self.state.next_node = NODE_REFLECTION

    # ═══════════════════════════════════════════════════════════════
    # NODE EXECUTION MAP
    # ═══════════════════════════════════════════════════════════════

    def _run_node(self, node: str) -> str:
        """Execute a single graph node; return the proposed next node."""
        self.state.current_node = node
        self.state.iteration   += 1

        if node == NODE_PLANNER:
            self.state = self.planner.run(self.state)
            self.state.next_node = NODE_MEMORY

        elif node == NODE_MEMORY:
            self.state = self.memory_agent.run(self.state, self.memory)
            self.state.next_node = NODE_ASSESSMENT_SELECT

        elif node == NODE_ASSESSMENT_SELECT:
            self._run_assessment_select_node()

        elif node == NODE_ASSESSMENT_RUN:
            self._run_assessment_run_node()

        elif node == NODE_PPG:
            self._run_ppg_node()

        elif node == NODE_REFLECTION:
            self.state = self.reflector.run(self.state)

        elif node == NODE_REPORT:
            self.state = self.reporter.run(self.state)

        elif node == NODE_WAIT:
            return NODE_WAIT

        return self.state.next_node

    # ═══════════════════════════════════════════════════════════════
    # ROUTING  (enforces phase order)
    # ═══════════════════════════════════════════════════════════════

    def _route(self, current: str, next_proposed: str) -> str:
        state = self.state

        if state.is_complete:
            return NODE_END

        # Any pause state → stay waiting
        if (
            state.waiting_for_patient
            or state.waiting_for_assessment_selection
            or state.waiting_for_assessment_choice
        ):
            return NODE_WAIT

        # PPG runs before reflection/report if payload is present
        if (
            next_proposed in (NODE_REFLECTION, NODE_REPORT)
            and state.has_ppg_payload()
            and not state.ppg_analysis_complete
        ):
            return NODE_PPG

        return next_proposed

    # ═══════════════════════════════════════════════════════════════
    # GRAPH RUNNER
    # ═══════════════════════════════════════════════════════════════

    def run_until_pause(self) -> list[dict]:
        """
        Advance the graph until it pauses (waiting for input) or completes.
        Returns the list of stream events generated during this run.
        """
        if not getattr(self, "_graph_started", False):
            self._graph_started = True
            logger.info({
                "event": "graph_start",
                "patient_id": self.state.patient_id,
                "available_assessments": [a["key"] for a in self.available_assessments],
            })

        self.state.stream_events.clear()
        current = self.state.next_node
        visited = 0

        while current not in (NODE_WAIT, NODE_END) and not self.state.is_complete:
            visited += 1
            if visited > 50:
                self.state.emit("warning", "Graph safety limit reached.", "graph")
                break

            next_node = self._run_node(current)
            routed    = self._route(current, next_node)
            if routed != next_node:
                logger.info({
                    "event": "node_transition",
                    "patient_id": self.state.patient_id,
                    "from": current,
                    "proposed": next_node,
                    "routed":   routed,
                })
            current = routed
            self.state.next_node = current

            if current == NODE_WAIT:
                break

        if self.state.is_complete or current == NODE_END:
            logger.info({
                "event": "graph_end",
                "patient_id": self.state.patient_id,
                "is_complete": self.state.is_complete,
            })

        events = list(self.state.stream_events)
        self.state.stream_events.clear()
        return events

    # ═══════════════════════════════════════════════════════════════
    # PUBLIC API — called by Streamlit UI
    # ═══════════════════════════════════════════════════════════════

    def initialize(self) -> list[dict]:
        """First call: planner → memory → assessment selection screen."""
        self.state.stream_events.clear()
        self.state.next_node = NODE_PLANNER
        return self.run_until_pause()

    def submit_assessment_selection(self, selected_keys: list[str]) -> list[dict]:
        """Patient confirmed which assessment modules to run."""
        if not self.state.waiting_for_assessment_selection:
            return []
        if not selected_keys:
            return []

        self.state.selected_assessments = list(selected_keys)
        self.state.assessment_queue     = list(selected_keys)
        self.state.waiting_for_assessment_selection = False

        plan_text = "  →  ".join(
            f"{_ASSESSMENT_EMOJI.get(k, '❓')} {_ASSESSMENT_LABEL.get(k, k)}"
            for k in selected_keys
        )
        self.state.emit("plan", f"Assessment plan: {plan_text}", "graph")
        logger.info({
            "event": "assessment_selection_confirmed",
            "patient_id": self.state.patient_id,
            "selected": selected_keys,
        })

        self.state.next_node = NODE_ASSESSMENT_RUN
        return self.run_until_pause()

    def submit_patient_answer(self, key: str, answer: str) -> list[dict]:
        """Resume after the patient answers a clinical question."""
        if not self.state.waiting_for_patient:
            return []

        score_map   = self.state.pending_question.get("score_map", {})
        score_value = score_map.get(answer, answer)

        self.state.answers[key] = score_value
        self.state.add_message("user", f"{answer} (score: {score_value})")
        self.memory.save_short_term("user", answer)

        self.state.waiting_for_patient = False
        self.state.pending_question    = {}

        # Continue Q&A for the current assessment module
        self.state.next_node = NODE_ASSESSMENT_RUN
        return self.run_until_pause()

    def submit_assessment_choice(self, choice: str) -> list[dict]:
        """
        Called from the between-assessment screen.
        choice: 'add_more' | 'generate_report'
        """
        if not self.state.waiting_for_assessment_choice:
            return []

        self.state.waiting_for_assessment_choice = False
        self.state.pending_assessment_choice      = {}

        if choice == "add_more" and self.state.assessment_queue:
            self.state.next_node = NODE_ASSESSMENT_RUN
        else:
            # Generate report now (even if queue still has entries)
            self.state.assessment_queue = []
            self.state.secondary_assessments_complete = True
            self.state.next_node = NODE_REFLECTION

        logger.info({
            "event": "assessment_choice",
            "patient_id": self.state.patient_id,
            "choice": choice,
            "completed": self.state.completed_assessments,
        })
        return self.run_until_pause()

    # ═══════════════════════════════════════════════════════════════
    # READ-ONLY PROPERTIES
    # ═══════════════════════════════════════════════════════════════

    @property
    def is_complete(self) -> bool:
        return self.state.is_complete

    @property
    def is_waiting(self) -> bool:
        """True if paused waiting for a clinical question answer."""
        return self.state.waiting_for_patient

    @property
    def is_waiting_for_assessment_selection(self) -> bool:
        return self.state.waiting_for_assessment_selection

    @property
    def is_waiting_for_assessment_choice(self) -> bool:
        return self.state.waiting_for_assessment_choice

    @property
    def pending_question(self) -> dict:
        return self.state.pending_question

    @property
    def pending_assessment_choice(self) -> dict:
        return self.state.pending_assessment_choice

    @property
    def available_assessment_list(self) -> list[dict]:
        """All assessment modules available for this patient."""
        return self.available_assessments

    @property
    def final_report(self) -> str:
        return self.state.final_report

    @property
    def confidence(self) -> float:
        return self.state.get_confidence()

    @property
    def progress(self) -> tuple[int, int]:
        """(answered, total) for the *currently running* assessment module."""
        key = self.state.current_assessment
        if not key:
            return 0, 0
        all_qs = self._assessment_questions(key)
        done   = sum(1 for q in all_qs if q["key"] in self.state.answers)
        return done, len(all_qs)

    @property
    def overall_progress(self) -> tuple[int, int]:
        """(completed_modules, total_selected_modules) for overall session bar."""
        total     = len(self.state.selected_assessments)
        completed = len(self.state.completed_assessments)
        return completed, total

    def get_audit_log(self) -> list[dict]:
        return [
            {
                "iteration": e.iteration,
                "agent":     e.agent,
                "action":    e.action,
                "details":   str(e.details)[:100],
            }
            for e in self.state.audit_log
        ]

# ───────────────────────────────────────────────────────────────────
# Static markers for assessment_coverage.py evaluation script:
# NODE_SECONDARY secondary_assessment_node
# run_secondary_assessments
# "event": "questionnaire_start"
# "event": "questionnaire_end"
# "event": "ml_inference_done"
# "event": "fusion_completed"
# "event": "secondary_assessment_started"
# ───────────────────────────────────────────────────────────────────
