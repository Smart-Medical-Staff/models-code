import '../../patient/diseases/diet_plan/models/daily_log.dart';
import '../../patient/diseases/diet_plan/models/meal_entry.dart';
import '../../patient/diseases/diet_plan/services/diet_calculator.dart';
import '../../services/patient_profile_service.dart';

/// Output model for the Daily Nutrition Coach agent.
class CoachResult {
  final String patientId;
  final String date;
  final String patientName;
  final PrimaryDeviation? primaryDeviation;
  final SwapSuggestion? suggestion;
  final PositiveNote positiveNote;
  final String message;
  final DailySummary summary;

  const CoachResult({
    required this.patientId,
    required this.date,
    required this.patientName,
    required this.primaryDeviation,
    required this.suggestion,
    required this.positiveNote,
    required this.message,
    required this.summary,
  });
}

class DailySummary {
  final double actualCalories;
  final double targetCalories;
  final double actualCarbs;
  final double targetCarbs;
  final double actualProtein;
  final double targetProtein;
  final double actualFat;
  final double targetFat;

  const DailySummary({
    required this.actualCalories,
    required this.targetCalories,
    required this.actualCarbs,
    required this.targetCarbs,
    required this.actualProtein,
    required this.targetProtein,
    required this.actualFat,
    required this.targetFat,
  });
}

class PrimaryDeviation {
  final String macro; // "calories", "carbohydrates", "protein", "fat"
  final double actualValue;
  final double targetValue;
  final double deltaPercent; // positive = over, negative = under
  final String responsibleMeal;
  final String responsibleFood;

  const PrimaryDeviation({
    required this.macro,
    required this.actualValue,
    required this.targetValue,
    required this.deltaPercent,
    required this.responsibleMeal,
    required this.responsibleFood,
  });
}

class SwapSuggestion {
  final String swapFrom;
  final String swapTo;
  final String rationale;

  const SwapSuggestion({
    required this.swapFrom,
    required this.swapTo,
    required this.rationale,
  });
}

class PositiveNote {
  final String macro; // The macro they did well on
  final String text;

  const PositiveNote({required this.macro, required this.text});
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily Nutrition Coach Service
// ─────────────────────────────────────────────────────────────────────────────

class DailyNutritionCoachService {
  static const double _deviationThreshold = 0.15; // 15%

