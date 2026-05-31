/// HbA1c Estimator — Flutter (Dart)
///
/// Single-file implementation. Drop into your Flutter project and push
/// `HbA1cEstimatorScreen()` from any navigator.
///
/// Estimates HbA1c (%) from a series of blood glucose readings (mg/dL)
/// using the standard regression:    HbA1c = (MBG + 46.7) / 28.7
/// where MBG is the mean of all readings.
///
/// One optional dependency (only for persistence — remove if not needed):
///   flutter pub add shared_preferences

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// FORMULA — pure, no Flutter dependency
// ============================================================================

/// Estimated HbA1c (%) from Mean Blood Glucose in mg/dL.
double mbgToHbA1c(double mbgMgDl) => (mbgMgDl + 46.7) / 28.7;

class HbA1cInterpretation {
  final String label;
  final Color color;
  const HbA1cInterpretation(this.label, this.color);
}

/// Clinical interpretation based on ADA HbA1c thresholds.
HbA1cInterpretation interpretHbA1c(double hba1c) {
  if (hba1c < 5.7) return const HbA1cInterpretation('Normal', Color(0xFF16A34A));
  if (hba1c < 6.5) return const HbA1cInterpretation('Prediabetes', Color(0xFFF59E0B));
  return const HbA1cInterpretation('Diabetes', Color(0xFFDC2626));
}

// ============================================================================
// STORAGE
// ============================================================================

const String _storageKey = 'hba1c_glucose_readings';

Future<List<double>> _loadReadings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return <double>[];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => (e as num).toDouble()).toList();
  } catch (_) {
    return <double>[];
  }
}

Future<void> _saveReadings(List<double> readings) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_storageKey, jsonEncode(readings));
}

// ============================================================================
// MAIN SCREEN
// ============================================================================

class HbA1cEstimatorScreen extends StatefulWidget {
  const HbA1cEstimatorScreen({super.key});

  @override
  State<HbA1cEstimatorScreen> createState() => _HbA1cEstimatorScreenState();
}

class _HbA1cEstimatorScreenState extends State<HbA1cEstimatorScreen> {
  final List<double> _readings = [];
  final TextEditingController _input = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadReadings().then((r) {
      if (!mounted) return;
      setState(() {
        _readings.addAll(r);
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _persist() {
    if (_loaded) _saveReadings(List<double>.from(_readings));
  }

  void _handleAdd() {
    final v = double.tryParse(_input.text.trim());
    if (v == null || v < 20 || v > 800) {
      _showAlert('Invalid reading', 'Enter a glucose value between 20 and 800 mg/dL.');
      return;
    }
    setState(() {
      _readings.add(v);
      _input.clear();
    });
    _persist();
  }

  void _handleRemove(int index) {
    setState(() => _readings.removeAt(index));
    _persist();
  }

  void _handleClearAll() {
    if (_readings.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Readings'),
        content: Text('Remove all ${_readings.length} readings?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _readings.clear());
              _persist();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showAlert(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasReadings = _readings.isNotEmpty;
    final mbg = hasReadings ? _readings.reduce((a, b) => a + b) / _readings.length : 0.0;
    final hba1c = hasReadings ? mbgToHbA1c(mbg) : 0.0;
    final interp = hasReadings ? interpretHbA1c(hba1c) : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('HbA1c Estimator',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  SizedBox(height: 4),
                  Text('Estimate HbA1c from glucose readings',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  children: [
                    // Result card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          const Text('ESTIMATED HBA1C',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          Text(hasReadings ? '${hba1c.toStringAsFixed(2)}%' : '—',
                              style: const TextStyle(
                                  fontSize: 56, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                          if (interp != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: interp.color,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(interp.label,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ],
                          const SizedBox(height: 20),
                          const Divider(color: Color(0xFFE2E8F0), height: 1),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _Stat(
                                    label: 'Mean Glucose',
                                    value: hasReadings ? mbg.toStringAsFixed(1) : '—',
                                    unit: 'mg/dL'),
                              ),
                              Expanded(
                                child: _Stat(
                                    label: 'Readings',
                                    value: '${_readings.length}',
                                    unit: 'entries'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Input card
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Add Glucose Reading (mg/dL)',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _handleAdd(),
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. 132',
                                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _handleAdd,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 22),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  child: const Text('Add',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text('Tip: 90+ readings give a clinically meaningful estimate.',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),

                    // Readings list header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Readings',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          if (hasReadings)
                            GestureDetector(
                              onTap: _handleClearAll,
                              child: const Text('Clear All',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFDC2626),
                                      fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                    ),

                    if (!hasReadings)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          'No readings yet — add your first glucose value above.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: List.generate(_readings.length, (i) {
                            final isLast = i == _readings.length - 1;
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        child: Text('${i + 1}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF94A3B8),
                                                fontWeight: FontWeight.w700)),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text('${_readings[i]} mg/dL',
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A))),
                                      ),
                                      GestureDetector(
                                        onTap: () => _handleRemove(i),
                                        behavior: HitTestBehavior.opaque,
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Text('✕',
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  color: Color(0xFF94A3B8),
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 54),
                                    child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                                  ),
                              ],
                            );
                          }),
                        ),
                      ),

                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: Text(
                        'This is an estimate based on the standard MBG → HbA1c regression. '
                        'It is not a substitute for laboratory testing or medical advice.',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                            fontStyle: FontStyle.italic,
                            height: 1.45),
                        textAlign: TextAlign.center,
                      ),
                    ),
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _Stat({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        Text(unit, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
      ],
    );
  }
}
