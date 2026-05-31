/// Data model for the NutriGuard AI agent's response.
class FoodResponse {
  /// null if food was not found in DB (Claude determined it).
  final bool? isSuitable;

  /// Full agent response in Markdown format (bilingual).
  final String message;

  /// "database" if food was found in local DB, "claude" otherwise.
  final String source;

  /// Raw Supabase row data for the matched food (null if not found in DB).
  /// Contains all 39 nutritional columns so the UI can build a FoodItem.
  final Map<String, dynamic>? foodData;

  const FoodResponse({
    required this.isSuitable,
    required this.message,
    required this.source,
    this.foodData,
  });

  factory FoodResponse.fromJson(Map<String, dynamic> json) {
    return FoodResponse(
      isSuitable: json['is_suitable'] as bool?,
      message: json['message'] as String? ?? '',
      source: json['source'] as String? ?? 'claude',
      foodData: json['food_data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'is_suitable': isSuitable,
        'message': message,
        'source': source,
        'food_data': foodData,
      };
}
