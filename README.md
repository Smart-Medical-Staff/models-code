# Smart Medical Staff — Feature Models & Services

This repository contains the clinical logic engines, data models, and patient-facing Flutter user interfaces for the core features used in our medical and nutritional management application.

---

## 📂 Repository Structure

The repository is organized into distinct feature modules, ordered sequentially:

```
models-code/
├── 01_nutrition_tracker/      # Food logging, custom food builder, & search
│   ├── FINAL_VALIDATED_FOOD_DATAv1.csv
│   └── nutrition_tracker.dart
├── 02_nutrition agent/        # Conversational food suitability checker
│   ├── models/
│   │   └── food_response_model.dart
│   ├── nutritionist_agent_page.dart
│   └── nutritionist_service.dart
├── 03_daily_coach/            # Daily coach narrative & target comparison
│   ├── daily_nutrition_coach_page.dart
│   └── daily_nutrition_coach_service.dart
├── 04_weekly_coach/           # 7-day RDI scanner & deficiency spotter
│   ├── weekly_deficiency_spotter_page.dart
│   └── weekly_deficiency_spotter_service.dart
├── 05_hba1c_estimator/        # HbA1c Estimator Screen & logic
│   └── hba1c_estimator.dart
├── 06_insulin_calculator/     # Weight-based profile build & dose calculator
│   └── insulin_calculator.dart
├── 07_neuropathy/             # Diabetic neuropathy clinical & ML scoring notebooks
│   ├── NDS(1).ipynb
│   ├── NSS.ipynb
│   ├── diabetic neuropathy(90)code.ipynb
│   └── final_decision.ipynb
├── 08_gingivitis/             # Gum health diagnostic & clinical simulator notebook
│   └── Gingivitis.ipynb
└──  09_multi_agent_rag/          # Clinical reasoning, RAG, orchestration & AI diagnostics
    ├── requirements.txt
    │
    ├── core/
    │   ├── questionnaire.py
    │   ├── rag_engine.py
    │   ├── tools.py
    │   ├── database/
    │   ├── repositories/
    │   ├── services/
    │   ├── workflows/
    │   ├── schemas/
    │   ├── models/
    │   └── utils/
    │
    ├── database/
    │   ├── schema.sql
    │   └── supabase/
    │
    ├── multi_agent/
    │   ├── agents.py
    │   ├── graph.py
    │   ├── memory.py
    │   ├── state.py
    │   ├── runtime_guard.py
    │   └── runtime_health.py
    │
    └── tools/
        ├── ppg_tool.py
        └── signal_quality_tool.py
```

---

## 🌟 Feature Overview

### 1. [Smart Nutrition Tracker](file:///d:/sms.doc/models-code/01_nutrition_tracker/README.md)
* **Clinical Purpose**: Integrates a local searchable food database of 500+ items and a master CSV database, tracks customized daily meal logs across Breakfast/Lunch/Dinner/Snacks, allocates target calorie budgets to individual meals, and provides full biometric BMR dashboards.

### 2. [Nutritionist Agent](file:///d:/sms.doc/models-code/02_nutrition%20agent/README.md)
* **Clinical Purpose**: High-fidelity bilingual chat interface connecting to an LLM-powered assistant (Llama 3.3 70B worker proxy) that evaluates individual food items and gives instant suitability guidance along with direct clinical app actions (Add to plan, Save log, Ask doctor).

### 3. [Daily Nutrition Coach](file:///d:/sms.doc/models-code/03_daily_coach/README.md)
* **Clinical Purpose**: Evaluates daily macronutrient intake against personal targets (Mifflin-St Jeor TDEE adjusted for weight targets), highlights deviations $>15\%$, traces deviations to a specific meal/food, and writes a narrative 4-sentence coaching report advising portions or food swaps.

### 4. [Weekly Deficiency Spotter](file:///d:/sms.doc/models-code/04_weekly_coach/README.md)
* **Clinical Purpose**: Runs 7-day nutritional scans for 10 micro-nutrients (adjusting targets for diabetic needs and demographics), maps deficiency severity bands, highlights biochemical interactions, tracks recurring gaps across weeks, and flags doctor referrals if severe or persistent gaps exist.

### 5. [HbA1c Estimator](file:///d:/sms.doc/models-code/05_hba1c_estimator/README.md)
* **Clinical Purpose**: Estimates the patient's HbA1c (Glycated Hemoglobin) level using a standard regression formula on a series of historical blood glucose readings.
* **ADA Classification**: Normal ($<5.7\%$), Prediabetes ($5.7\% - 6.4\%$), and Diabetes ($\ge 6.5\%$).

### 6. [Insulin Dose Calculator & Tracker](file:///d:/sms.doc/models-code/06_insulin_calculator/README.md)
* **Clinical Purpose**: Automatically generates a diabetic profile (TDD, ICR, ISF) based on weight and diabetes type, recalculates all parameters dynamically upon basal dose adjustment, and calculates quick-acting bolus insulin for meals and glucose corrections.

### 7. [Diabetic Neuropathy Assessment](file:///d:/sms.doc/models-code/07_neuropathy/README.md)
* **Clinical Purpose**: Assesses Painful Diabetic Neuropathy (PDN) by calculating patient-reported symptoms (NSS questionnaire) and physical examination scores (NDS sensory/motor examination), and applies a weighted voting model combined with a Random Forest Classifier to provide a final diagnostic verdict.

### 8. [Virtual Gum Health Analyzer](file:///d:/sms.doc/models-code/08_gingivitis/README.md)
* **Clinical Purpose**: Evaluates patient gum health based on standard periodontal indicators (gingival color, bleeding slider, edema, and tartar deposits) plus halitosis and smoking statuses, computing a weighted severity score and generating custom clinical recommendations.

### 9. [Multi-Agent RAG Orchestration](file:///d:/sms.doc/models-code/09_Multi_Agent_RAG/README.md)
* **Clinical Purpose**: Provides a centralized AI reasoning framework that combines Retrieval-Augmented Generation (RAG), multi-agent orchestration, clinical workflows, patient memory, and machine-learning diagnostic services. The platform coordinates disease screening, risk stratification, signal analysis, and personalized clinical guidance across multiple medical domains while maintaining explainability and auditability.
