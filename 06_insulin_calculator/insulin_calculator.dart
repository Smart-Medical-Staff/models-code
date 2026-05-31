/// Insulin Dose Calculator & Tracker — Flutter (Dart)
///
/// Single-file implementation. Drop into your Flutter project and push
/// `InsulinCalculatorScreen()` from any navigator.
///
/// One dependency required:
///   flutter pub add shared_preferences

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// THEME
// ============================================================================

class _C {
  static const primary       = Color(0xFF2563EB);
  static const primaryLight  = Color(0xFFEFF6FF);
  static const success       = Color(0xFF16A34A);
  static const danger        = Color(0xFFDC2626);
  static const textPrimary   = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary  = Color(0xFF9CA3AF);
  static const background    = Color(0xFFF9FAFB);
  static const surface       = Color(0xFFFFFFFF);
  static const border        = Color(0xFFE5E7EB);
  static const basal         = Color(0xFF7C3AED);
  static const basalLight    = Color(0xFFF5F3FF);
}

// ============================================================================
// TYPES
// ============================================================================

enum DiabetesType { t1d, t2d }
enum DoseType { bolus, basal }

class UserProfile {
  final DiabetesType diabetesType;
  final double weight;                  // kg
  final double totalDailyDose;          // TDD in units
  final double basalDose;               // 50% of TDD
  final double carbRatio;               // grams of carbs per 1 unit (ICR)
  final double insulinSensitivityFactor;// mg/dL drop per 1 unit (ISF)
  final double targetBloodGlucose;      // mg/dL

  const UserProfile({
    required this.diabetesType,
    required this.weight,
    required this.totalDailyDose,
    required this.basalDose,
    required this.carbRatio,
    required this.insulinSensitivityFactor,
    required this.targetBloodGlucose,
  });

  Map<String, dynamic> toJson() => {
        'diabetesType': diabetesType.name,
        'weight': weight,
        'totalDailyDose': totalDailyDose,
        'basalDose': basalDose,
        'carbRatio': carbRatio,
        'insulinSensitivityFactor': insulinSensitivityFactor,
        'targetBloodGlucose': targetBloodGlucose,
      };

  static UserProfile fromJson(Map<String, dynamic> j) => UserProfile(
        diabetesType: DiabetesType.values.firstWhere((e) => e.name == j['diabetesType'],
            orElse: () => DiabetesType.t1d),
        weight: (j['weight'] as num).toDouble(),
        totalDailyDose: (j['totalDailyDose'] as num).toDouble(),
        basalDose: (j['basalDose'] as num).toDouble(),
        carbRatio: (j['carbRatio'] as num).toDouble(),
        insulinSensitivityFactor: (j['insulinSensitivityFactor'] as num).toDouble(),
        targetBloodGlucose: (j['targetBloodGlucose'] as num).toDouble(),
      );

  UserProfile copyWith({
    double? totalDailyDose,
    double? basalDose,
    double? carbRatio,
    double? insulinSensitivityFactor,
  }) =>
      UserProfile(
        diabetesType: diabetesType,
        weight: weight,
        totalDailyDose: totalDailyDose ?? this.totalDailyDose,
        basalDose: basalDose ?? this.basalDose,
        carbRatio: carbRatio ?? this.carbRatio,
        insulinSensitivityFactor: insulinSensitivityFactor ?? this.insulinSensitivityFactor,
        targetBloodGlucose: targetBloodGlucose,
      );
}

class DoseLog {
  final String id;
  final double units;
  final DoseType type;
  final int timestamp; // ms since epoch
  final double? mealUnits;
  final double? correctionUnits;

  const DoseLog({
    required this.id,
    required this.units,
    required this.type,
    required this.timestamp,
    this.mealUnits,
    this.correctionUnits,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'units': units,
        'type': type.name,
        'timestamp': timestamp,
        if (mealUnits != null) 'mealUnits': mealUnits,
        if (correctionUnits != null) 'correctionUnits': correctionUnits,
      };

  static DoseLog fromJson(Map<String, dynamic> j) => DoseLog(
        id: j['id'] as String,
        units: (j['units'] as num).toDouble(),
        type: DoseType.values.firstWhere((e) => e.name == j['type'],
            orElse: () => DoseType.bolus),
        timestamp: (j['timestamp'] as num).toInt(),
        mealUnits: j['mealUnits'] == null ? null : (j['mealUnits'] as num).toDouble(),
        correctionUnits:
            j['correctionUnits'] == null ? null : (j['correctionUnits'] as num).toDouble(),
      );
}

class DailyData {
  final List<DoseLog> logs;
  final String date; // YYYY-MM-DD
  const DailyData({required this.logs, required this.date});

