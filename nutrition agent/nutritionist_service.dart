import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/food_response_model.dart';
import '../../services/patient_profile_service.dart';

/// Service that powers the Nutritionist agent.
///
/// Strategy:
/// 1. Include the patient's profile data (weight, diabetes type, allergies,
///    etc.) from [PatientProfileService] so the AI provides personalized advice.
/// 2. Send the food query directly to the Cloudflare Worker (which proxies to
///    Llama 3.3 70B via Cloudflare AI) — the AI uses its own nutritional
///    knowledge to assess the food.
/// 3. Return the structured [FoodResponse] to the UI.
///
/// **Security:** No API keys live in this file.  All secrets are stored in
/// Cloudflare Workers Secrets and never exposed to the client.
class NutritionistService {
  // ─────────────────────────────────────────────────────────────────────────
  // Cloudflare Worker URL
  // ─────────────────────────────────────────────────────────────────────────
  static const String _workerUrl =
      'https://nutriguard-agent.smartmedicalstaff.workers.dev';

  /// Query the Nutritionist agent for a given [foodName].
  ///
  /// [language] — "en" or "ar". Auto-detected from the app's locale if null.
  static Future<FoodResponse> checkFood(
    String foodName, {
    String language = 'en',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString('patientId') ?? 'anonymous';

    // ── Load patient profile for personalized AI context ─────────────────
    final patientProfile = await PatientProfileService.instance.load();
    final patientContext = patientProfile.isComplete
        ? '\nPATIENT PROFILE:\n${patientProfile.toAiContext()}\n'
        : '';

    final userMessage = '''
Patient query language: $language
Food item the patient wants to eat: "$foodName"
$patientContext
Please assess this food for a diabetic patient and respond following your instructions.
Provide complete and accurate nutritional values per 100g from your medical knowledge.
''';

    // ── Cloudflare Worker call ─────────────────────────────────────────────
    final response = await http.post(
      Uri.parse('$_workerUrl/agent/nutritionist/check'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'food_name': foodName,
        'language': language,
        'patient_id': patientId,
        'db_context': '',
        'user_message': userMessage,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return FoodResponse(
        isSuitable: data['is_suitable'] as bool?,
        message: data['message'] as String? ?? '',
        source: 'ai',
      );
    }

    throw Exception('Nutritionist agent error: HTTP ${response.statusCode}');
  }
}
