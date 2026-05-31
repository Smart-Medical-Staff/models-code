import 'package:flutter/material.dart';

import 'weekly_deficiency_spotter_service.dart';

/// Patient-facing Weekly Deficiency Spotter UI.
///
/// Shows a weekly nutrition report card with flagged deficiencies,
/// food suggestions, and a summary of nutrient coverage.
class WeeklyDeficiencySpotterPage extends StatefulWidget {
  const WeeklyDeficiencySpotterPage({super.key});

  @override
  State<WeeklyDeficiencySpotterPage> createState() =>
      WeeklyDeficiencySpotterPageState();
}

class WeeklyDeficiencySpotterPageState
    extends State<WeeklyDeficiencySpotterPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  SpotterResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runSpotter();
  }

  /// Public method so parent can trigger a refresh when food is added.
  Future<void> refresh() => _runSpotter();

  Future<void> _runSpotter() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await WeeklyDeficiencySpotterService.evaluate();
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
            CircularProgressIndicator(color: Color(0xFF5C6BC0)),
            SizedBox(height: 16),
            Text(
              'Scanning your weekly nutrition…',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return _emptyState(
        Icons.error_outline,
        'Something went wrong',
        'Could not analyze your weekly nutrition.\nTap to retry.',
        onTap: _runSpotter,
      );
    }

    if (_result == null) {
      return _emptyState(
        Icons.calendar_today_outlined,
        'No meals logged yet',
        'Add your first meal in the Diet Plan tab\nand the weekly report will start building.',
        onTap: null,
      );
    }

    return RefreshIndicator(
      onRefresh: _runSpotter,
      color: const Color(0xFF5C6BC0),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildSummaryCard(),
            const SizedBox(height: 16),
            _buildCoverageGrid(),
            if (_result!.flaggedDeficiencies.isNotEmpty) ...[
              const SizedBox(height: 16),
              ..._result!.flaggedDeficiencies
                  .map((d) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildDeficiencyCard(d),
                      )),
            ],
            if (_result!.interactionFlags.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildInteractionsCard(),
            ],
            if (_result!.referralFlag) ...[
              const SizedBox(height: 12),
              _buildReferralBanner(),
            ],
            const SizedBox(height: 20),
            _buildDisclaimerText(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5C6BC0), Color(0xFF7986CB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5C6BC0).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.search_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Weekly Nutrition Report',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Color(0xFF1A237E),
                ),
              ),
              Text(
                'Week ending ${_result!.weekEnding} · ${_result!.daysLogged} days logged',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _runSpotter,
          icon: const Icon(Icons.refresh_rounded),
          color: const Color(0xFF5C6BC0),
          tooltip: 'Re-scan',
        ),
      ],
    );
  }

  // ─── Overall summary card ─────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    final hasFlagged = _result!.flaggedDeficiencies.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasFlagged
              ? [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)]
              : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasFlagged
              ? const Color(0xFFF48FB1)
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
                hasFlagged ? Icons.warning_amber : Icons.check_circle,
                color: hasFlagged
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFF43A047),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                hasFlagged ? 'Gaps Found' : 'Looking Good!',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: hasFlagged
                      ? const Color(0xFFC62828)
                      : const Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _result!.patientMessage,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF37474F),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Nutrient coverage grid ───────────────────────────────────────────────

  Widget _buildCoverageGrid() {
    final all = _result!.allCoverage.values.toList();

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
          _sectionTitle(Icons.grid_view, 'Nutrient Coverage'),
          const SizedBox(height: 14),
          ...all.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _coverageRow(c),
              )),
        ],
      ),
    );
  }

  Widget _coverageRow(NutrientCoverage c) {
    final pct = (c.coveragePct / 100).clamp(0.0, 1.5);
    final color = _bandColor(c.band);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.nutrient,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                if (c.recurring)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.repeat, size: 14, color: Color(0xFFE53935)),
                  ),
              ],
            ),
            Text(
              '${c.coveragePct.round()}%  ·  ${bandLabel(c.band)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: pct.toDouble(),
            minHeight: 7,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Color _bandColor(CoverageBand b) {
    switch (b) {
      case CoverageBand.adequate:
        return const Color(0xFF43A047);
      case CoverageBand.marginal:
        return const Color(0xFFFB8C00);
      case CoverageBand.deficient:
        return const Color(0xFFE53935);
      case CoverageBand.severelyDeficient:
        return const Color(0xFFB71C1C);
    }
  }

  // ─── Deficiency card ──────────────────────────────────────────────────────

  Widget _buildDeficiencyCard(FlaggedDeficiency d) {
    final c = d.coverage;
    final color = _bandColor(c.band);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      c.band == CoverageBand.severelyDeficient
                          ? Icons.warning
                          : Icons.flag,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      c.nutrient,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (c.recurring)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Recurring',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE53935),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            d.plainLanguageImpact,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          if (c.interactionNote != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.link, size: 14, color: Colors.amber.shade800),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    c.interactionNote!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Try this week:',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Color(0xFF37474F),
            ),
          ),
          const SizedBox(height: 6),
          ...d.foodSuggestions.map((fs) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.restaurant,
                      size: 14,
                      color: const Color(0xFF5C6BC0),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${fs.food} — ',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF37474F),
                              ),
                            ),
                            TextSpan(
                              text: fs.reason,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─── Interaction flags card ───────────────────────────────────────────────

  Widget _buildInteractionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.link, 'Nutrient Interactions'),
          const SizedBox(height: 10),
          ..._result!.interactionFlags.map((flag) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        flag,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─── Referral banner ──────────────────────────────────────────────────────

  Widget _buildReferralBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEF9A9A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_services, color: Color(0xFFD32F2F)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _result!.referralRationale ??
                  'Persistent nutrient gaps detected — consider speaking with your doctor about a dietary consultation.',
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFFC62828),
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared ───────────────────────────────────────────────────────────────

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
              'This is informational guidance based on your logged meals, not medical advice. '
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

  Widget _emptyState(IconData icon, String title, String subtitle,
      {VoidCallback? onTap}) {
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
                color: const Color(0xFF5C6BC0).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: const Color(0xFF5C6BC0)),
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
        Icon(icon, size: 18, color: const Color(0xFF5C6BC0)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Color(0xFF5C6BC0),
          ),
        ),
      ],
    );
  }
}