  Map<String, dynamic> toJson() =>
      {'logs': logs.map((l) => l.toJson()).toList(), 'date': date};

  static DailyData fromJson(Map<String, dynamic> j) => DailyData(
        logs: (j['logs'] as List<dynamic>)
            .map((e) => DoseLog.fromJson(e as Map<String, dynamic>))
            .toList(),
        date: j['date'] as String,
      );
}

class BolusResult {
  final double mealDose;
  final double correctionDose;
  final double totalDose;
  const BolusResult(this.mealDose, this.correctionDose, this.totalDose);
}

// ============================================================================
// CALCULATION ENGINE
// ============================================================================

const String _kProfileKey = 'insulin_user_profile';
const String _kDailyKey   = 'insulin_daily_data';

String _getTodayString() {
  final d = DateTime.now();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Build a UserProfile from weight + diabetes type using standard formulas.
UserProfile buildProfileFromWeight(double weight, DiabetesType diabetesType,
    {double targetBG = 120}) {
  // T1D factor ~0.55; T2D factor ~0.40 (clinical rule of thumb)
  final tddFactor = diabetesType == DiabetesType.t1d ? 0.55 : 0.4;
  final tdd = weight * tddFactor;
  return UserProfile(
    diabetesType: diabetesType,
    weight: weight,
    totalDailyDose: tdd,
    basalDose: tdd * 0.5,                  // 50% rule
    carbRatio: 500 / tdd,                  // Rule of 500
    insulinSensitivityFactor: 1800 / tdd,  // Rule of 1800
    targetBloodGlucose: targetBG,
  );
}

/// Adjust basal by ±1 unit and cascade-recalculate TDD, ICR, ISF.
UserProfile adjustBasalDose(UserProfile profile, double adjustment) {
  final newBasal = max(1.0, profile.basalDose + adjustment);
  final newTDD = newBasal / 0.5;
  return profile.copyWith(
    basalDose: newBasal,
    totalDailyDose: newTDD,
    carbRatio: 500 / newTDD,
    insulinSensitivityFactor: 1800 / newTDD,
  );
}

/// Calculate bolus dose for a meal with optional BG correction.
BolusResult calculateBolus(UserProfile profile, double carbs, [double? currentBG]) {
  final mealDose =
      (profile.carbRatio > 0 && carbs > 0) ? carbs / profile.carbRatio : 0.0;

  double correctionDose = 0;
  if (currentBG != null &&
      profile.insulinSensitivityFactor > 0 &&
      currentBG > profile.targetBloodGlucose) {
    correctionDose =
        (currentBG - profile.targetBloodGlucose) / profile.insulinSensitivityFactor;
  }

  return BolusResult(
    max(0.0, mealDose),
    max(0.0, correctionDose),
    max(0.0, mealDose + correctionDose),
  );
}

// ============================================================================
// STORAGE
// ============================================================================

Future<UserProfile?> _loadProfile() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProfileKey);
    if (raw == null) return null;
    return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<void> _saveProfile(UserProfile p) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kProfileKey, jsonEncode(p.toJson()));
}

Future<DailyData> _loadDailyData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDailyKey);
    if (raw != null) {
      final parsed = DailyData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (parsed.date == _getTodayString()) return parsed;
    }
  } catch (_) {}
  return DailyData(logs: const [], date: _getTodayString());
}

Future<void> _saveDailyData(DailyData data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kDailyKey, jsonEncode(data.toJson()));
}

String _generateId() =>
    '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 32).toRadixString(36)}';

// ============================================================================
// MAIN SCREEN
// ============================================================================

class InsulinCalculatorScreen extends StatefulWidget {
  const InsulinCalculatorScreen({super.key});

  @override
  State<InsulinCalculatorScreen> createState() => _InsulinCalculatorScreenState();
}

