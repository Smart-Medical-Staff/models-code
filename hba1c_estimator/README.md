# HbA1c Estimator

A Flutter widget and clinical logic engine that estimates a patient's Glycated Hemoglobin (HbA1c) level from a historical series of blood glucose readings.

---

## 🩺 Clinical Logic & Formula

HbA1c represents the average blood glucose level over the past 2 to 3 months. This widget uses the standard clinical linear regression formula to estimate HbA1c (%) from the Mean Blood Glucose (MBG) in mg/dL:

$$\text{Estimated HbA1c (\%)} = \frac{\text{MBG} + 46.7}{28.7}$$

### Clinical Interpretation (ADA Guidelines)
Estimated HbA1c values are categorized according to the American Diabetes Association (ADA) guidelines:

| HbA1c Range | Classification | Theme Color | Clinical Meaning |
| :--- | :--- | :--- | :--- |
| **< 5.7%** | Normal | Green (`#16A34A`) | Blood sugar levels are in the healthy non-diabetic range. |
| **5.7% – 6.4%** | Prediabetes | Orange (`#F59E0B`) | Indicates high risk of developing diabetes; lifestyle changes recommended. |
| **≥ 6.5%** | Diabetes | Red (`#DC2626`) | Diagnostic threshold for Diabetes; requires clinical management. |

---

## 🛠️ Code Structure

- [hba1c_estimator.dart](file:///d:/sms.doc/models-code/hba1c_estimator/hba1c_estimator.dart): Core feature file containing:
  - **Clinical Helper Functions**: `mbgToHbA1c` and `interpretHbA1c`.
  - **Data Persistence**: Uses `shared_preferences` to persist glucose readings locally as a JSON string under the key `hba1c_glucose_readings`.
  - **UI Widget (`HbA1cEstimatorScreen`)**: A modern, clean, responsive Flutter page styled with Slate/Slate-900 typography, featuring a dashboard showing estimated HbA1c, interpretation tags, a glucose entry input field, validation rules, and an entry history log.
- [hba1c_estimator_test.dart](file:///d:/sms.doc/models-code/hba1c_estimator/hba1c_estimator_test.dart): Self-contained unit tests asserting mathematical precision and ADA categorization correctness.

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
   Push `HbA1cEstimatorScreen` from any navigator event:
   ```dart
   Navigator.push(
     context,
     MaterialPageRoute(builder: (context) => const HbA1cEstimatorScreen()),
   );
   ```

---

## 🧪 Verification

To run unit tests:
```bash
dart run hba1c_estimator/hba1c_estimator_test.dart
```
