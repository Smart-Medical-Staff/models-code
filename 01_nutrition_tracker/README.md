# Smart Nutrition Tracker

An advanced, comprehensive food logging and nutritional tracking database feature. It performs biometric calculations, maintains a local food database, computes target limits for individual meals, and provides graphical dashboards for daily macro distributions.

---

## 🩺 Biometric & Nutritional Engine

### 1. Mifflin-St Jeor BMR & TDEE Calculations
The system calculates Basal Metabolic Rate (BMR) utilizing the **Mifflin-St Jeor** equation:
* **Men**: $BMR = 10 \times \text{Weight (kg)} + 6.25 \times \text{Height (cm)} - 5 \times \text{Age (y)} + 5$
* **Women**: $BMR = 10 \times \text{Weight (kg)} + 6.25 \times \text{Height (cm)} - 5 \times \text{Age (y)} - 161$

*Note: The implementation uses standard clinical coefficients:*
* **Men BMR**: $88.36 + 13.4 \times W + 4.8 \times H - 5.7 \times A$
* **Women BMR**: $447.6 + 9.2 \times W + 3.1 \times H - 4.3 \times A$

Total Daily Energy Expenditure (TDEE) is calculated by multiplying BMR with the patient's physical activity factor:
* **Sedentary**: $\times 1.2$
* **Lightly Active**: $\times 1.375$
* **Moderately Active**: $\times 1.55$
* **Very Active**: $\times 1.725$

### 2. Goal-Based TDEE Adjustments
The system calculates the patient's Body Mass Index (BMI) and adjusts the daily calorie budget accordingly:
* **Underweight (BMI < 18.5)**: Focuses on weight gain ($\text{TDEE} + 500\text{ kcal}$).
* **Overweight (BMI $\ge$ 24.9)**: Focuses on weight loss ($\text{TDEE} - 500\text{ kcal}$).
* **Normal Weight (18.5 – 24.8)**: Focuses on maintenance ($\text{TDEE}$).

### 3. Target Calorie Limits per Meal
To ensure balanced energy intake throughout the day, the daily calorie budget is distributed as:
* **Breakfast**: $25\%$ of adjusted TDEE.
* **Lunch**: $35\%$ of adjusted TDEE.
* **Dinner**: $20\%$ of adjusted TDEE.
* **Snacks**: $20\%$ of adjusted TDEE.

### 4. Macro Splits
The target calorie budget is converted to gram values based on:
* **Carbohydrates**: $45\%$ of energy intake ($4\text{ kcal/g}$).
* **Protein**: $20\%$ of energy intake ($4\text{ kcal/g}$).
* **Fat**: $35\%$ of energy intake ($9\text{ kcal/g}$).

---

## 🛠️ Code Structure

- [nutrition_tracker.dart](file:///d:/sms.doc/models-code/01_nutrition_tracker/nutrition_tracker.dart): Core feature file containing:
  - **Models**: `FoodItem` (nutrient components per 100g), `UserProfile`, `MealEntry` (tracks grams consumed), and `DailyLog`.
  - **Food Database**: Incorporates a built-in search index of **~512 foods** (embedded in source text) and custom food registry.
  - **Storage Manager**: Persists user profiles, food lists, and logs in `shared_preferences`.
  - **Interactive UI (`NutritionTrackerScreen`)**: A dashboard featuring progress indicators, meal categorizations, search sheets, and food logging menus.
- [FINAL_VALIDATED_FOOD_DATAv1.csv](file:///d:/sms.doc/models-code/01_nutrition_tracker/FINAL_VALIDATED_FOOD_DATAv1.csv): Validated database of food items containing complete macro and micro-nutrients per 100g.

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
     MaterialPageRoute(builder: (context) => const NutritionTrackerScreen()),
   );
   ```