class _InsulinCalculatorScreenState extends State<InsulinCalculatorScreen> {
  UserProfile? _profile;
  DailyData _daily = DailyData(logs: const [], date: _getTodayString());
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([_loadProfile(), _loadDailyData()]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as UserProfile?;
      _daily = results[1] as DailyData;
      _loading = false;
    });
  }

  Future<void> _handleSaveProfile(UserProfile p) async {
    await _saveProfile(p);
    final fresh = DailyData(logs: const [], date: _getTodayString());
    await _saveDailyData(fresh);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _daily = fresh;
    });
  }

  Future<void> _handleResetProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Profile'),
        content: const Text("This will clear your profile and today's logs. Continue?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _C.danger),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfileKey);
    await prefs.remove(_kDailyKey);
    if (!mounted) return;
    setState(() {
      _profile = null;
      _daily = DailyData(logs: const [], date: _getTodayString());
    });
  }

  void _addLog({required double units, required DoseType type, double? mealUnits, double? correctionUnits}) {
    final newLog = DoseLog(
      id: _generateId(),
      units: units,
      type: type,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      mealUnits: mealUnits,
      correctionUnits: correctionUnits,
    );
    final updated = DailyData(logs: [..._daily.logs, newLog], date: _daily.date);
    setState(() => _daily = updated);
    _saveDailyData(updated);
  }

  void _deleteLog(String id) {
    final updated = DailyData(
        logs: _daily.logs.where((l) => l.id != id).toList(), date: _daily.date);
    setState(() => _daily = updated);
    _saveDailyData(updated);
  }

  Future<void> _adjustBasal(double delta) async {
    final p = _profile;
    if (p == null) return;
    final updated = adjustBasalDose(p, delta);
    await _saveProfile(updated);
    if (!mounted) return;
    setState(() => _profile = updated);
  }

  Future<void> _openManualLogModal() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ManualLogDialog(
        onLog: (u, t) {
          _addLog(units: u, type: t);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${u.toStringAsFixed(1)} unit ${t.name} dose recorded.')),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _C.background,
        body: Center(child: CircularProgressIndicator(color: _C.primary)),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return Scaffold(
        backgroundColor: _C.background,
        body: SafeArea(
          child: Column(
            children: [
              _AppHeader(title: 'Insulin Dose Calculator & Tracker'),
              Expanded(child: _ProfileSetup(onSave: _handleSaveProfile)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _C.background,
      body: SafeArea(
        child: Column(
          children: [
            _AppHeader(
              title: 'Daily Summary',
              trailing: GestureDetector(
                onTap: _handleResetProfile,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Edit Profile',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: _C.primary)),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  children: [
                    _DoseSummary(profile: profile),
                    const SizedBox(height: 16),
                    _DoseTracker(
                      daily: _daily,
                      tdd: profile.totalDailyDose,
                      onDelete: _deleteLog,
                      onOpenManual: _openManualLogModal,
                    ),
                    const SizedBox(height: 16),
                    _MealCalculator(profile: profile, onLog: _addLog),
                    const SizedBox(height: 16),
                    _BasalAdjustment(onAdjust: _adjustBasal),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

class _AppHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _AppHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _C.surface,
        border: Border(bottom: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: _C.textPrimary)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: _C.textPrimary)),
      );
}

class _LabeledInput extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? value;
  final String? hint;
  final String? unit;
  final bool editable;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;
  const _LabeledInput({
    required this.label,
    this.controller,
    this.value,
    this.hint,
    this.unit,
    this.editable = true,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _C.textPrimary)),
          const SizedBox(height: 6),
          Stack(
            children: [
              TextField(
                controller: controller ??
                    (value != null ? TextEditingController(text: value) : null),
                enabled: editable,
                keyboardType: keyboardType,
                inputFormatters: keyboardType == const TextInputType.numberWithOptions(decimal: true)
                    ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                    : null,
                onChanged: onChanged,
                style: TextStyle(
                    fontSize: 15,
                    color: editable ? _C.textPrimary : _C.textSecondary),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(color: _C.textTertiary),
                  filled: true,
                  fillColor: editable ? _C.surface : const Color(0xFFF9FAFB),
                  isDense: true,
                  contentPadding: EdgeInsets.fromLTRB(12, 12, unit != null ? 56 : 12, 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _C.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _C.border),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _C.border),
                  ),
                ),
              ),
              if (unit != null)
                Positioned(
                  right: 12,
                  top: 14,
                  child: Text(unit!,
                      style: const TextStyle(fontSize: 13, color: _C.textSecondary)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _BtnVariant { primary, secondary, danger, ghost }

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final _BtnVariant variant;
  const _Btn({required this.label, required this.onPressed, this.variant = _BtnVariant.primary});

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    Color bg, fg, border;
    switch (variant) {
      case _BtnVariant.primary:
        bg = _C.primary; fg = Colors.white; border = _C.primary;
        break;
      case _BtnVariant.secondary:
        bg = _C.surface; fg = _C.textPrimary; border = _C.border;
        break;
      case _BtnVariant.danger:
        bg = _C.danger; fg = Colors.white; border = _C.danger;
        break;
      case _BtnVariant.ghost:
        bg = Colors.transparent; fg = _C.primary; border = Colors.transparent;
        break;
    }
    if (disabled) { bg = _C.border; fg = _C.textSecondary; border = _C.border; }
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: border),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _DoseTag extends StatelessWidget {
  final DoseType type;
  const _DoseTag(this.type);

  @override
  Widget build(BuildContext context) {
    final isBolus = type == DoseType.bolus;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isBolus ? _C.primaryLight : _C.basalLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(isBolus ? 'Bolus' : 'Basal',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isBolus ? _C.primary : _C.basal)),
    );
  }
}

// ============================================================================
// PROFILE SETUP
// ============================================================================

class _ProfileSetup extends StatefulWidget {
  final ValueChanged<UserProfile> onSave;
  const _ProfileSetup({required this.onSave});

  @override
  State<_ProfileSetup> createState() => _ProfileSetupState();
}

class _ProfileSetupState extends State<_ProfileSetup> {
  DiabetesType _type = DiabetesType.t1d;
  final TextEditingController _weight = TextEditingController(text: '70');

  @override
  void dispose() { _weight.dispose(); super.dispose(); }

  void _save() {
    final w = double.tryParse(_weight.text);
    if (w == null || w <= 0) {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Invalid Weight'),
        content: const Text('Please enter a valid weight in kilograms.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ));
      return;
    }
    widget.onSave(buildProfileFromWeight(w, _type));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text('Welcome',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700, color: _C.textPrimary)),
                SizedBox(height: 6),
                Text('Set up your profile so we can calculate your insulin needs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: _C.textSecondary, height: 1.45)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Diabetes Type',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: _C.textPrimary)),
                const SizedBox(height: 6),
                _TypeSelector<DiabetesType>(
                  options: const [DiabetesType.t1d, DiabetesType.t2d],
                  labels: const {DiabetesType.t1d: 'Type 1 (T1D)', DiabetesType.t2d: 'Type 2 (T2D)'},
                  value: _type,
                  onChange: (v) => setState(() => _type = v),
                ),
                _LabeledInput(label: 'Weight', controller: _weight, hint: 'e.g. 70', unit: 'kg'),
                const SizedBox(height: 8),
                _Btn(label: 'Calculate & Save Profile', onPressed: _save),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Disclaimer: This tool is for informational purposes only. '
              'Always consult your healthcare provider for medical advice.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _C.textTertiary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeSelector<T> extends StatelessWidget {
  final List<T> options;
  final Map<T, String> labels;
  final T value;
  final ValueChanged<T> onChange;
  const _TypeSelector({
    required this.options,
    required this.labels,
    required this.value,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: _C.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: options.map((opt) {
          final selected = opt == value;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChange(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: selected ? _C.primary : _C.surface,
                child: Text(
                  labels[opt] ?? opt.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : _C.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================================
// DOSE SUMMARY
// ============================================================================

class _DoseSummary extends StatelessWidget {
  final UserProfile profile;
  const _DoseSummary({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Your Insulin Profile'),
          Row(children: [
            Expanded(child: _MetricCard(label: 'Total Daily Dose', value: profile.totalDailyDose.toStringAsFixed(1), unit: 'units', hint: 'Based on your weight')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(label: 'Basal Dose (50%)', value: profile.basalDose.toStringAsFixed(1), unit: 'units', hint: 'Long-acting background')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _MetricCard(label: 'Carb Ratio (ICR)', value: '1:${profile.carbRatio.toStringAsFixed(0)}', unit: 'u/g', hint: 'Rule of 500')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(label: 'Sensitivity (ISF)', value: profile.insulinSensitivityFactor.toStringAsFixed(0), unit: 'mg/dL', hint: 'Rule of 1800')),
          ]),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label, value, unit, hint;
  const _MetricCard({required this.label, required this.value, required this.unit, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _C.textSecondary)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _C.primary)),
            const SizedBox(width: 4),
            Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(unit, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _C.textSecondary))),
          ]),
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(fontSize: 10, color: _C.textTertiary)),
        ],
      ),
    );
  }
}

// ============================================================================
// MEAL CALCULATOR
// ============================================================================

class _MealCalculator extends StatefulWidget {
  final UserProfile profile;
  final void Function({required double units, required DoseType type, double? mealUnits, double? correctionUnits}) onLog;
  const _MealCalculator({required this.profile, required this.onLog});

  @override
  State<_MealCalculator> createState() => _MealCalculatorState();
}

class _MealCalculatorState extends State<_MealCalculator> {
  final _carbs = TextEditingController();
  final _bg = TextEditingController();

  @override
  void dispose() { _carbs.dispose(); _bg.dispose(); super.dispose(); }

  BolusResult get _result {
    final c = double.tryParse(_carbs.text) ?? 0;
    final bg = double.tryParse(_bg.text);
    return calculateBolus(widget.profile, c, bg);
  }

  void _log() {
    final r = _result;
    if (r.totalDose <= 0) return;
    widget.onLog(units: r.totalDose, type: DoseType.bolus, mealUnits: r.mealDose, correctionUnits: r.correctionDose);
    _carbs.clear(); _bg.clear();
    setState(() {});
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dose Logged'),
      content: Text('${r.totalDose.toStringAsFixed(1)} unit bolus recorded.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Bolus Dose Calculator'),
          _LabeledInput(label: 'Carbs in Meal', controller: _carbs, hint: 'e.g. 60', unit: 'g',
              onChanged: (_) => setState(() {})),
          _LabeledInput(label: 'Current Blood Glucose', controller: _bg, hint: 'e.g. 180', unit: 'mg/dL',
              onChanged: (_) => setState(() {})),
          _LabeledInput(label: 'Target Blood Glucose', value: widget.profile.targetBloodGlucose.toStringAsFixed(0), unit: 'mg/dL', editable: false),
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Recommended Dose',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.textSecondary)),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(r.totalDose.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: _C.primary)),
                const SizedBox(width: 6),
                const Padding(padding: EdgeInsets.only(bottom: 6),
                    child: Text('units', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _C.textSecondary))),
              ]),
              const SizedBox(height: 4),
              Text('Meal: ${r.mealDose.toStringAsFixed(1)} u   Correction: ${r.correctionDose.toStringAsFixed(1)} u',
                  style: const TextStyle(fontSize: 12, color: _C.textSecondary)),
            ]),
          ),
          _Btn(
            label: r.totalDose > 0
                ? 'Log ${r.totalDose.toStringAsFixed(1)} Unit Bolus'
                : 'Enter carbs or BG to calculate',
            onPressed: r.totalDose > 0 ? _log : null,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DOSE TRACKER
// ============================================================================

class _DoseTracker extends StatelessWidget {
  final DailyData daily;
  final double tdd;
  final ValueChanged<String> onDelete;
  final VoidCallback onOpenManual;
  const _DoseTracker({required this.daily, required this.tdd, required this.onDelete, required this.onOpenManual});

  String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDetails(DoseLog log) {
    if (log.type == DoseType.bolus && log.mealUnits != null) {
      return 'Meal: ${log.mealUnits!.toStringAsFixed(1)}u  Correction: ${(log.correctionUnits ?? 0).toStringAsFixed(1)}u';
    }
    return log.type == DoseType.basal ? 'Basal — long-acting' : 'Manual bolus';
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete Log'),
      content: const Text('Remove this dose entry?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () { Navigator.pop(ctx); onDelete(id); },
          style: TextButton.styleFrom(foregroundColor: _C.danger),
          child: const Text('Delete'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final totalTaken = daily.logs.fold<double>(0, (s, l) => s + l.units);
    final percentage = tdd > 0 ? min(totalTaken / tdd * 100, 100.0) : 0.0;
    final sortedLogs = [...daily.logs]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Today's Doses",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.textPrimary)),
          OutlinedButton(
            onPressed: onOpenManual,
            style: OutlinedButton.styleFrom(
              foregroundColor: _C.textPrimary,
              side: const BorderSide(color: _C.border),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('+ Log Dose', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${totalTaken.toStringAsFixed(1)} units taken', style: const TextStyle(fontSize: 12, color: _C.textSecondary)),
          Text('TDD: ${tdd.toStringAsFixed(1)} units', style: const TextStyle(fontSize: 12, color: _C.textSecondary)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 8,
            backgroundColor: _C.border,
            valueColor: const AlwaysStoppedAnimation(_C.primary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${percentage.round()}% of TDD',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: _C.textTertiary)),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: _C.border)),
        const Text('Logged Doses',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _C.textSecondary)),
        const SizedBox(height: 8),
        if (sortedLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No doses logged yet today.', style: TextStyle(fontSize: 14, color: _C.textTertiary))),
          )
        else
          ...sortedLogs.map((log) => Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _C.border))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('${log.units.toStringAsFixed(1)} units',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _C.textPrimary)),
                        const SizedBox(width: 8),
                        _DoseTag(log.type),
                        const SizedBox(width: 8),
                        Text(_formatTime(log.timestamp),
                            style: const TextStyle(fontSize: 12, color: _C.textTertiary)),
                      ]),
                      const SizedBox(height: 2),
                      Text(_formatDetails(log),
                          style: const TextStyle(fontSize: 12, color: _C.textSecondary)),
                    ]),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _confirmDelete(context, log.id),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Text('✕', style: TextStyle(fontSize: 18, color: _C.textSecondary)),
                    ),
                  ),
                ]),
              )),
      ]),
    );
  }
}

