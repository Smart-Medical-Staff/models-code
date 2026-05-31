import '../../patient/diseases/diet_plan/models/daily_log.dart';
import '../../patient/diseases/diet_plan/models/meal_entry.dart';
import '../../patient/diseases/diet_plan/services/diet_storage_service.dart';
import '../../services/patient_profile_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Coverage band thresholds (from spec)
// ─────────────────────────────────────────────────────────────────────────────
enum CoverageBand { adequate, marginal, deficient, severelyDeficient }

String bandLabel(CoverageBand b) {
  switch (b) {
    case CoverageBand.adequate:
      return 'Adequate';
    case CoverageBand.marginal:
      return 'Marginal';
    case CoverageBand.deficient:
      return 'Deficient';
    case CoverageBand.severelyDeficient:
      return 'Severely Deficient';
  }
}

CoverageBand _classify(double pct) {
  if (pct >= 85) return CoverageBand.adequate;
  if (pct >= 60) return CoverageBand.marginal;
  if (pct >= 35) return CoverageBand.deficient;
  return CoverageBand.severelyDeficient;
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class NutrientCoverage {
  final String nutrient;
  final String unit;
  final double actualPerDay;
  final double rdiPerDay;
  final double coveragePct;
  final CoverageBand band;
  final bool recurring;
  final String? interactionNote;

  const NutrientCoverage({
    required this.nutrient,
    required this.unit,
    required this.actualPerDay,
    required this.rdiPerDay,
    required this.coveragePct,
    required this.band,
    this.recurring = false,
    this.interactionNote,
  });

  NutrientCoverage copyWith({bool? recurring, String? interactionNote}) {
    return NutrientCoverage(
      nutrient: nutrient,
      unit: unit,
      actualPerDay: actualPerDay,
      rdiPerDay: rdiPerDay,
      coveragePct: coveragePct,
      band: band,
      recurring: recurring ?? this.recurring,
      interactionNote: interactionNote ?? this.interactionNote,
    );
  }
}

class FoodSuggestion {
  final String food;
  final bool familiar;
  final String reason;

  const FoodSuggestion({
    required this.food,
    required this.familiar,
    required this.reason,
  });
}

class FlaggedDeficiency {
  final NutrientCoverage coverage;
  final String plainLanguageImpact;
  final List<FoodSuggestion> foodSuggestions;

  const FlaggedDeficiency({
    required this.coverage,
    required this.plainLanguageImpact,
    required this.foodSuggestions,
  });
}

class SpotterResult {
  final String weekEnding;
  final int daysLogged;
  final String overallSummary;
  final List<FlaggedDeficiency> flaggedDeficiencies;
  final String closingNote;
  final String patientMessage;
  final Map<String, NutrientCoverage> allCoverage;
  final List<String> interactionFlags;
  final bool referralFlag;
  final String? referralRationale;

  const SpotterResult({
    required this.weekEnding,
    required this.daysLogged,
    required this.overallSummary,
    required this.flaggedDeficiencies,
    required this.closingNote,
    required this.patientMessage,
    required this.allCoverage,
    required this.interactionFlags,
    required this.referralFlag,
    this.referralRationale,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// RDI Reference Table (WHO / EFSA / NIH — diabetic-adjusted)
// ─────────────────────────────────────────────────────────────────────────────

class _RDI {
  final double fiber;     // g/day
  final double iron;      // mg/day
  final double calcium;   // mg/day
  final double magnesium; // mg/day
  final double zinc;      // mg/day
  final double potassium; // mg/day
  final double vitaminC;  // mg/day
  final double vitaminD;  // mcg/day
  final double vitaminB12;// mcg/day
  final double folate;    // mcg/day

  const _RDI({
    required this.fiber,
    required this.iron,
    required this.calcium,
    required this.magnesium,
    required this.zinc,
    required this.potassium,
    required this.vitaminC,
    required this.vitaminD,
    required this.vitaminB12,
    required this.folate,
  });
}

_RDI _getRDI(String gender, int age, bool isDiabetic) {
  // Diabetic patients have elevated fiber needs (≥35g vs 25g)
  final baseFiber = isDiabetic ? 35.0 : 25.0;
  final isMale = gender.toLowerCase().contains('male') && !gender.toLowerCase().contains('female');

  if (isMale) {
    return _RDI(
      fiber: baseFiber,
      iron: age > 50 ? 8.0 : 8.0,
      calcium: age > 50 ? 1200.0 : 1000.0,
      magnesium: age > 30 ? 420.0 : 400.0,
      zinc: 11.0,
      potassium: 3400.0,
      vitaminC: 90.0,
      vitaminD: age > 70 ? 20.0 : 15.0,
      vitaminB12: 2.4,
      folate: 400.0,
    );
  } else {
    return _RDI(
      fiber: baseFiber,
      iron: age > 50 ? 8.0 : 18.0,
      calcium: age > 50 ? 1200.0 : 1000.0,
      magnesium: age > 30 ? 320.0 : 310.0,
      zinc: 8.0,
      potassium: 2600.0,
      vitaminC: 75.0,
      vitaminD: age > 70 ? 20.0 : 15.0,
      vitaminB12: 2.4,
      folate: 400.0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plain-language impact descriptions
// ─────────────────────────────────────────────────────────────────────────────

String _impactText(String nutrient, bool isDiabetic) {
  switch (nutrient) {
    case 'Fiber':
      return isDiabetic
          ? 'Low fiber can cause blood sugar to spike after meals and affects digestive health.'
          : 'Fiber helps with digestion and keeps you feeling full longer.';
    case 'Iron':
      return 'Low iron can cause fatigue, weakness, and difficulty concentrating.';
    case 'Calcium':
      return 'Calcium is essential for bone health and muscle function.';
    case 'Magnesium':
      return isDiabetic
          ? 'Low magnesium can make insulin less effective at controlling blood sugar.'
          : 'Magnesium supports muscle function, sleep quality, and energy.';
    case 'Zinc':
      return 'Zinc supports immune function and wound healing.';
    case 'Potassium':
      return 'Potassium helps regulate blood pressure and muscle contractions.';
    case 'Vitamin C':
      return 'Vitamin C supports immune health and helps your body absorb iron.';
    case 'Vitamin D':
      return 'Vitamin D is important for bone health and immune function.';
    case 'Vitamin B12':
      return isDiabetic
          ? 'B12 supports nerve health — especially important for diabetic neuropathy prevention.'
          : 'Vitamin B12 is essential for nerve function and red blood cell production.';
    case 'Folate':
      return 'Folate is important for cell repair and cardiovascular health.';
    default:
      return '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default food suggestions per nutrient
// ─────────────────────────────────────────────────────────────────────────────

List<FoodSuggestion> _defaultSuggestions(String nutrient) {
  switch (nutrient) {
    case 'Fiber':
      return const [
        FoodSuggestion(food: 'Almonds (a small handful daily)', familiar: false, reason: 'Rich in fiber and healthy fats'),
        FoodSuggestion(food: 'Wholegrain bread', familiar: false, reason: 'Swap white bread for wholegrain for an easy fiber boost'),
        FoodSuggestion(food: 'Lentils or beans', familiar: false, reason: 'Excellent source of fiber and protein'),
      ];
    case 'Iron':
      return const [
        FoodSuggestion(food: 'Spinach', familiar: false, reason: 'Rich in iron, especially when cooked'),
        FoodSuggestion(food: 'Red meat (lean)', familiar: false, reason: 'Highly bioavailable iron source'),
        FoodSuggestion(food: 'Lentils', familiar: false, reason: 'Plant-based iron with added fiber'),
      ];
    case 'Calcium':
      return const [
        FoodSuggestion(food: 'Yogurt (unsweetened)', familiar: false, reason: 'High in calcium and gut-friendly probiotics'),
        FoodSuggestion(food: 'Cheese (small portion)', familiar: false, reason: 'Concentrated calcium source'),
        FoodSuggestion(food: 'Sardines (with bones)', familiar: false, reason: 'One of the richest natural calcium sources'),
      ];
    case 'Magnesium':
      return const [
        FoodSuggestion(food: 'Spinach', familiar: false, reason: 'One of the best sources of magnesium'),
        FoodSuggestion(food: 'Pumpkin seeds', familiar: false, reason: 'A small handful provides significant magnesium'),
        FoodSuggestion(food: 'Dark chocolate (85%+)', familiar: false, reason: 'A small square is surprisingly high in magnesium'),
      ];
    case 'Zinc':
      return const [
        FoodSuggestion(food: 'Pumpkin seeds', familiar: false, reason: 'Excellent zinc source in a small serving'),
        FoodSuggestion(food: 'Chicken', familiar: false, reason: 'Good source of zinc and lean protein'),
        FoodSuggestion(food: 'Chickpeas', familiar: false, reason: 'Plant-based zinc with added fiber'),
      ];
    case 'Potassium':
      return const [
        FoodSuggestion(food: 'Banana', familiar: false, reason: 'Well-known potassium source (eat in moderation for blood sugar)'),
        FoodSuggestion(food: 'Sweet potato', familiar: false, reason: 'Rich in potassium with a lower glycemic index than regular potato'),
        FoodSuggestion(food: 'Avocado', familiar: false, reason: 'High in potassium and healthy fats'),
      ];
    case 'Vitamin C':
      return const [
        FoodSuggestion(food: 'Bell peppers', familiar: false, reason: 'Higher in vitamin C than oranges'),
        FoodSuggestion(food: 'Broccoli', familiar: false, reason: 'Good source of vitamin C with added fiber'),
        FoodSuggestion(food: 'Strawberries', familiar: false, reason: 'Sweet source of vitamin C (eat in moderation)'),
      ];
    case 'Vitamin D':
      return const [
        FoodSuggestion(food: 'Eggs (with yolk)', familiar: false, reason: 'One of the few food sources of vitamin D'),
        FoodSuggestion(food: 'Salmon or fatty fish', familiar: false, reason: 'The best natural food source of vitamin D'),
        FoodSuggestion(food: 'Fortified milk', familiar: false, reason: 'An easy daily source of vitamin D'),
      ];
    case 'Vitamin B12':
      return const [
        FoodSuggestion(food: 'Eggs', familiar: false, reason: 'Reliable B12 source, easy to add daily'),
        FoodSuggestion(food: 'Milk or yogurt', familiar: false, reason: 'Good source of B12 and calcium together'),
        FoodSuggestion(food: 'Fish', familiar: false, reason: 'Rich in B12 and omega-3 fatty acids'),
      ];
    case 'Folate':
      return const [
        FoodSuggestion(food: 'Spinach or dark leafy greens', familiar: false, reason: 'One of the richest natural folate sources'),
        FoodSuggestion(food: 'Lentils', familiar: false, reason: 'Excellent source of folate and fiber'),
        FoodSuggestion(food: 'Asparagus', familiar: false, reason: 'Unusually high in folate for a vegetable'),
      ];
    default:
      return const [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Weekly Deficiency Spotter Service
// ─────────────────────────────────────────────────────────────────────────────

class WeeklyDeficiencySpotterService {
  static final _storage = DietStorageService();

  /// Run the full weekly deficiency analysis.
  /// Returns null if no meal logs exist for this week.
  static Future<SpotterResult?> evaluate() async {
    // ── Load patient profile ─────────────────────────────────────────────
    final profile = await PatientProfileService.instance.load();
    if (!profile.hasDietData) return null;

    final gender = profile.gender;
    final age = profile.age ?? 30;
    final isDiabetic = profile.hasDiabetes || profile.bloodSugarType != 'none';

    // ── Load last 7 days of meal logs ────────────────────────────────────
    final weekLogs = await _storage.loadLast7Days();
    final daysLogged = weekLogs.length;

    // Gate: need at least 1 day with entries
    if (daysLogged < 1) return null;

    // ── Step 1: Aggregate 7-day nutrient totals ──────────────────────────
    final totals = _aggregateWeeklyTotals(weekLogs);

    // ── Step 2: Compute RDI coverage ─────────────────────────────────────
    final rdi = _getRDI(gender, age, isDiabetic);
    final coverageMap = _computeCoverage(totals, rdi, daysLogged);

    // ── Step 4: Check recurrence ─────────────────────────────────────────
    final prevReport = await _storage.loadPreviousSpotterReport();
    final prevDeficiencies = _extractPrevDeficiencies(prevReport);
    _markRecurring(coverageMap, prevDeficiencies);

    // ── Step 5: Check interaction effects ────────────────────────────────
    final interactions = _checkInteractions(coverageMap, isDiabetic);

    // ── Step 6: Select top 2–3 deficiencies ──────────────────────────────
    final flagged = _selectTopDeficiencies(coverageMap, isDiabetic);

    // ── Step 7: Map to food suggestions ──────────────────────────────────
    // (Using default suggestions; familiar food matching would need 30-day history)
    final flaggedWithSuggestions = flagged.map((fc) {
      return FlaggedDeficiency(
        coverage: fc,
        plainLanguageImpact: _impactText(fc.nutrient, isDiabetic),
        foodSuggestions: _defaultSuggestions(fc.nutrient),
      );
    }).toList();

    // ── Referral flag ────────────────────────────────────────────────────
    final severeCount = coverageMap.values
        .where((c) => c.band == CoverageBand.severelyDeficient)
        .length;
    final recurringCount = coverageMap.values
        .where((c) => c.recurring && c.band.index >= CoverageBand.deficient.index)
        .length;
    final referralFlag = severeCount >= 2 || recurringCount >= 2;
    final referralRationale = referralFlag
        ? 'Persistent deficiencies detected over multiple weeks — '
          'a formal dietary consultation is recommended.'
        : null;

    // ── Step 8: Compose patient message ──────────────────────────────────
    final patientMessage = _composePatientMessage(
      daysLogged, flaggedWithSuggestions, coverageMap,
    );
    final overallSummary = _composeOverallSummary(daysLogged, coverageMap);
    final closingNote = _composeClosingNote(coverageMap);

    // ── Compute week ending date ─────────────────────────────────────────
    final weekEnding = weekLogs.isNotEmpty
        ? weekLogs.last.date
        : _storage.todayString();

    // ── Save current report for next week's recurrence detection ─────────
    final deficientList = coverageMap.entries
        .where((e) => e.value.band == CoverageBand.deficient ||
                      e.value.band == CoverageBand.severelyDeficient)
        .map((e) => e.key)
        .toList();
    await _storage.saveSpotterReport({
      'week_ending': weekEnding,
      'deficiencies': deficientList,
    });

    return SpotterResult(
      weekEnding: weekEnding,
      daysLogged: daysLogged,
      overallSummary: overallSummary,
      flaggedDeficiencies: flaggedWithSuggestions,
      closingNote: closingNote,
      patientMessage: patientMessage,
      allCoverage: coverageMap,
      interactionFlags: interactions,
      referralFlag: referralFlag,
      referralRationale: referralRationale,
    );
  }

  // ─── Pipeline helpers ──────────────────────────────────────────────────

  static Map<String, double> _aggregateWeeklyTotals(List<DailyLog> logs) {
    final t = <String, double>{
      'fiber': 0, 'iron': 0, 'calcium': 0, 'magnesium': 0,
      'zinc': 0, 'potassium': 0, 'vitaminC': 0, 'vitaminD': 0,
      'vitaminB12': 0, 'folate': 0,
    };

    for (final log in logs) {
      for (final e in log.entries) {
        t['fiber'] = t['fiber']! + e.fiber;
        t['iron'] = t['iron']! + e.iron;
        t['calcium'] = t['calcium']! + e.calcium;
        t['magnesium'] = t['magnesium']! + e.magnesium;
        t['zinc'] = t['zinc']! + e.zinc;
        t['potassium'] = t['potassium']! + e.potassium;
        t['vitaminC'] = t['vitaminC']! + e.vitaminC;
        t['vitaminD'] = t['vitaminD']! + e.vitaminD;
        t['vitaminB12'] = t['vitaminB12']! + e.vitaminB12;
        t['folate'] = t['folate']! + e.folate;
      }
    }
    return t;
  }

  static Map<String, NutrientCoverage> _computeCoverage(
    Map<String, double> totals,
    _RDI rdi,
    int daysLogged,
  ) {
    final rdiMap = {
      'Fiber': (rdi.fiber, 'g'),
      'Iron': (rdi.iron, 'mg'),
      'Calcium': (rdi.calcium, 'mg'),
      'Magnesium': (rdi.magnesium, 'mg'),
      'Zinc': (rdi.zinc, 'mg'),
      'Potassium': (rdi.potassium, 'mg'),
      'Vitamin C': (rdi.vitaminC, 'mg'),
      'Vitamin D': (rdi.vitaminD, 'mcg'),
      'Vitamin B12': (rdi.vitaminB12, 'mcg'),
      'Folate': (rdi.folate, 'mcg'),
    };
    final keyMap = {
      'Fiber': 'fiber', 'Iron': 'iron', 'Calcium': 'calcium',
      'Magnesium': 'magnesium', 'Zinc': 'zinc', 'Potassium': 'potassium',
      'Vitamin C': 'vitaminC', 'Vitamin D': 'vitaminD',
      'Vitamin B12': 'vitaminB12', 'Folate': 'folate',
    };

    final result = <String, NutrientCoverage>{};
    for (final entry in rdiMap.entries) {
      final name = entry.key;
      final (rdiVal, unit) = entry.value;
      final totalVal = totals[keyMap[name]] ?? 0.0;
      final avgPerDay = totalVal / daysLogged;
      final pct = rdiVal > 0 ? (avgPerDay / rdiVal) * 100.0 : 100.0;

      result[name] = NutrientCoverage(
        nutrient: name,
        unit: unit,
        actualPerDay: avgPerDay.toDouble(),
        rdiPerDay: rdiVal,
        coveragePct: pct.toDouble(),
        band: _classify(pct.toDouble()),
      );
    }
    return result;
  }

  static List<String> _extractPrevDeficiencies(Map<String, dynamic>? prev) {
    if (prev == null) return [];
    final list = prev['deficiencies'];
    if (list is List) return list.cast<String>();
    return [];
  }

  static void _markRecurring(
    Map<String, NutrientCoverage> coverage,
    List<String> prevDeficiencies,
  ) {
    for (final name in prevDeficiencies) {
      if (coverage.containsKey(name)) {
        final c = coverage[name]!;
        if (c.band == CoverageBand.deficient ||
            c.band == CoverageBand.severelyDeficient) {
          coverage[name] = c.copyWith(recurring: true);
        }
      }
    }
  }

  static List<String> _checkInteractions(
    Map<String, NutrientCoverage> coverage,
    bool isDiabetic,
  ) {
    final flags = <String>[];
    final isLow = (String n) =>
        coverage[n]?.band == CoverageBand.deficient ||
        coverage[n]?.band == CoverageBand.severelyDeficient;

    if (isLow('Iron') && isLow('Vitamin C')) {
      flags.add('Low iron + low vitamin C: vitamin C significantly increases iron absorption — co-deficiency compounds the impact.');
    }
    if (isLow('Magnesium') && isDiabetic) {
      flags.add('Low magnesium in a diabetic patient: magnesium deficiency is associated with insulin resistance.');
    }
    if (isLow('Vitamin D') && isLow('Calcium')) {
      flags.add('Low vitamin D + low calcium: co-deficiency accelerates bone density loss.');
    }
    if (isLow('Vitamin B12')) {
      flags.add('Low vitamin B12: if the patient is on metformin, this medication depletes B12 — monitor closely.');
    }
    if (isLow('Potassium')) {
      flags.add('Low potassium: relevant if the patient is on ACE inhibitors or diuretics.');
    }

    // Tag interaction notes on the coverage entries
    if (isLow('Iron') && isLow('Vitamin C')) {
      coverage['Iron'] = coverage['Iron']!.copyWith(
        interactionNote: 'Pair with vitamin C foods to boost absorption',
      );
    }

    return flags;
  }

  static List<NutrientCoverage> _selectTopDeficiencies(
    Map<String, NutrientCoverage> coverage,
    bool isDiabetic,
  ) {
    final candidates = coverage.values
        .where((c) =>
            c.band == CoverageBand.deficient ||
            c.band == CoverageBand.severelyDeficient)
        .toList();

    // Sort: severity → recurring → interaction
    candidates.sort((a, b) {
      // 1. Severity (severely deficient first)
      final sevCmp = b.band.index.compareTo(a.band.index);
      if (sevCmp != 0) return sevCmp;
      // 2. Recurring first
      if (a.recurring && !b.recurring) return -1;
      if (!a.recurring && b.recurring) return 1;
      // 3. Has interaction note
      if (a.interactionNote != null && b.interactionNote == null) return -1;
      if (a.interactionNote == null && b.interactionNote != null) return 1;
      // 4. Lower coverage first
      return a.coveragePct.compareTo(b.coveragePct);
    });

    return candidates.take(3).toList();
  }

  static String _composeOverallSummary(
    int daysLogged,
    Map<String, NutrientCoverage> coverage,
  ) {
    final adequate = coverage.values
        .where((c) => c.band == CoverageBand.adequate)
        .length;
    final total = coverage.length;

    return 'This week you logged meals on $daysLogged out of 7 days. '
        '$adequate out of $total tracked nutrients are within healthy range.';
  }

  static String _composeClosingNote(Map<String, NutrientCoverage> coverage) {
    // Find something positive
    final goodOnes = coverage.entries
        .where((e) => e.value.band == CoverageBand.adequate)
        .map((e) => e.key)
        .toList();

    if (goodOnes.isNotEmpty) {
      final items = goodOnes.take(2).join(' and ');
      return 'Your $items levels are looking good — keep that going!';
    }
    return 'Tracking consistently is the best first step — keep logging and small changes will add up.';
  }

  static String _composePatientMessage(
    int daysLogged,
    List<FlaggedDeficiency> flagged,
    Map<String, NutrientCoverage> coverage,
  ) {
    final buf = StringBuffer();
    buf.write('This week you logged meals on $daysLogged out of 7 days');

    final defCount = flagged.length;
    if (defCount == 0) {
      buf.write(
        ' — and all your tracked nutrients are within a healthy range. '
        'Great week! Keep up the consistency.',
      );
      return buf.toString();
    }

    buf.write('. ');
    if (defCount == 1) {
      buf.write('One thing is worth paying attention to. ');
    } else {
      buf.write('$defCount things are worth paying attention to. ');
    }

    for (final f in flagged) {
      final n = f.coverage.nutrient;
      final recurring = f.coverage.recurring ? ' (this is a recurring pattern)' : '';
      buf.write('Your $n has been low$recurring — ${f.plainLanguageImpact.toLowerCase()} ');
      if (f.foodSuggestions.isNotEmpty) {
        buf.write('Try adding ${f.foodSuggestions.first.food.toLowerCase()} to your meals this week. ');
      }
    }

    // Add closing
    buf.write(_composeClosingNote(coverage));
    return buf.toString();
  }
}