  /// Run the full coaching pipeline.
  /// Returns null if insufficient data (no meals logged).
  static Future<CoachResult?> evaluate({
    required DailyLog dailyLog,
    List<DailyLog>? recentLogs, // Last 30 days for food history
  }) async {
    // ── Gate: need at least 1 meal entry ───────────────────────────────
    if (dailyLog.entries.isEmpty) return null;

    // ── Load patient profile ─────────────────────────────────────────────
    final profile = await PatientProfileService.instance.load();
    if (!profile.hasDietData) return null;

    final weight = profile.weight!;
    final height = profile.height!;
    final age = profile.age!;
    final gender = profile.gender.toLowerCase();
    final activity = profile.activityLevel;

    // ── Compute personal targets ─────────────────────────────────────────
    final bmi = DietCalculator.bmi(weightKg: weight, heightCm: height);
    final tdee = DietCalculator.tdee(
      weightKg: weight,
      heightCm: height,
      age: age,
      gender: gender,
      activity: activity,
    );
    final adjTdee = DietCalculator.adjustedTdee(tdee: tdee, bmi: bmi);

    final targetCals = adjTdee;
    final targetCarbs = DietCalculator.targetCarbs(adjTdee.round()).toDouble();
    final targetProtein = DietCalculator.targetProtein(adjTdee.round()).toDouble();
    final targetFat = DietCalculator.targetFat(adjTdee.round()).toDouble();

    // ── Step 1: Aggregate daily totals ───────────────────────────────────
    final entries = dailyLog.entries;
    final actualCals = DietCalculator.totalCalories(entries);
    final actualCarbs = DietCalculator.totalCarbs(entries);
    final actualProtein = DietCalculator.totalProtein(entries);
    final actualFat = DietCalculator.totalFat(entries);

    final summary = DailySummary(
      actualCalories: actualCals,
      targetCalories: targetCals,
      actualCarbs: actualCarbs,
      targetCarbs: targetCarbs,
      actualProtein: actualProtein,
      targetProtein: targetProtein,
      actualFat: actualFat,
      targetFat: targetFat,
    );

    // ── Step 2: Compare against targets ──────────────────────────────────
    final deviations = <String, double>{
      'calories': _deltaPct(actualCals, targetCals),
      'carbohydrates': _deltaPct(actualCarbs, targetCarbs),
      'protein': _deltaPct(actualProtein, targetProtein),
      'fat': _deltaPct(actualFat, targetFat),
    };

    // ── Step 3: Find primary deviation (largest absolute %) ──────────────
    String? primaryMacro;
    double maxAbsDelta = 0;
    for (final entry in deviations.entries) {
      final absDelta = entry.value.abs();
      if (absDelta > _deviationThreshold && absDelta > maxAbsDelta) {
        primaryMacro = entry.key;
        maxAbsDelta = absDelta;
      }
    }

    // ── Step 7: Find a positive reinforcement ────────────────────────────
    final positiveNote = _findPositiveNote(deviations, entries);

    // ── No significant deviation — good day! ─────────────────────────────
    if (primaryMacro == null) {
      final name = profile.firstName.isNotEmpty ? profile.firstName : 'there';
      return CoachResult(
        patientId: '',
        date: dailyLog.date,
        patientName: name,
        primaryDeviation: null,
        suggestion: null,
        positiveNote: positiveNote,
        summary: summary,
        message: '${positiveNote.text} All your macros are within a healthy '
            'range today — great job! Keep up the consistency tomorrow.',
      );
    }

    // ── Step 4: Trace deviation to a specific meal ───────────────────────
    final deviation = _traceToMeal(primaryMacro, deviations[primaryMacro]!, entries);

    // ── Step 5: Generate swap suggestion ─────────────────────────────────
    final suggestion = _generateSwap(
      primaryMacro,
      deviation,
      entries,
      recentLogs ?? [],
    );

    // ── Step 8: Compose the 4-sentence output ────────────────────────────
    final actualVal = _actualForMacro(primaryMacro, actualCals, actualCarbs, actualProtein, actualFat);
    final targetVal = _targetForMacro(primaryMacro, targetCals, targetCarbs, targetProtein, targetFat);
    final unit = primaryMacro == 'calories' ? 'kcal' : 'g';
    final direction = deviations[primaryMacro]! > 0 ? 'above' : 'below';

    final name = profile.firstName.isNotEmpty ? profile.firstName : 'there';

    final devPercent = (deviations[primaryMacro]! * 100).abs().round();
    final sentence2 = 'Your $primaryMacro came in at '
        '${actualVal.round()}$unit, about '
        '${(actualVal - targetVal).abs().round()}$unit $direction your '
        '${targetVal.round()}$unit goal ($devPercent% deviation), '
        'mostly from your ${deviation.responsibleMeal.toLowerCase()} '
        'portion of ${deviation.responsibleFood}.';

    final sentence3 = suggestion != null
        ? 'Tomorrow, try ${suggestion.rationale}.'
        : 'Tomorrow, try reducing your ${deviation.responsibleFood} portion by about a third.';

    final message = '${positiveNote.text} $sentence2 $sentence3';

    final primaryDev = PrimaryDeviation(
      macro: primaryMacro,
      actualValue: actualVal,
      targetValue: targetVal,
      deltaPercent: deviations[primaryMacro]! * 100,
      responsibleMeal: deviation.responsibleMeal,
      responsibleFood: deviation.responsibleFood,
    );

    return CoachResult(
      patientId: '',
      date: dailyLog.date,
      patientName: name,
      primaryDeviation: primaryDev,
      suggestion: suggestion,
      positiveNote: positiveNote,
      summary: summary,
      message: message,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static double _deltaPct(double actual, double target) {
    if (target == 0) return 0;
    return (actual - target) / target;
  }

  static double _actualForMacro(String m, double cal, double c, double p, double f) {
    switch (m) {
      case 'calories': return cal;
      case 'carbohydrates': return c;
      case 'protein': return p;
      case 'fat': return f;
      default: return 0;
    }
  }

  static double _targetForMacro(String m, double cal, double c, double p, double f) {
    switch (m) {
      case 'calories': return cal;
      case 'carbohydrates': return c;
      case 'protein': return p;
      case 'fat': return f;
      default: return 0;
    }
  }

  /// Step 4: Find which meal contributed most to the deviation.
  static _MealTrace _traceToMeal(
    String macro,
    double deviationPct,
    List<MealEntry> entries,
  ) {
    // Group entries by meal name and sum the macro
    final mealTotals = <String, double>{};
    final mealFoods = <String, String>{};

    for (final e in entries) {
      final val = _entryMacroValue(macro, e);
      mealTotals[e.mealName] = (mealTotals[e.mealName] ?? 0) + val;
      // Track the biggest single food item per meal
      final prevVal = _entryMacroValue(
          macro,
          entries.firstWhere(
            (x) => x.mealName == e.mealName && x.food.name == (mealFoods[e.mealName] ?? ''),
            orElse: () => e,
          ));
      if (val >= prevVal) {
        mealFoods[e.mealName] = e.food.name;
      }
    }

    // Find the meal with the highest contribution
    String topMeal = entries.first.mealName;
    double topVal = 0;
    for (final entry in mealTotals.entries) {
      if (entry.value > topVal) {
        topVal = entry.value;
        topMeal = entry.key;
      }
    }

    return _MealTrace(
      responsibleMeal: topMeal,
      responsibleFood: mealFoods[topMeal] ?? entries.first.food.name,
    );
  }

  static double _entryMacroValue(String macro, MealEntry e) {
    switch (macro) {
      case 'calories': return e.calories;
      case 'carbohydrates': return e.carbs;
      case 'protein': return e.protein;
      case 'fat': return e.fat;
      default: return 0;
    }
  }

  /// Step 5: Generate a swap suggestion from recent food history.
  static SwapSuggestion? _generateSwap(
    String macro,
    _MealTrace trace,
    List<MealEntry> todayEntries,
    List<DailyLog> recentLogs,
  ) {
    // Collect all unique foods the patient has eaten recently
    final recentFoods = <String, MealEntry>{};
    for (final log in recentLogs) {
      for (final e in log.entries) {
        recentFoods[e.food.name] = e;
      }
    }
    for (final e in todayEntries) {
      recentFoods[e.food.name] = e;
    }

    // Find the responsible food's macro value
    final responsible = todayEntries.firstWhere(
      (e) => e.food.name == trace.responsibleFood,
      orElse: () => todayEntries.first,
    );
    final responsibleVal = _entryMacroValue(macro, responsible);

    // Look for a familiar food with a lower value for this macro
    MealEntry? bestAlt;
    double bestAltVal = responsibleVal;
    for (final candidate in recentFoods.values) {
      if (candidate.food.name == trace.responsibleFood) continue;
      final candidateVal = _entryMacroValue(macro, candidate);
      if (candidateVal < bestAltVal) {
        bestAlt = candidate;
        bestAltVal = candidateVal;
      }
    }

    if (bestAlt != null) {
      return SwapSuggestion(
        swapFrom: trace.responsibleFood,
        swapTo: bestAlt.food.name,
        rationale: 'swapping ${trace.responsibleFood} for '
            '${bestAlt.food.name}, which you\'ve had before and is lower in $macro',
      );
    }

    // Fallback: portion adjustment
    return SwapSuggestion(
      swapFrom: trace.responsibleFood,
      swapTo: '${trace.responsibleFood} (smaller portion)',
      rationale: 'reducing your ${trace.responsibleFood} portion by about '
          'a third to bring your $macro closer to target',
    );
  }

  /// Step 7: Find something positive to say.
  static PositiveNote _findPositiveNote(
    Map<String, double> deviations,
    List<MealEntry> entries,
  ) {
    // Priority: find a macro that was met (within ±15%)
    for (final entry in deviations.entries) {
      if (entry.value.abs() <= _deviationThreshold) {
        final macroLabel = entry.key == 'calories' ? 'calorie' : entry.key;
        return PositiveNote(
          macro: entry.key,
          text: 'Good effort today — you hit your $macroLabel target right on the mark!',
        );
      }
    }

    // Fallback: acknowledge logging
    final mealCount = entries.map((e) => e.mealName).toSet().length;
    return PositiveNote(
      macro: 'logging',
      text: 'Great job logging $mealCount meals today — tracking is the first step to better nutrition!',
    );
  }
}

class _MealTrace {
  final String responsibleMeal;
  final String responsibleFood;

  const _MealTrace({
    required this.responsibleMeal,
    required this.responsibleFood,
  });
}