// ============================================================================
// BASAL ADJUSTMENT
// ============================================================================

class _BasalAdjustment extends StatelessWidget {
  final ValueChanged<double> onAdjust;
  const _BasalAdjustment({required this.onAdjust});

  void _confirm(BuildContext context, double delta) {
    final dir = delta > 0 ? 'increase' : 'decrease';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Adjust Basal Dose'),
      content: Text(
          'This will permanently $dir your basal dose by 1 unit and recalculate '
          'your carb ratio and sensitivity factor. Continue?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(ctx); onAdjust(delta); }, child: const Text('Confirm')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionTitle('Fine-Tune Basal Dose'),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'If your blood sugar is not stable between meals or overnight, make small '
            'adjustments here. Each step changes your basal by 1 unit and '
            'recalculates your ICR and ISF.',
            style: TextStyle(fontSize: 13, color: _C.textSecondary, height: 1.45),
          ),
        ),
        Row(children: [
          Expanded(child: Column(children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('BG often too low?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.textSecondary)),
            ),
            _Btn(label: '− Decrease by 1 unit', onPressed: () => _confirm(context, -1), variant: _BtnVariant.secondary),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('BG often too high?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.textSecondary)),
            ),
            _Btn(label: '+ Increase by 1 unit', onPressed: () => _confirm(context, 1), variant: _BtnVariant.secondary),
          ])),
        ]),
        const SizedBox(height: 12),
        const Text(
          'Always consult your healthcare provider before adjusting your insulin therapy.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: _C.textTertiary, height: 1.45),
        ),
      ]),
    );
  }
}

