# Weekly Deficiency Spotter

A comprehensive 7-day nutrient analysis and diagnostic coaching module. It calculates micronutrient recommended daily intake (RDI) targets, classifies coverage into diagnostic bands, runs recurrence checks across weeks, identifies critical nutrient interactions, and alerts clinical staff when a formal specialist referral is required.

---

## 🩺 Clinical Logic & Thresholds

### 1. Recommended Daily Intake (RDI) Ratios
RDI targets are generated dynamically based on gender, age, and diabetes status for 10 micro-nutrients:

| Nutrient | Unit | Male Target | Female Target | Diabetic Adjustments |
| :--- | :--- | :--- | :--- | :--- |
| **Fiber** | g/day | $\ge 25.0$ | $\ge 25.0$ | Elevated to **$\ge 35.0\text{ g/day}$** |
| **Iron** | mg/day | $8.0$ | $18.0$ ($8.0$ if age > 50) | — |
| **Calcium** | mg/day | $1000.0$ ($1200.0$ if age > 50) | $1000.0$ ($1200.0$ if age > 50) | — |
| **Magnesium** | mg/day | $420.0$ ($400.0$ if age $\le$ 30) | $320.0$ ($310.0$ if age $\le$ 30) | — |
| **Zinc** | mg/day | $11.0$ | $8.0$ | — |
| **Potassium** | mg/day | $3400.0$ | $2600.0$ | — |
| **Vitamin C** | mg/day | $90.0$ | $75.0$ | — |
| **Vitamin D** | mcg/day | $15.0$ ($20.0$ if age > 70) | $15.0$ ($20.0$ if age > 70) | — |
| **Vitamin B12** | mcg/day | $2.4$ | $2.4$ | — |
| **Folate** | mcg/day | $400.0$ | $400.0$ | — |

*Diabetic patients have elevated fiber needs to help slow glucose absorption and prevent postprandial spikes.*

### 2. Coverage Band Classification
For each nutrient, actual daily average intake (Total intake over 7 days / days logged) is compared to the RDI target:

* **Adequate ($\ge 85\%$)**: Green theme (`#43A047`).
* **Marginal ($60\% - 84\%$)**: Orange theme (`#FB8C00`).
* **Deficient ($35\% - 59\%$)**: Red theme (`#E53935`).
* **Severely Deficient ($< 35\%$)**: Dark Red theme (`#B71C1C`).

### 3. Recurrence Detection
The service queries the database for the previous week's spotter report. If a nutrient was deficient or severely deficient last week and remains deficient this week, it is flagged as **Recurring**.

### 4. Nutrient Interaction Check
The system flags interactive biochemical relationships:
* **Iron + Vitamin C**: Vitamin C enhances iron absorption; co-deficiency worsens symptoms.
* **Calcium + Vitamin D**: Vitamin D is necessary for calcium absorption; co-deficiency accelerates bone loss.
* **Magnesium + Diabetes**: Magnesium deficiency exacerbates insulin resistance.
* **Metformin + Vitamin B12**: Metformin depletes Vitamin B12; requires monitoring to prevent neuropathy.
* **ACE Inhibitors / Diuretics + Potassium**: Relates potassium levels to medication management.

### 5. Specialist Referral Trigger (Medical Referral Banner)
A doctor referral warning is triggered (`referralFlag = true`) under either clinical condition:
1. **Severe Gaps**: The patient is severely deficient ($<35\%$ RDI) in **$\ge 2$** nutrients.
2. **Persistent Gaps**: The patient has **$\ge 2$** recurring deficiencies.

---

## 🛠️ Code Structure

- [weekly_deficiency_spotter_service.dart](file:///d:/sms.doc/models-code/04_weekly_coach/weekly_deficiency_spotter_service.dart): Core engine running the weekly clinical analysis and mapping suggestions.
- [weekly_deficiency_spotter_page.dart](file:///d:/sms.doc/models-code/04_weekly_coach/weekly_deficiency_spotter_page.dart): A Flutter dashboard card UI displaying:
  - Weekly overall summary.
  - Interactive grid showing coverage levels and bands for all 10 nutrients.
  - Actionable deficiency cards with clinical impact statements and suggested foods.
  - Interlocking biochemical interaction banners.
  - Highlighted medical referral warnings.

---

## 🚀 How to Integrate

1. **Required Shared Services**:
   This module integrates with the following shared app services (relative to the feature directory):
   - `../../patient/diseases/diet_plan/models/daily_log.dart`
   - `../../patient/diseases/diet_plan/models/meal_entry.dart`
   - `../../patient/diseases/diet_plan/services/diet_storage_service.dart`
   - `../../services/patient_profile_service.dart`

2. **Displaying the Page**:
   Simply navigate to or include the `WeeklyDeficiencySpotterPage` in your weekly report tab:
   ```dart
   const WeeklyDeficiencySpotterPage()
   ```
