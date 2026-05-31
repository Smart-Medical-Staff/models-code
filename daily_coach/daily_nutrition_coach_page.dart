import 'package:flutter/material.dart';

import 'daily_nutrition_coach_service.dart';
import '../../patient/diseases/diet_plan/services/diet_storage_service.dart';

/// The Daily Nutrition Coach card UI.
///
/// Shows the patient a concise daily coaching message based on their
/// logged meals vs. personal targets. Implements the patient-facing
/// card from the Daily Nutrition Coach agent spec.
class DailyNutritionCoachPage extends StatefulWidget {
  const DailyNutritionCoachPage({super.key});

  @override
  State<DailyNutritionCoachPage> createState() =>
      DailyNutritionCoachPageState();
}

class DailyNutritionCoachPageState extends State<DailyNutritionCoachPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final DietStorageService _storage = DietStorageService();
  CoachResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runCoach();
  }

  /// Public method so parent can trigger a refresh when food is added.
  Future<void> refresh() => _runCoach();

  Future<void> _runCoach() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dailyLog = await _storage.loadDailyLog();
      final result = await DailyNutritionCoachService.evaluate(
        dailyLog: dailyLog,
      );

      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00897B)),
            SizedBox(height: 16),
            Text(
              'Analyzing your meals…',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return _buildEmptyState(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        subtitle: 'Could not analyze your meals.\nTap to retry.',
        onTap: _runCoach,
      );
    }

    if (_result == null) {
      return _buildEmptyState(
        icon: Icons.restaurant_outlined,
        title: 'No meals logged yet',
        subtitle:
            'Add your first meal in the Diet Plan tab\nand the coach will start analyzing your day.',
        onTap: null,
      );
    }

    return RefreshIndicator(
      onRefresh: _runCoach,
      color: const Color(0xFF00897B),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildCoachHeader(),
            const SizedBox(height: 20),
            _buildMessageCard(),
            const SizedBox(height: 16),
            _buildMacroComparisonCard(),
            if (_result!.primaryDeviation != null) ...[
              const SizedBox(height: 16),
              _buildDeviationCard(),
            ],
            if (_result!.suggestion != null) ...[
              const SizedBox(height: 16),
              _buildSuggestionCard(),
            ],
            const SizedBox(height: 24),
            _buildDisclaimerText(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────

  Widget _buildCoachHeader() {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00897B), Color(0xFF26A69A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00897B).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.psychology, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Daily Nutrition Coach',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF1A237E),
                ),
              ),
              Text(
                _result!.date,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _runCoach,
          icon: const Icon(Icons.refresh_rounded),
          color: const Color(0xFF00897B),
          tooltip: 'Re-analyze',
        ),
      ],
    );
  }

  // ─── Main coaching message card ──────────────────────────────────────────

  Widget _buildMessageCard() {
    final hasDeviation = _result!.primaryDeviation != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasDeviation
              ? [const Color(0xFFFFF8E1), const Color(0xFFFFF3E0)]
              : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasDeviation
              ? const Color(0xFFFFE082)
              : const Color(0xFFA5D6A7),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasDeviation ? Icons.tips_and_updates : Icons.celebration,
                color: hasDeviation
                    ? const Color(0xFFF9A825)
                    : const Color(0xFF43A047),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                hasDeviation ? 'Today\'s Coaching' : 'Great Day!',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: hasDeviation
                      ? const Color(0xFFF57F17)
                      : const Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _result!.message,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.65,
              color: Color(0xFF37474F),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Macro comparison grid ────────────────────────────────────────────────

  Widget _buildMacroComparisonCard() {
    final s = _result!.summary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.bar_chart, 'Today vs. Targets'),
          const SizedBox(height: 14),
          _macroRow('Calories', s.actualCalories, s.targetCalories, 'kcal',
              const Color(0xFFE53935)),
          const SizedBox(height: 10),
          _macroRow('Carbs', s.actualCarbs, s.targetCarbs, 'g',
              const Color(0xFFFB8C00)),
          const SizedBox(height: 10),
          _macroRow('Protein', s.actualProtein, s.targetProtein, 'g',
              const Color(0xFF43A047)),
          const SizedBox(height: 10),
          _macroRow('Fat', s.actualFat, s.targetFat, 'g',
              const Color(0xFF1E88E5)),
        ],
      ),
    );
  }

  Widget _macroRow(
      String label, double actual, double target, String unit, Color color) {
    final pct = target > 0 ? (actual / target).clamp(0.0, 2.0) : 0.0;
    final delta = actual - target;
    final overUnder = delta > 0 ? '+' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(
              '${actual.round()} / ${target.round()} $unit  ($overUnder${delta.round()})',
              style: TextStyle(
                fontSize: 12,
                color: delta.abs() / (target == 0 ? 1 : target) > 0.15
                    ? const Color(0xFFE53935)
                    : const Color(0xFF43A047),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct.toDouble(),
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(
              pct > 1.15 ? const Color(0xFFE53935) : color,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Deviation detail card ────────────────────────────────────────────────

  Widget _buildDeviationCard() {
    final d = _result!.primaryDeviation!;
    final direction = d.deltaPercent > 0 ? 'over' : 'under';
    final unit = d.macro == 'calories' ? 'kcal' : 'g';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFCC80),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.flag_rounded, 'Primary Deviation'),
          const SizedBox(height: 12),
          _detailRow('Macro', d.macro.toUpperCase()),
          _detailRow('Actual', '${d.actualValue.round()} $unit'),
          _detailRow('Target', '${d.targetValue.round()} $unit'),
          _detailRow('Deviation', '${d.deltaPercent.abs().round()}% $direction'),
          _detailRow('Source', '${d.responsibleMeal} → ${d.responsibleFood}'),
        ],
      ),
    );
  }

  // ─── Swap suggestion card ─────────────────────────────────────────────────

  Widget _buildSuggestionCard() {
    final s = _result!.suggestion!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF80CBC4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.swap_horiz, 'Suggested Swap'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _swapChip(s.swapFrom, const Color(0xFFE53935), Icons.close),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, color: Color(0xFF00897B)),
              ),
              Expanded(
                child: _swapChip(s.swapTo, const Color(0xFF43A047), Icons.check),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s.rationale,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _swapChip(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Disclaimer ───────────────────────────────────────────────────────────

  Widget _buildDisclaimerText() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This is informational guidance, not medical advice. '
              'Always consult your doctor or dietitian before making major diet changes.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared helpers ───────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF00897B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: const Color(0xFF00897B)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Color(0xFF37474F),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF00897B)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Color(0xFF00897B),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade600)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF37474F))),
        ],
      ),
    );
  }
}