// ============================================================================
// MANUAL LOG DIALOG
// ============================================================================

class _ManualLogDialog extends StatefulWidget {
  final void Function(double units, DoseType type) onLog;
  const _ManualLogDialog({required this.onLog});

  @override
  State<_ManualLogDialog> createState() => _ManualLogDialogState();
}

class _ManualLogDialogState extends State<_ManualLogDialog> {
  final _units = TextEditingController();
  DoseType _type = DoseType.bolus;

  @override
  void dispose() { _units.dispose(); super.dispose(); }

  void _submit() {
    final u = double.tryParse(_units.text);
    if (u == null || u <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid dose in units.')),
      );
      return;
    }
    Navigator.pop(context);
    widget.onLog(u, _type);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Log a Manual Dose',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _C.textPrimary)),
            const SizedBox(height: 16),
            _LabeledInput(label: 'Dose Amount', controller: _units, hint: 'e.g. 5.0', unit: 'units'),
            const Text('Insulin Type',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _C.textPrimary)),
            const SizedBox(height: 6),
            _TypeSelector<DoseType>(
              options: const [DoseType.bolus, DoseType.basal],
              labels: const {DoseType.bolus: 'Bolus (rapid)', DoseType.basal: 'Basal (long-acting)'},
              value: _type,
              onChange: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _Btn(label: 'Cancel', onPressed: () => Navigator.pop(context), variant: _BtnVariant.secondary)),
              const SizedBox(width: 10),
              Expanded(child: _Btn(label: 'Log Dose', onPressed: _submit)),
            ]),
          ],
        ),
      ),
    );
  }
}
