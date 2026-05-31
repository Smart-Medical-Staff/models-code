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
└── 06_insulin_calculator/      # Weight-based profile build & dose calculator
    └── insulin_calculator.dart
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
