import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'nutritionist_service.dart';
import 'models/food_response_model.dart';
import 'widgets/agent_bubble.dart';

// ─── Message model ─────────────────────────────────────────────────────────

class _Message {
  final bool isUser;
  final String text;
  final bool? isSuitable;
  final bool isLoading;
  final Map<String, dynamic>? foodData;
  final String? foodName;
  final double? grams;

  const _Message({
    required this.isUser,
    required this.text,
    this.isSuitable,
    this.isLoading = false,
    this.foodData,
    this.foodName,
    this.grams,
  });
}

// ─── Main page ─────────────────────────────────────────────────────────────

class NutritionistAgentPage extends StatefulWidget {
  final bool showAppBar;
  /// Called when the user taps "Add to Diet Plan" on a food response.
  /// Passes (foodName, grams, rawSupabaseRow, agentMessage).
  final void Function(String foodName, double grams, Map<String, dynamic> foodData, String agentMessage)? onAddToDiet;

  const NutritionistAgentPage({
    super.key,
    this.showAppBar = true,
    this.onAddToDiet,
  });

  @override
  State<NutritionistAgentPage> createState() => _NutritionistAgentPageState();
}

class _NutritionistAgentPageState extends State<NutritionistAgentPage>
    with SingleTickerProviderStateMixin {
  final List<_Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isLoading = false;
  late final AnimationController _fadeCtrl;

  // Language auto-detection (simple heuristic: if input contains Arabic chars)
  String _detectLang(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text) ? 'ar' : 'en';
  }

  bool _isArabic = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeCtrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isArabic = Localizations.localeOf(context).languageCode == 'ar';

    if (_messages.isEmpty) {
      _messages.add(_Message(
        isUser: false,
        text: _isArabic
            ? 'مرحباً! أنا **Nutritionist**\n\n'
              'مساعدك الغذائي لمرضى السكري.\n'
              'اكتب اسم أي طعام وسأقوم بتقييمه لك فوراً.\n\n'
              'استشر طبيبك دائماً قبل إجراء أي تغييرات في نظامك الغذائي.'
            : 'Hello! I\'m **Nutritionist**\n\n'
              'Your diabetes nutrition assistant.\n'
              'Type any food name and I\'ll assess it instantly.\n\n'
              'Always consult your doctor before making dietary changes.',
        isSuitable: null,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendQuery(String foodName) async {
    final query = foodName.trim();
    if (query.isEmpty) return;

    final lang = _detectLang(query);

    setState(() {
      _messages.add(_Message(isUser: true, text: query));
      _messages.add(const _Message(isUser: false, text: '', isLoading: true));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final FoodResponse result =
          await NutritionistService.checkFood(query, language: lang);

      // Try to extract grams from the user query (e.g. "123g chicken", "chicken 200 grams")
      double parsedGrams = 100; // default to 100g
      final gramsMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:g(?:ram(?:s)?)?|جرام)\b', caseSensitive: false).firstMatch(query);
      if (gramsMatch != null) {
        parsedGrams = double.tryParse(gramsMatch.group(1)!) ?? 100;
      }

      setState(() {
        _messages.removeLast(); // remove loading bubble
        _messages.add(_Message(
          isUser: false,
          text: result.message,
          isSuitable: result.isSuitable,
          foodData: {'food_name': query},
          foodName: query,
          grams: parsedGrams,
        ));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(_Message(
          isUser: false,
          text: _isArabic 
              ? 'عذراً، تعذر الاتصال بالخادم.\n\nيرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.\n\nالخطأ: $e'
              : 'Sorry, I couldn\'t reach the server.\n\n'
                'Please check your internet connection and try again.\n\n'
                'Error: $e',
          isSuitable: null,
        ));
        _isLoading = false;
      });
    }

    _scrollToBottom();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: Column(
        children: [
          Expanded(
            child: FadeTransition(
              opacity: _fadeCtrl,
              child: ListView.builder(
                controller: _scrollCtrl,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final msg = _messages[i];
                  if (msg.isUser) {
                    return UserBubble(text: msg.text);
                  }
                  return AgentBubble(
                    isSuitable: msg.isSuitable,
                    message: msg.text,
                    isLoading: msg.isLoading,
                    onAddToDiet: (msg.foodData != null && widget.onAddToDiet != null)
                        ? () => widget.onAddToDiet!(
                              msg.foodName ?? '',
                              msg.grams ?? 100,
                              msg.foodData!,
                              msg.text,
                            )
                        : null,
                    onSaveToLog: msg.isSuitable == true
                        ? () => _showSavedSnack()
                        : null,
                    onAskDoctor: () => _launchDoctorEscalation(),
                  );
                },
              ),
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A237E)),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF43A047), Color(0xFF00ACC1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(Icons.restaurant_menu, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nutritionist',
                style: TextStyle(
                  color: Color(0xFF1A237E),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _isLoading 
                    ? (_isArabic ? 'جاري تحليل الطعام...' : 'Analysing your food…') 
                    : (_isArabic ? 'مساعد التغذية لمرضى السكري' : 'Diabetes Nutrition Agent'),
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Color(0xFF43A047)),
          onPressed: _showInfoDialog,
          tooltip: 'About Nutritionist',
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: Colors.grey.shade200,
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding:
          EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: _controller,
                textDirection: TextDirection.ltr,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  hintText: _isArabic ? 'اكتب اسم طعام...' : 'Type a food name…',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 13),
                  suffixIcon: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onSubmitted: _sendQuery,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SendButton(
            isLoading: _isLoading,
            onTap: () => _sendQuery(_controller.text),
          ),
        ],
      ),
    );
  }

  void _showSavedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(_isArabic ? 'تم الحفظ في سجل الطعام' : 'Saved to your Food Log'),
          ],
        ),
        backgroundColor: const Color(0xFF43A047),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _launchDoctorEscalation() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isArabic ? 'جاري فتح رسائل طبيبك...' : 'Opening your Doctor messages…'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );
    // In production: Navigator.push to the doctor messaging page.
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.info, size: 24),
            const SizedBox(width: 8),
            Text(_isArabic ? 'عن Nutritionist' : 'About Nutritionist',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          _isArabic
              ? 'Nutritionist هو مساعدك الغذائي لمرضى السكري، مدعوم بالذكاء الاصطناعي وقاعدة بيانات موثوقة تضم 3,950 طعاماً.\n\n'
                'يقيم ملاءمة الطعام بناءً على:\n'
                '• المؤشر الجلايسيمي (إرشادات ADA)\n'
                '• محتوى السكر والكربوهيدرات\n'
                '• الصوديوم والدهون المشبعة والألياف\n\n'
                'المصادر: ADA 2024 · منظمة الصحة العالمية · وزارة الزراعة الأمريكية · جامعة سيدني\n\n'
                'توفر هذه الأداة إرشادات غذائية فقط — وليس تشخيصاً طبياً.'
              : 'Nutritionist is your diabetes nutrition assistant, powered by AI and a '
                'validated database of 3,950 foods.\n\n'
                'It assesses food suitability based on:\n'
                '• Glycemic Index (ADA guidelines)\n'
                '• Sugar & carbohydrate content\n'
                '• Sodium, saturated fat, fiber\n\n'
                'Sources: ADA 2024 · WHO · USDA · '
                'University of Sydney\n\n'
                'This tool provides food guidance only — not medical diagnosis.',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_isArabic ? 'حسناً' : 'Got it'),
          ),
        ],
      ),
    );
  }
}

// ─── Send button ──────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _SendButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: isLoading
              ? const LinearGradient(
                  colors: [Colors.grey, Colors.grey])
              : const LinearGradient(
                  colors: [Color(0xFF43A047), Color(0xFF00ACC1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isLoading
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF43A047).withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}
