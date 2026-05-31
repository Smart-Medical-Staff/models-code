# Insulin Dose Calculator & Tracker

A clinical calculation engine and tracking interface for managing insulin doses in patients with Type 1 (T1D) or Type 2 (T2D) Diabetes.

---

## 🩺 Clinical Calculations

The engine calculates a patient's insulin parameters using weight, diabetes type, and blood glucose targets.

### 1. Profile Generation (Weight-Based)
Initial insulin values are generated using clinical rules of thumb:
* **Total Daily Dose (TDD)**:
  * **Type 1 Diabetes (T1D)**: $TDD = \text{Weight (kg)} \times 0.55$
  * **Type 2 Diabetes (T2D)**: $TDD = \text{Weight (kg)} \times 0.40$
* **Basal Dose**: $50\%$ of TDD (slow-acting insulin).
* **Insulin-to-Carbohydrate Ratio (ICR)**: Calculates grams of carbs covered by $1$ unit of insulin. Uses the **Rule of 500**:
  $$ICR = \frac{500}{TDD}$$
* **Insulin Sensitivity Factor (ISF)**: Calculates the drop in blood glucose (mg/dL) per $1$ unit of insulin. Uses the **Rule of 1800**:
  $$ISF = \frac{1800}{TDD}$$
* **Target Blood Glucose**: Default is $120\text{ mg/dL}$.

### 2. Basal Adjustment & Recalculation Cascade
When a user or physician adjusts the slow-acting basal dose, the system automatically cascades recalculations to update all dependent parameters:
1. $\text{New Basal} = \text{Basal} \pm \Delta$
2. $\text{New TDD} = \text{New Basal} / 0.5$
3. $\text{New ICR} = 500 / \text{New TDD}$
4. $\text{New ISF} = 1800 / \text{New TDD}$

### 3. Bolus Calculation (Meal Dose + Correction)
To calculate quick-acting bolus insulin for a meal:
$$\text{Meal Bolus} = \frac{\text{Carbohydrates (g)}}{ICR}$$
$$\text{Correction Bolus} = \frac{\text{Current Blood Glucose} - \text{Target Blood Glucose}}{ISF} \quad (\text{only if } \text{BG} > \text{Target})$$
$$\text{Total Bolus} = \text{Meal Bolus} + \text{Correction Bolus}$$

---

## 🛠️ Code Structure

- [insulin_calculator.dart](file:///d:/sms.doc/models-code/06_insulin_calculator/insulin_calculator.dart): Core feature file containing:
  - **Clinical Models**: `UserProfile` (stores demographic and clinical ratios) and `DoseLog`/`DailyData` (stores dose events).
  - **Calculation Functions**: `buildProfileFromWeight`, `adjustBasalDose`, and `calculateBolus`.
  - **Storage Manager**: Persists user profiles under key `insulin_user_profile` and daily logs under key `insulin_daily_data` via `shared_preferences`.
  - **Dashboard & UI Widget (`InsulinCalculatorScreen`)**: A premium UI styled in dark-slate and royal blue that lets users set up profiles, track daily logs, calculate bolus doses, adjust basal doses, and view daily summaries.

---

## 🚀 How to Integrate

1. **Add Dependencies**:
   Ensure `shared_preferences` is in your Flutter project's `pubspec.yaml`:
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     shared_preferences: ^2.2.0
   ```
2. **Navigate to the Screen**:
   ```dart
   Navigator.push(
     context,
     MaterialPageRoute(builder: (context) => const InsulinCalculatorScreen()),
   );
   ```
