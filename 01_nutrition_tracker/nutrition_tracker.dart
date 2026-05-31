/// Smart Nutrition Tracker — Flutter (Dart)
///
/// Single-file implementation. Drop into your Flutter project and push
/// `NutritionTrackerScreen()` from any navigator.
///
/// One dependency required:
///   flutter pub add shared_preferences

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// COLOURS
// ============================================================================

class _C {
  static const lime      = Color(0xFF84CC16);
  static const limeLight = Color(0xFFF7FEE7);
  static const green     = Color(0xFF16A34A);
  static const red       = Color(0xFFF87171);
  static const orange    = Color(0xFFFB923C);
  static const blue      = Color(0xFF60A5FA);
  static const bg        = Color(0xFFF1F5F9);
  static const surface   = Color(0xFFFFFFFF);
  static const border    = Color(0xFFE2E8F0);
  static const txt       = Color(0xFF1E293B);
  static const txtSub    = Color(0xFF64748B);
  static const txtMuted  = Color(0xFF94A3B8);
}

// ============================================================================
// TYPES
// ============================================================================

class FoodItem {
  final String name;
  final double cal;   // kcal per 100g
  final double pro;   // protein g
  final double fat;   // fat g
  final double carb;  // carbs g
  final double fib;   // fiber g
  final double ca;    // calcium mg
  final double mg;    // magnesium mg
  final double k;     // potassium mg
  final double na;    // sodium mg
  const FoodItem(this.name, this.cal, this.pro, this.fat, this.carb,
      this.fib, this.ca, this.mg, this.k, this.na);

  Map<String, dynamic> toJson() => {
        'name': name,
        'cal': cal, 'pro': pro, 'fat': fat, 'carb': carb, 'fib': fib,
        'ca': ca, 'mg': mg, 'k': k, 'na': na,
      };

  static FoodItem fromJson(Map<String, dynamic> j) => FoodItem(
        j['name'] as String,
        (j['cal'] as num).toDouble(),
        (j['pro'] as num).toDouble(),
        (j['fat'] as num).toDouble(),
        (j['carb'] as num).toDouble(),
        (j['fib'] as num).toDouble(),
        (j['ca'] as num).toDouble(),
        (j['mg'] as num).toDouble(),
        (j['k'] as num).toDouble(),
        (j['na'] as num).toDouble(),
      );
}

enum Gender { male, female }
enum ActivityLevel { sedentary, lightlyActive, moderatelyActive, veryActive }
enum Goal { lose, maintain, gain }

class UserProfile {
  final String name;
  final Gender gender;
  final String birthday;       // YYYY-MM-DD
  final double heightCm;
  final double weightKg;
  final double targetWeightKg;
  final ActivityLevel activityLevel;
  const UserProfile({
    required this.name,
    required this.gender,
    required this.birthday,
    required this.heightCm,
    required this.weightKg,
    required this.targetWeightKg,
    required this.activityLevel,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'gender': gender.name,
        'birthday': birthday,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'targetWeightKg': targetWeightKg,
        'activityLevel': activityLevel.name,
      };

  static UserProfile fromJson(Map<String, dynamic> j) => UserProfile(
        name: j['name'] as String,
        gender: Gender.values.firstWhere((e) => e.name == j['gender'],
            orElse: () => Gender.female),
        birthday: j['birthday'] as String,
        heightCm: (j['heightCm'] as num).toDouble(),
        weightKg: (j['weightKg'] as num).toDouble(),
        targetWeightKg: (j['targetWeightKg'] as num).toDouble(),
        activityLevel: ActivityLevel.values.firstWhere((e) => e.name == j['activityLevel'],
            orElse: () => ActivityLevel.moderatelyActive),
      );
}

class MealEntry {
  final String id;
  final FoodItem food;
  final double grams;
  const MealEntry({required this.id, required this.food, required this.grams});

  Map<String, dynamic> toJson() =>
      {'id': id, 'food': food.toJson(), 'grams': grams};

  static MealEntry fromJson(Map<String, dynamic> j) => MealEntry(
        id: j['id'] as String,
        food: FoodItem.fromJson(j['food'] as Map<String, dynamic>),
        grams: (j['grams'] as num).toDouble(),
      );
}

enum MealName { breakfast, lunch, dinner, snacks }

extension MealNameX on MealName {
  String get label {
    switch (this) {
      case MealName.breakfast: return 'Breakfast';
      case MealName.lunch:     return 'Lunch';
      case MealName.dinner:    return 'Dinner';
      case MealName.snacks:    return 'Snacks';
    }
  }
}

class DailyLog {
  final String date;
  final Map<MealName, List<MealEntry>> meals;
  const DailyLog({required this.date, required this.meals});

  Map<String, dynamic> toJson() => {
        'date': date,
        'meals': {
          for (final m in MealName.values)
            m.name: (meals[m] ?? []).map((e) => e.toJson()).toList(),
        },
      };

  static DailyLog fromJson(Map<String, dynamic> j) {
    final raw = (j['meals'] as Map<String, dynamic>?) ?? const {};
    final meals = <MealName, List<MealEntry>>{};
    for (final m in MealName.values) {
      final lst = raw[m.name] as List<dynamic>?;
      meals[m] = lst == null
          ? <MealEntry>[]
          : lst.map((e) => MealEntry.fromJson(e as Map<String, dynamic>)).toList();
    }
    return DailyLog(date: j['date'] as String, meals: meals);
  }
}

class Calculations {
  final double bmi;
  final Goal goal;
  final int tdee;
  final int adjustedTdee;
  final Map<MealName, int> mealLimits;
  final int targetCarbs, targetProtein, targetFat;
  final int totalCal, totalCarbs, totalProtein, totalFat;
  final Map<MealName, int> perMeal;
  const Calculations({
    required this.bmi, required this.goal, required this.tdee, required this.adjustedTdee,
    required this.mealLimits,
    required this.targetCarbs, required this.targetProtein, required this.targetFat,
    required this.totalCal, required this.totalCarbs, required this.totalProtein, required this.totalFat,
    required this.perMeal,
  });
}

// ============================================================================
// FOOD DATABASE  (~512 items)
// Format per line: name|cal|pro|fat|carb|fib|ca|mg|k|na  (all per 100 g)
// ============================================================================

const String _foodDb = r'''
abalone|89|15.4|0.637|5.416|0|26.4|40.8|212.5|0.3
abiyuch|157|3.036|0.179|35.812|12.1|18.2|54.7|693.1|0.093
acai (brazil)|41|0.82|0|9.43|5|91|18|113|103
acai berries|200|0|0|50|12|53|65|500|317
acerola cherries|143|4.4|2.2|26.4|4|24|38|383|304
acerola cherry|2|0.066|0.044|0.336|0.077|0|0.021|0.5|0.088
acerola cherry juice|56|0.988|0.691|11.457|0.7|24.2|29|234.7|0.082
acorn dried|144|2.207|8.538|14.582|0|15.3|23.2|200.6|0
acorn flour|626|0|0|100|0|53.8|137.5|890|0
acorn raw|110|1.64|6.561|11.096|0|11.6|17.5|152.5|0
acorn squash cooked|115|2.011|0.262|26.148|9|90.2|88.2|895.9|0.5
acorn squash raw|172|2.972|0.35|39.242|6.5|142.2|137.9|1495.6|0.017
acorns (north america)|184|2.191|8.762|24.095|13|115|61|206|12
adobo fresco|780|0|86.667|0|3.7|354.2|66.2|538.6|49.4
adzuki beans|475|0|52.778|0|0|93|162|332|392
adzuki beans (japan, china)|219|16.724|15.131|3.982|3|18|25|417|275
adzuki beans cooked|294|17.011|0.197|56.047|16.8|0|4.6|386.4|0.079
adzuki beans raw|648|97.206|2.486|0.308|25|130|250.2|2470.4|0.06
after eight mints nestle|36|0.099|0.994|6.663|0.2|1.1|0|0|0.025
agar|1|0.027|0.03|0.155|0.027|0.075|0.046|0.3|0.049
agar-agar|47|0|0|11.75|13|158|16|434|95
agave syrup|21|0.024|0.077|5.052|0.01|0.088|0.034|0.3|0.09
alaska king crab cooked|130|27.486|2.229|0|0|79.1|84.4|351.1|1.4
alaska king crab raw|144|33.6|1.067|0|0|79.1|84.3|350.9|1.4
alfalfa seeds|1|0.092|0.069|0.002|0.015|1|0.8|2.4|0.048
allspice|567|0|63|0|2|312|35|588|93
allspice ground|5|0.064|0.128|0.897|0.4|12.6|2.6|19.8|0.001
almond butter|614|18.863|51.874|17.92|11.6|268|303|749|0
almond flour|268|15.041|10.939|27.347|8|94|30|307|12
almond granola bar|119|1.76|5.965|14.569|1.2|7.7|19.4|65.5|0.067
almond meal|556|0|61.778|0|12|345|97|766|106
almond milk|39|1.054|3.162|1.581|0.6|113|12|170|186
almond milk (unsweetened)|388|0|43.111|0|6|445|59|727|112
almond oil|292|8.95|23.494|11.188|6|308|47|723|273
almond paste|900|0|100|0|10.9|390.4|295.1|712.8|0.051
almond rice bar|128|1.944|5.54|17.591|1|20.7|19.9|64.1|0
almonds|579|19.788|46.578|20.162|12.5|264|270|733|1
almonds raw|9|0.31|0.724|0.31|0.2|4|4|10.6|0.043
almonds roasted|182|5.937|15.399|4.916|3.2|87.3|82.2|209.7|0.029
aloo gobi|180|0|0|45|5|60|30|500|400
aloo paratha|320|8|12|45|5|45|28|410|460
amaranth|155|0|0|38.75|2|164|36|595|106
amaranth (north america)|39|0|0|9.75|5|196|60|323|378
amaranth cooked|251|9.108|3.819|45.049|5.2|115.6|159.9|332.1|0.095
amaranth flakes|134|5.071|2.321|23.207|3.6|6.5|9.5|134.1|0.067
amaranth flour|77|9.625|0|9.625|4|120|42|233|330
amaranth grain (mexico, peru)|180|0|0|45|3|32|65|295|140
amaranth greens (various african countries)|180|9|0|36|14|29|55|274|103
amaranth leaves|6|0.533|0.057|0.838|0|60.2|15.4|171.1|0.071
amaranth raw|37|1.367|0.683|6.346|0.7|15.9|24.8|50.8|0.077
american cheese|93|4.515|7.926|0.903|0|261.3|6.5|33|0.4
american cheese spread|46|2.567|3.356|1.382|0|89.9|4.6|38.7|0.3
american grapes|2|0.028|0.069|0.317|0.09|0.3|0.1|4.6|0.056
american shad cooked|363|0|40.333|0|0|86.4|54.7|708.5|0.043
american shad raw|362|32.041|25.982|0|0|86.5|55.2|706.6|0.001
amp energy pepsi|110|0.549|0.183|26.539|0|31.2|7.2|7.2|0.093
amp energy sugar free pepsi|5|0|0|1.25|0|0|7.2|4.8|0.093
anasazi beans|187|0|0|46.75|9|189|13|211|397
ancho pepper dried|48|1.733|1.213|7.538|3.7|10.4|19.2|409.9|0.068
anchovy canned in oil|8|1.143|0.381|0|0|9.3|2.8|21.8|0.1
anchovy raw|37|5.994|1.447|0|0|41.6|11.6|108.4|0.012
anejo cheese|492|90|10|0|0|897.6|37|114.8|1.5
angel food cake|72|1.668|0.196|15.891|0.4|39.2|3.4|26|0.2
anise|459|0|0|100|5|154|60|273|157
anise seed|337|17.6|15.9|50|14.6|646|170|1441|16
anjeer (fig, dried)|249|3.3|0.93|63.87|9.8|162|68|680|10
apple|52|0.264|0.176|12.339|2.4|6|9.1|107|1
apple butter|175|0|0|43.75|1|12|5|106|4
apple chips|365|1|0|91.25|6|20|8|280|55
apple cider|47|0|0|11.75|0|7|5|101|7
apple cider vinegar|21|0|0|0.93|0|7|5|73|5
apple juice|114|0.197|0.296|27.636|0.5|0|12.4|17.4|0.082
apple pie|237|2.054|11.147|34.069|1.5|12|9|89|253
apples|87|0|0|21.75|10|127|97|241|92
apricot|48|1.4|0.39|11.12|2|13|10|259|1
apricot dried|241|3.39|0.51|62.64|7.3|55|32|1162|10
apricot jam|250|0.4|0.1|65|0.8|20|8|130|32
apricot nectar|56|0.375|0.105|13.788|0.5|8|7|114|4
arancini|185|5|7|26|2|80|22|260|450
argan oil|884|0|100|0|0|0|0|0|0
artichoke|47|3.27|0.15|10.51|5.4|44|60|370|94
artichoke hearts|36|2.5|0.2|7.5|4.8|21|42|354|94
artichoke pasta|369|14|2|72|3.5|32|48|280|10
arugula|25|2.58|0.66|3.65|1.6|160|47|369|27
asparagus|20|2.2|0.12|3.88|2.1|24|14|202|2
asparagus cooked|22|2.4|0.22|4.11|1.8|23|12|224|14
avocado|160|1.788|13.408|8.045|7|12|78.3|485|7
avocado oil|884|0|100|0|0|0|0|0|0
bacon|106|3.306|10.219|0.2|0|1|3.1|131.6|0.1
bacon cooked|43|3.569|3.161|0.069|0|0|3.1|47.8|0
bagel|272|10|1.3|56|2.3|30|22|107|426
baguette|270|9|1|55|2.7|28|25|110|450
baked beans|155|9.7|0.5|27.2|7.7|56|37|296|422
baked potato|97|2.57|0.1|22.6|2.2|15|28|535|17
baklava|428|6|23|54|3|50|28|250|196
banana|96|1.075|0.196|22.485|2.6|5|40.5|358|1
banana bread|326|5|13|49|1.5|36|20|150|255
banana chips|519|2.3|33.6|58.4|6.8|18|54|536|6
barley|354|12.48|2.3|73.48|17.3|33|133|452|12
barley cooked|123|2.26|0.44|28.2|3.8|11|22|93|3
basil|22|3.15|0.64|2.65|1.6|177|64|295|4
basil dried|251|22.98|4.07|47.75|37.7|2240|422|2630|76
basmati rice cooked|130|2.7|0.3|28.2|0.4|5|8|68|325
bay leaves|313|7.61|8.36|74.97|26.3|834|120|529|23
bean sprouts|30|3.14|0.18|5.94|1.8|13|21|149|6
beef brisket cooked|295|28.4|19.6|0|0|11|19|285|57
beef burger cooked|295|26|19|0|0|18|20|310|65
beef gravy|123|8.289|5.24|10.671|0.9|14|4.7|188.7|1.5
beef jerky|410|33|26|11|0|13|28|597|1781
beef mince cooked|262|26|17|0|0|17|22|325|67
beef ribeye steak cooked|338|30.7|23.5|0|0|12|19|289|60
beef stew|115|8.5|5|9|1.5|30|15|280|310
beef tenderloin steak cooked|374|74.8|8.311|0|0|26.6|30.8|460.6|0.061
beer lager|43|0.46|0|3.55|0|5|6|27|4
beet greens|22|2.2|0.13|4.33|3.7|117|70|762|226
beetroot|43|1.61|0.17|9.56|2.8|16|23|325|78
bell pepper green|20|0.86|0.17|4.64|1.7|10|10|175|3
bell pepper red|31|0.99|0.3|6.03|2.1|7|12|211|4
bell pepper yellow|27|1|0.21|6.32|0.9|11|12|212|2
biryani chicken|168|9|6|20|1|35|24|272|480
black bean burger|200|12|8|22|6|80|52|380|450
black beans|227|15.011|1.501|38.362|9|28|70|355|1
black beans canned|91|5.45|0.35|16.55|7.5|32|28|244|420
black currants|63|1.4|0.41|15.38|0|55|24|322|2
black eyed peas|116|8|0.53|20.76|6.5|24|53|278|4
black olives|115|0.84|10.68|6.26|3.2|88|11|8|735
black pepper|251|10.39|3.26|63.95|25.3|443|171|1329|20
black pudding|305|14.3|22.2|16|0.8|42|17|248|1360
black rice|356|9|3.5|74|4|25|143|278|7
black sesame seeds|573|17.7|50|23|11.8|975|347|468|8
black tea|2|0|0|0.3|0|0|3|37|0
black turtle beans|341|21.6|1.4|62.4|8.7|160|160|1483|5
blackberries|43|1.39|0.49|9.61|5.3|29|20|162|1
blackberry jam|250|0.5|0.2|65|2|22|8|130|10
blueberries|57|0.74|0.33|14.49|2.4|6|6|77|1
blueberry muffin|377|6|15|56|2|70|22|150|280
bok choy|13|1.5|0.2|2.18|1|105|19|252|65
borscht|45|2|1|7|2|40|15|220|400
boysenberries|43|1.39|0.49|9.61|5.3|29|20|162|1
braised pork belly|518|18|50|0|0|13|12|218|56
bran flakes cereal|320|11|3|72|16|29|87|450|644
brazil nut|659|14.32|67.1|11.74|7.5|160|376|659|3
bread white|265|8.85|3.18|50.6|2.7|151|24|115|491
bread whole wheat|247|13|3.5|41|7|77|76|248|400
breadcrumbs|395|13|5|73|3.5|110|28|180|731
brie cheese|334|20.75|27.68|0.45|0|184|20|152|629
broccoli|34|2.82|0.37|6.64|2.6|47|21|316|33
broccoli rabe|22|3.17|0.49|2.85|2.7|108|22|196|33
broth beef|7|1.1|0.2|0.1|0|14|2|172|385
broth chicken|15|1.9|0.5|1.4|0|12|3|152|376
broth vegetable|7|0.3|0.2|1|0|14|2|120|430
brownies|437|5.9|19.8|63.2|3.1|23|30|202|324
brussels sprouts|43|3.38|0.3|8.95|3.8|42|23|389|25
buckwheat|343|13.25|3.4|71.5|10|18|231|460|1
buckwheat groats cooked|92|3.38|0.62|19.94|2.7|7|51|88|4
buffalo mozzarella|280|18|22|1|0|390|18|110|400
bulgur cooked|83|3.08|0.24|18.58|4.5|10|32|68|5
burger bun|263|8.5|4|49|2.3|60|25|98|491
butter|717|0.85|81.11|0.06|0|24|2|24|643
butter beans|338|21.4|1.1|60.6|10.2|118|70|930|7
butter unsalted|717|0.85|81.11|0.06|0|24|2|24|11
buttermilk|40|3.31|0.88|4.79|0|116|11|151|105
butternut squash|45|1|0.1|11.69|2|48|34|352|4
butterscotch|397|0.3|3.3|82.5|0|32|2|112|136
cabbage|25|1.28|0.1|5.8|2.5|40|12|170|18
caesar salad dressing|355|3|37|4|0|78|8|164|700
cake chocolate|371|5|19|47|2|64|28|163|352
cake vanilla|391|4.9|17.7|55.3|0.6|75|10|84|324
camembert cheese|300|19.8|24.26|0.46|0|388|20|187|842
cannellini beans|153|9.7|0.4|27.8|6.3|91|66|435|4
canola oil|884|0|100|0|0|0|0|0|0
cantaloupe melon|34|0.84|0.19|8.16|0.9|9|12|267|16
capers|23|2.36|0.86|4.89|3.2|40|33|40|2964
cardamom|311|10.76|6.7|68.47|28|383|229|1119|18
carrot|41|0.93|0.24|9.58|2.8|33|12|320|69
carrot juice|40|0.95|0.15|9.28|0.8|24|14|292|36
carrot raw|41|0.93|0.24|9.58|2.8|33|12|320|69
cashew|553|18.22|43.85|30.19|3.3|37|292|660|12
cashew milk|25|0.5|1|1|0|120|5|35|115
cauliflower|25|1.92|0.28|4.97|2|22|15|299|30
celery|16|0.69|0.17|2.97|1.6|40|11|260|80
cheddar cheese|403|24.9|33.14|1.28|0|721|28|98|621
cherry|50|1|0.3|12.18|1.6|13|11|222|3
cherry tomatoes|18|0.88|0.2|3.92|1.2|10|11|237|5
chia seeds|486|16.54|30.74|42.12|34.4|631|335|407|16
chicken breast cooked|165|31|3.6|0|0|15|29|256|74
chicken breast raw|120|22.5|2.62|0|0|11|29|256|65
chicken curry|151|12|8|8|1.5|35|28|312|520
chicken drumstick cooked|223|26.2|12.7|0|0|17|22|247|86
chicken liver|172|26.5|5.5|0.73|0|11|22|263|71
chicken nuggets|296|14.6|19|18.7|0.9|15|18|278|556
chicken rice|151|7|3|25|1|16|20|167|290
chicken soup|21|1.1|0.4|3|0.3|8|5|130|560
chicken thigh cooked|209|26.6|11.7|0|0|17|22|247|87
chicken tikka masala|160|12|8|9|1.2|50|28|380|480
chickpeas|364|19.3|6|60.65|17.4|105|115|875|24
chickpeas canned|139|7.05|2.35|22.5|6.3|42|35|207|240
chickpeas cooked|164|8.86|2.59|27.42|7.6|49|48|291|7
chilli beef|190|14|9|14|3|35|28|390|480
chilli con carne|130|10|5|12|4|40|28|380|450
chips potato|547|6.56|37.47|52.9|4.4|21|45|1100|525
chocolate dark 70|598|7.79|42.63|45.9|10.9|73|228|715|20
chocolate milk|83|3.4|3.4|11.4|0.3|138|29|226|65
chocolate mousse|218|4.9|15.6|18|0.4|90|24|178|72
chorizo|455|24.1|38.3|1.9|0|8|23|450|1740
cinnamon|247|3.99|1.24|80.59|53.1|1002|60|431|10
clementine|47|0.85|0.15|11.75|1.7|30|10|177|1
coconut cream|330|3.63|34.68|7.11|2.2|16|37|386|18
coconut milk|230|2.29|23.84|5.54|2.2|18|37|263|15
coconut oil|862|0|100|0|0|0|0|0|0
coconut water|19|0.72|0.2|3.71|1.1|24|25|250|105
cod cooked|105|22.83|0.86|0|0|25|36|480|78
cod raw|82|17.81|0.67|0|0|16|32|413|54
coffee black|2|0.28|0.06|0|0|2|3|49|2
coleslaw|105|1.3|9.3|7.4|1.2|40|10|140|213
collard greens|32|3|0.61|5.42|4|232|27|213|17
condensed milk sweetened|321|7.91|8.7|54.4|0|284|26|371|127
corn|86|3.27|1.35|18.7|2|2|37|270|15
corn flour|361|6.93|3.86|76.85|7.3|7|93|315|5
corn on the cob|86|3.27|1.35|18.7|2|2|37|270|15
corn tortilla|218|5.7|2.85|45.94|6.3|75|65|178|42
cornflakes|357|7.5|0.4|84.72|3.8|3|14|120|618
cottage cheese|98|11.12|4.51|3.38|0|83|11|104|364
couscous cooked|112|3.79|0.16|23.22|1.4|8|8|58|5
crab meat|97|19.35|1.54|0|0|62|42|329|395
cranberries|46|0.46|0.13|12.2|4.6|8|6|85|2
cranberry juice|54|0.07|0.13|13.57|0.1|8|3|77|2
cream cheese|342|5.93|33.8|4.07|0|98|9|138|321
cream of wheat cooked|56|1.9|0.26|11.49|0.6|18|6|33|79
crème fraîche|292|2.5|30|2.5|0|75|8|100|40
croissant|406|8.2|21.03|45.8|2.6|37|16|118|375
cucumber|16|0.65|0.11|3.63|0.5|16|13|147|2
cumin|375|17.81|22.27|44.24|10.5|931|366|1788|168
curly kale|49|4.28|0.93|8.75|3.6|150|47|491|38
custard|122|4.4|3.5|19.9|0.1|135|13|160|55
custard apple|75|1.7|0.6|17.71|3|30|18|382|4
dates|282|2.45|0.39|75.03|8|64|54|696|2
dark chocolate cake|362|5|17|50|2.2|50|30|183|210
edamame|122|11.91|5.2|8.91|5.2|63|64|436|6
egg fried rice|195|5|7|28|1.5|28|18|200|550
egg white|52|10.9|0.17|0.73|0|7|11|163|166
egg yolk|322|15.86|26.54|3.59|0|129|5|109|48
eggs|155|12.58|10.61|1.12|0|56|12|138|124
eggplant|25|0.98|0.18|5.88|3|9|14|229|2
endive|17|1.25|0.2|3.35|3.1|52|15|314|22
falafel|333|13.31|17.8|31.84|4.9|78|81|585|294
fava beans|341|26.12|1.53|58.29|25|103|192|1062|13
fennel|31|1.24|0.2|7.3|3.1|49|17|414|52
feta cheese|264|14.21|21.28|4.09|0|493|19|62|1116
fig|74|0.75|0.3|19.18|2.9|35|17|232|1
fish and chips|252|12|12|26|2.5|70|28|390|700
fish cake|94|8.2|3.9|7|0.6|49|17|183|520
fish fingers|225|12|10|22|1.5|80|18|280|480
flaxseed|534|18.29|42.16|28.88|27.3|255|392|813|30
french dressing|449|0.5|41|18|0.5|30|8|130|960
french fries|312|3.4|15.5|42|3.6|16|28|527|265
french onion soup|50|2.5|2|6|0.8|45|8|183|610
french toast|229|8.4|10.9|27.7|1.2|130|16|166|311
frozen yogurt|159|4.2|6.2|25.4|0|152|16|215|62
garam masala|379|12|10|50|16|813|160|1020|76
garlic|149|6.36|0.5|33.06|2.1|181|25|401|17
garlic bread|350|9|16|44|2|78|20|140|580
ginger|80|1.82|0.75|17.77|2|16|43|415|13
goji berries|349|14.26|0.39|77.06|13.1|190|90|1132|298
gouda cheese|356|24.94|27.44|2.22|0|700|29|121|819
granola|471|10.75|20.7|64.22|6.7|56|129|402|23
granola bar|479|8.48|20.6|66.82|5.2|73|110|366|299
grape juice|60|0.37|0.13|14.96|0.2|11|10|104|5
grapefruit|42|0.77|0.14|10.66|1.6|22|9|135|0
grapes|67|0.63|0.35|17.15|0.9|10|7|191|2
green beans|31|1.83|0.22|6.97|2.7|37|25|211|6
green lentils cooked|116|9.02|0.38|20.13|7.9|19|36|369|2
green peas|81|5.42|0.4|14.46|5.1|25|33|244|5
greek salad|100|3|7|8|2|110|18|260|530
greek yogurt full fat|97|9|5|3.98|0|110|11|141|36
greek yogurt low fat|59|10.19|0.39|3.6|0|110|11|141|36
guacamole|151|1.76|13.2|8.2|5.5|15|25|400|176
guava|68|2.55|0.95|14.32|5.4|18|22|417|2
gyoza|202|10|7|26|2|28|18|185|380
halloumi|321|21.3|26|1.4|0|795|8|70|1240
ham|145|18.3|7.5|0.39|0|8|18|250|1313
hamburger|295|16|19|24|1.5|80|20|280|450
hazelnuts|628|14.95|60.75|16.7|9.7|114|163|680|0
honey|304|0.3|0|82.4|0.2|6|2|52|4
honeydew melon|36|0.54|0.14|9.09|0.8|6|10|228|18
hotdog|290|11|26|2|0|11|14|178|800
hummus|166|7.9|9.6|14.3|6|49|71|228|379
ice cream chocolate|216|3.8|11|28.4|1.1|138|22|249|79
ice cream vanilla|207|3.5|11|23.6|0.7|128|14|199|80
idli|58|2.2|0.4|12|0.5|12|10|56|190
jackfruit|95|1.72|0.64|23.25|1.5|24|29|448|2
jalapeño|29|0.91|0.37|6.5|2.8|12|15|248|3
jam strawberry|250|0.4|0.1|65|1.2|20|8|130|32
jasmine rice cooked|130|2.7|0.3|28.2|0.4|5|8|68|350
jelly donut|344|5.8|14.5|49.5|1.2|55|17|108|380
jicama|38|0.72|0.09|8.82|4.9|12|12|150|4
kale|49|4.28|0.93|8.75|3.6|150|47|491|38
kefir|52|3.79|1.01|7.65|0|110|14|173|50
kelp|43|1.68|0.56|9.57|1.3|168|121|89|233
ketchup|112|1.74|0.18|28.5|0.7|25|12|325|907
kidney beans|333|23.58|0.83|60.01|15.2|143|140|1406|24
kidney beans canned|127|8.67|0.5|22.8|6.4|47|34|403|237
kidney beans cooked|127|8.67|0.5|22.8|6.4|47|34|403|2
kimchi|15|1.1|0.5|2.4|1.9|33|10|222|498
kiwi|61|1.14|0.52|14.66|3|34|17|312|3
kohlrabi|27|1.7|0.1|6.2|3.6|24|19|350|20
kombucha|20|0.2|0|4.6|0|8|4|43|10
lamb chops cooked|294|25.8|20.2|0|0|20|24|285|73
lamb curry|198|14|12|10|2|45|28|350|510
lamb leg roasted|230|26.5|13.3|0|0|14|24|318|70
lasagne|166|8.7|8|15|1.5|130|22|230|390
lemon|29|1.1|0.3|9.32|2.8|26|8|138|2
lemon juice|22|0.35|0.24|6.9|0.3|7|6|103|1
lentil soup|115|8|3|15|5|40|35|350|450
lentils|353|25.8|1.06|60.08|10.7|56|122|955|6
lentils cooked|116|9.02|0.38|20.13|7.9|19|36|369|2
lentils red cooked|100|7.6|0.36|17.5|7.9|17|22|300|2
lettuce iceberg|14|0.9|0.14|2.97|1.2|18|7|141|10
lettuce romaine|17|1.23|0.3|3.29|2.1|33|14|247|8
lime|30|0.7|0.2|10.54|2.8|33|6|102|2
liver beef|135|20.36|3.63|3.89|0|5|18|313|69
lobster cooked|98|20.5|0.59|1.29|0|96|34|352|380
low fat yogurt|56|5.25|0.75|7.67|0|183|17|240|77
mackerel cooked|239|21.86|15.46|0|0|15|73|401|83
mango|60|0.82|0.38|14.98|1.6|11|10|168|1
mango juice|60|0.41|0.19|14.86|0.5|6|7|119|14
mango sorbet|100|0.3|0.1|25.5|0.8|8|4|100|5
margarine|717|0.2|80|0.7|0|24|3|36|751
mayonnaise|680|0.96|74.85|0.57|0|9|4|34|635
meat pie|289|10.2|19|21|1.2|45|16|248|490
milk chocolate|535|7.65|29.66|59.4|3.4|189|63|372|79
milk full fat|61|3.2|3.27|4.8|0|113|10|150|43
milk skimmed|34|3.41|0.08|4.96|0|122|11|166|44
milk soy|33|2.86|1.61|2.13|0|25|19|118|51
minestrone soup|50|2.5|1.5|8|2|45|15|220|420
mint|70|3.75|0.94|14.89|8|243|80|569|31
miso|199|11.69|6.01|26.47|5.4|57|48|210|3728
miso soup|21|2.21|0.67|2.64|0.3|12|14|65|624
mixed nuts|607|18.5|52.5|21|4.4|134|176|642|120
mochi|229|3.7|0.5|53.3|0.2|3|7|23|9
molasses|290|0|0.1|74.73|0|205|242|1464|37
mozzarella cheese|300|22.17|22.35|2.19|0|505|20|76|627
mushrooms|22|3.09|0.34|3.26|1|3|9|318|5
mussels cooked|172|23.8|4.48|7.39|0|33|37|320|369
mustard|66|4.37|3.66|5.83|3.2|58|48|152|1135
navy beans|337|22.33|1.5|60.75|10.5|127|175|1185|5
nectarine|44|1.06|0.32|10.55|1.7|6|9|201|0
noodles egg cooked|138|4.54|2.15|25.16|1.8|19|21|44|8
nori seaweed|35|5.81|0.28|5.11|0.3|70|2|356|48
nut butter mixed|589|21.9|51|18.7|5.6|62|166|626|8
oat bran|246|17.3|7.03|66.22|15.4|54|235|566|4
oat milk|46|1|1.5|6.6|0.8|120|6|60|49
oats|389|16.89|6.9|66.27|10.6|54|177|429|2
oats cooked|68|2.4|1.4|11.9|1.7|10|26|61|49
olive oil|884|0|100|0|0|1|0|1|2
olives green|145|1.03|15.32|3.84|3.3|88|11|42|1556
onion|40|1.1|0.1|9.34|1.7|23|10|166|4
orange|47|0.94|0.12|11.75|2.4|40|10|181|0
orange juice|45|0.7|0.2|10.4|0.2|11|11|200|1
oyster|69|7.07|2.5|5.65|0|59|47|168|106
pad thai|168|8|6|22|2|60|28|240|620
paella|186|12|7|20|1.5|48|32|320|560
palm oil|884|0|100|0|0|0|0|0|0
pancakes|227|6.4|10.3|28.6|1|139|18|148|459
papaya|43|0.47|0.26|10.82|1.7|20|21|182|8
parmesan cheese|431|38.46|28.61|3.22|0|1184|44|92|1529
parsley|36|2.97|0.79|6.33|3.3|138|50|554|56
passion fruit|97|2.2|0.7|23.38|10.4|12|29|348|28
pasta cooked|131|5.06|1.06|25.22|1.8|7|18|44|1
pasta tomato sauce|130|5|3|21|2|30|18|280|380
pastry puff|558|9|39|43|2|28|17|108|487
peach|39|0.91|0.25|9.54|1.5|6|9|190|0
peach jam|250|0.4|0.1|64|0.8|15|8|130|10
peanut butter|588|25.09|49.94|19.56|6|43|168|649|17
peanuts|567|23.966|45.702|14.955|8.5|92|168|705|18
pear|57|0.36|0.14|15.23|3.1|9|7|119|1
peas|81|5.42|0.4|14.46|5.1|25|33|244|5
pecan|691|9.17|71.97|13.86|9.6|70|121|410|0
pesto|394|6.3|39.6|5.5|2|168|81|360|700
pickle cucumber|11|0.33|0.2|2.26|1.2|16|7|116|785
pie apple|237|2.054|11.147|34.069|1.5|12|9|89|253
pineapple|50|0.54|0.12|13.12|1.4|13|12|109|1
pistachio|560|20.16|45.32|27.17|10.3|105|121|1025|1
pita bread|275|9.1|1.2|55.7|2.2|58|26|120|536
pizza|266|11.39|9.69|33.33|2.3|188|24|172|598
plum|46|0.7|0.28|11.42|1.4|6|7|157|0
polenta cooked|70|1.7|0.4|15.6|0.8|2|9|30|234
pomegranate|83|1.67|1.17|18.7|4|10|12|236|3
popcorn|387|12.94|4.54|77.78|14.5|7|144|329|10
pork chops cooked|231|27.8|12.9|0|0|18|25|411|72
pork ribs cooked|321|26.2|23.3|0|0|13|22|310|74
potato|77|2|0.09|17.49|2.2|12|23|425|6
potato chips|547|6.56|37.47|52.9|4.4|21|45|1100|525
potato salad|143|2.08|9.86|13.35|1.5|22|16|204|489
potato soup|81|2.7|3.4|11.2|1|50|17|280|440
prawns cooked|99|21.35|1.08|0.93|0|85|39|185|224
pretzels|380|9.87|4.04|80.3|2.7|25|26|153|1614
protein bar|378|33.3|11.2|35.9|4.2|300|100|280|300
protein powder whey|400|80|7|12|0.5|130|120|600|200
prunes|240|2.18|0.38|63.88|7.1|43|41|732|2
pumpkin|26|1|0.1|6.5|0.5|21|12|340|1
pumpkin seeds|559|30.23|49.05|10.71|6|46|592|809|7
quinoa cooked|120|4.4|1.92|21.3|2.8|17|64|172|7
radish|16|0.68|0.1|3.4|1.6|25|10|233|39
raisins|299|3.07|0.46|79.18|3.7|50|32|749|11
rapeseed oil|884|0|100|0|0|0|0|0|0
raspberries|52|1.2|0.65|11.94|6.5|25|22|151|1
red lentils cooked|100|7.6|0.36|17.5|7.9|17|22|300|2
red onion|40|1.1|0.1|9.34|1.7|23|10|166|4
red wine|85|0.07|0|2.61|0|8|10|127|4
refried beans|102|5.5|2.5|15.8|5|59|35|300|374
rice basmati cooked|130|2.7|0.3|28.2|0.4|5|8|68|325
rice brown cooked|123|2.58|0.97|25.58|1.8|10|44|154|5
rice cakes|387|8.19|2.83|81.54|3.5|7|52|115|30
rice noodles cooked|109|1.8|0.2|25.9|0.2|7|9|30|33
rice pudding|131|3.5|4.1|21.4|0.3|127|11|152|54
rice white cooked|130|2.69|0.28|28.17|0.4|10|12|35|1
ricotta cheese|174|11.26|12.98|3.04|0|207|11|105|84
roast beef|185|29.9|7.1|0|0|5|24|378|56
rolled oats|389|16.89|6.9|66.27|10.6|54|177|429|2
rum|231|0|0|0|0|0|0|2|0
rye bread|259|8.46|3.29|48.3|5.8|73|40|166|603
rye crackers|370|9.44|4.11|78.62|11.7|32|74|246|500
rye flour|335|13.25|2.73|69.77|14.6|24|110|517|2
salmon cooked|208|19.84|13.42|0|0|13|30|490|59
salmon raw|142|19.84|6.34|0|0|12|27|363|44
salsa|36|1.4|0.2|7.6|1.8|28|14|248|480
salt|0|0|0|0|0|24|1|8|38758
sardines canned|208|24.62|11.45|0|0|382|39|397|505
sardines in oil|185|21.5|10.45|0|0|382|39|397|505
sauerkraut|19|0.91|0.14|4.28|2.9|30|13|170|661
sausage pork cooked|339|15.35|29.82|3.45|0|16|17|262|862
scrambled egg|149|9.99|10.98|1.53|0|77|12|124|298
seitan|370|75|1.9|14|0.6|142|34|320|340
sesame seeds|573|17.7|50|23|11.8|975|347|468|8
shrimp cooked|99|21.35|1.08|0.93|0|85|39|185|224
shrimp raw|85|20.1|0.51|0.93|0|52|34|185|119
skim milk|34|3.41|0.08|4.96|0|122|11|166|44
smoothie green|65|2|0.5|14|3|80|28|360|60
soba noodles cooked|99|5|0.1|21.4|0|9|9|35|60
soy milk|33|2.86|1.61|2.13|0|25|19|118|51
soy sauce|60|5.57|0.06|5.57|0.8|17|40|435|5493
spaghetti bolognese|180|10|7|20|2|45|25|300|380
spaghetti cooked|157|5.76|0.93|30.6|1.8|7|25|44|1
spinach|23|2.86|0.39|3.63|2.2|99|79|558|79
spinach cooked|41|5.35|0.52|6.75|4.3|136|87|466|70
spring onion|32|1.83|0.19|7.34|2.6|72|20|276|16
spring roll|153|4.5|6.5|20|1.5|38|18|193|380
squid cooked|175|17.93|7.27|7.46|0|32|33|280|265
steak sirloin cooked|267|30.64|15.36|0|0|17|24|370|57
strawberries|32|0.67|0.3|7.68|2|16|13|153|1
strawberry yogurt|95|3.5|1.4|18|0.3|120|14|187|52
sugar|387|0|0|100|0|1|0|2|1
sugar snap peas|42|2.8|0.2|7.55|2.6|27|24|200|3
sunflower oil|884|0|100|0|0|0|0|0|0
sunflower seeds|584|20.78|51.46|20|8.6|78|325|645|9
sweet corn|86|3.27|1.35|18.7|2|2|37|270|15
sweet potato|86|1.57|0.05|20.12|3|30|25|337|55
sweet potato cooked|90|2.01|0.15|20.71|3.3|27|22|337|36
swiss cheese|380|26.9|27.8|5.4|0|791|36|224|187
swordfish cooked|172|28.4|5.66|0|0|6|38|558|115
tahini|595|17|53.76|21.19|9.3|426|95|414|115
tamarind|239|2.8|0.6|62.5|5.1|74|92|628|28
tempeh|193|18.54|10.8|9.39|0|111|81|412|9
tilapia cooked|128|26.15|2.65|0|0|14|32|380|56
tilapia raw|96|20.08|1.7|0|0|10|27|302|52
tofu firm|144|17.3|8.72|2.78|2.3|683|58|121|14
tofu silken|55|4.8|2.7|1.4|0|25|21|97|8
tomato|18|0.88|0.2|3.89|1.2|10|11|237|5
tomato juice|17|0.85|0.05|3.53|0.4|10|11|217|314
tomato paste|82|4.3|0.46|18.91|4.1|36|28|1014|59
tomato sauce|29|1.43|0.27|6.72|1.7|18|14|400|24
tortilla chips|489|7.2|23.9|63.2|5|41|55|352|461
tortilla flour|310|7.88|8.12|51.68|3.6|130|23|114|609
trout cooked|190|26.63|8.47|0|0|86|29|481|57
tuna canned in water|109|25.51|2.53|0|0|17|36|264|396
tuna raw|132|28.48|4.9|0|0|30|50|252|39
tuna steak cooked|184|29.9|6.3|0|0|12|35|536|58
turkey breast cooked|135|30.1|1.22|0|0|14|31|298|55
turkey breast raw|104|21.92|1.22|0.72|0|10|29|245|57
turkey mince cooked|218|28.6|11.1|0|0|23|26|340|87
turnip|28|0.9|0.1|6.43|1.8|30|11|191|67
tzatziki|88|4.3|6.6|3.7|0.3|116|14|148|200
udon noodles cooked|132|3.5|0.6|27.7|0.4|8|11|35|500
vanilla ice cream|207|3.5|11|23.6|0.7|128|14|199|80
veal cutlet cooked|194|29.4|7.7|0|0|24|28|360|76
vegetable curry|97|3|4|14|3|80|28|350|450
vegetable soup|23|1.5|0.5|3.6|1.5|30|12|200|386
venison cooked|187|30.2|6|0|0|7|26|335|54
vinegar apple cider|21|0|0|0.93|0|7|5|73|5
walnuts|654|15.23|65.21|13.71|6.7|98|158|441|2
water|0|0|0|0|0|23.7|4.7|0|0
water chestnuts|97|1.41|0.1|23.94|3|11|22|584|14
watercress|11|2.3|0.13|1.29|0.5|120|21|330|41
watermelon|30|0.61|0.15|7.55|0.4|7|10|112|1
wheat bread whole|247|13|3.5|41|7|77|76|248|400
wheat germ|360|23.15|9.72|51.8|13.2|45|239|892|16
whey protein|400|80|7|12|0.5|130|120|600|200
white bean soup|110|7|2|18|5|75|42|380|450
white beans|337|23.36|0.85|60.27|10.4|240|190|1795|16
white chocolate|539|5.87|32.09|59.24|0|199|12|286|90
white fish cooked|105|22.83|0.86|0|0|25|36|480|78
white rice cooked|130|2.69|0.28|28.17|0.4|10|12|35|1
white wine|82|0.1|0|2.6|0|9|10|71|5
whole milk|61|3.2|3.27|4.8|0|113|10|150|43
wild rice cooked|101|3.99|0.34|21.34|1.8|3|32|101|3
worcestershire sauce|78|2.5|0.05|19.5|0|90|31|918|980
yellow squash|16|1.21|0.18|3.38|1.1|15|17|262|2
yogurt full fat|61|3.47|3.25|4.66|0|121|12|155|46
yogurt greek|97|9|5|3.98|0|110|11|141|36
yogurt low fat|56|5.25|0.75|7.67|0|183|17|240|77
zucchini|17|1.21|0.32|3.11|1|16|18|261|8
''';

List<FoodItem>? _parsedFoods;

List<FoodItem> _getAllFoods() {
  if (_parsedFoods != null) return _parsedFoods!;
  _parsedFoods = _foodDb.trim().split('\n').map((line) {
    final p = line.split('|');
    double parse(int i) {
      if (i >= p.length) return 0;
      return double.tryParse(p[i]) ?? 0;
    }
    return FoodItem(
      p.isNotEmpty ? p[0] : '',
      parse(1), parse(2), parse(3), parse(4), parse(5),
      parse(6), parse(7), parse(8), parse(9),
    );
  }).toList();
  return _parsedFoods!;
}

List<FoodItem> _searchFoods(String query) {
  final all = _getAllFoods();
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all.take(50).toList();
  return all.where((f) => f.name.contains(q)).take(60).toList();
}

// ============================================================================
// CALCULATION ENGINE  — Mifflin-St Jeor BMR
// ============================================================================

const Map<ActivityLevel, double> _activityMul = {
  ActivityLevel.sedentary:         1.2,
  ActivityLevel.lightlyActive:     1.375,
  ActivityLevel.moderatelyActive:  1.55,
  ActivityLevel.veryActive:        1.725,
};

int _calcAge(String birthday) {
  try {
    final b = DateTime.parse(birthday);
    final n = DateTime.now();
    int age = n.year - b.year;
    if (n.month < b.month || (n.month == b.month && n.day < b.day)) age--;
    return math.max(0, age);
  } catch (_) {
    return 0;
  }
}

Calculations _computeCalcs(UserProfile profile, Map<MealName, List<MealEntry>> meals) {
  final age = _calcAge(profile.birthday);
  final h = profile.heightCm, w = profile.weightKg;

  // Mifflin-St Jeor BMR (height in cm)
  final bmr = profile.gender == Gender.male
      ? 88.36 + 13.4 * w + 4.8 * h - 5.7 * age
      : 447.6 + 9.2 * w + 3.1 * h - 4.3 * age;

  final tdee = (bmr * _activityMul[profile.activityLevel]!).round();

  // BMI → goal
  final bmi = w / math.pow(h / 100, 2);
  final goal = bmi < 18.5 ? Goal.gain : (bmi >= 24.9 ? Goal.lose : Goal.maintain);

  final adjustedTdee = tdee + (goal == Goal.lose ? -500 : (goal == Goal.gain ? 500 : 0));

  // Meal limits — Breakfast 25%, Lunch 35%, Dinner 20%, Snacks 20%
  final mealLimits = <MealName, int>{
    MealName.breakfast: (adjustedTdee * 0.25).round(),
    MealName.lunch:     (adjustedTdee * 0.35).round(),
    MealName.dinner:    (adjustedTdee * 0.20).round(),
    MealName.snacks:    (adjustedTdee * 0.20).round(),
  };

  // Macros: 45/20/35  ÷ 4/4/9
  final targetCarbs   = ((adjustedTdee * 0.45) / 4).round();
  final targetProtein = ((adjustedTdee * 0.20) / 4).round();
  final targetFat     = ((adjustedTdee * 0.35) / 9).round();

  int totalCal = 0;
  double totalCarbs = 0, totalProtein = 0, totalFat = 0;
  final perMeal = <MealName, int>{
    for (final m in MealName.values) m: 0,
  };

  for (final m in MealName.values) {
    for (final e in meals[m] ?? const <MealEntry>[]) {
      final r = e.grams / 100;
      final cal = (e.food.cal * r).round();
      perMeal[m] = (perMeal[m] ?? 0) + cal;
      totalCal += cal;
      totalCarbs   += e.food.carb * r;
      totalProtein += e.food.pro  * r;
      totalFat     += e.food.fat  * r;
    }
  }

  return Calculations(
    bmi: bmi, goal: goal, tdee: tdee, adjustedTdee: adjustedTdee,
    mealLimits: mealLimits,
    targetCarbs: targetCarbs, targetProtein: targetProtein, targetFat: targetFat,
    totalCal: totalCal,
    totalCarbs: totalCarbs.round(),
    totalProtein: totalProtein.round(),
    totalFat: totalFat.round(),
    perMeal: perMeal,
  );
}

// ============================================================================
// STORAGE
// ============================================================================

const String _kProfile = 'snt_profile';
const String _kLog     = 'snt_log';

String _todayStr() {
  final d = DateTime.now();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

DailyLog _emptyLog() => DailyLog(
      date: _todayStr(),
      meals: {for (final m in MealName.values) m: <MealEntry>[]},
    );

Future<UserProfile?> _loadProfile() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProfile);
    if (raw == null) return null;
    return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<void> _persistProfile(UserProfile p) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kProfile, jsonEncode(p.toJson()));
}

Future<DailyLog> _loadLog() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLog);
    if (raw != null) {
      final parsed = DailyLog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (parsed.date == _todayStr()) return parsed;
    }
  } catch (_) {}
  return _emptyLog();
}

Future<void> _persistLog(DailyLog l) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLog, jsonEncode(l.toJson()));
}

String _uid() =>
    '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32).toRadixString(36)}';

// ============================================================================
// ROOT SCREEN
// ============================================================================

class NutritionTrackerScreen extends StatefulWidget {
  const NutritionTrackerScreen({super.key});

  @override
  State<NutritionTrackerScreen> createState() => _NutritionTrackerScreenState();
}

class _NutritionTrackerScreenState extends State<NutritionTrackerScreen> {
  UserProfile? _profile;
  DailyLog _log = _emptyLog();
  Calculations? _calcs;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([_loadProfile(), _loadLog()]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as UserProfile?;
      _log = results[1] as DailyLog;
      _recalc();
      _loading = false;
    });
  }

  void _recalc() {
    _calcs = _profile == null ? null : _computeCalcs(_profile!, _log.meals);
  }

  Future<void> _setProfile(UserProfile p) async {
    await _persistProfile(p);
    final fresh = _emptyLog();
    await _persistLog(fresh);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _log = fresh;
      _recalc();
    });
  }

  void _addFood(MealName meal, FoodItem food, double grams) {
    final newMeals = <MealName, List<MealEntry>>{
      for (final m in MealName.values) m: List<MealEntry>.from(_log.meals[m] ?? const []),
    };
    newMeals[meal]!.add(MealEntry(id: _uid(), food: food, grams: grams));
    final updated = DailyLog(date: _log.date, meals: newMeals);
    setState(() {
      _log = updated;
      _recalc();
    });
    _persistLog(updated);
  }

  void _removeFood(MealName meal, String id) {
    final newMeals = <MealName, List<MealEntry>>{
      for (final m in MealName.values) m: List<MealEntry>.from(_log.meals[m] ?? const []),
    };
    newMeals[meal] = newMeals[meal]!.where((e) => e.id != id).toList();
    final updated = DailyLog(date: _log.date, meals: newMeals);
    setState(() {
      _log = updated;
      _recalc();
    });
    _persistLog(updated);
  }

  Future<void> _handleReset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfile);
    await prefs.remove(_kLog);
    if (!mounted) return;
    setState(() {
      _profile = null;
      _log = _emptyLog();
      _calcs = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _C.bg,
        body: Center(child: CircularProgressIndicator(color: _C.green)),
      );
    }
    if (_profile == null) {
      return _Onboarding(onDone: _setProfile);
    }
    final calcs = _calcs!;
    final profile = _profile!;
    Widget body;
    switch (_tab) {
      case 1: body = _InsightsTab(calcs: calcs); break;
      case 2: body = _PlanTab(calcs: calcs); break;
      case 3: body = _AccountTab(profile: profile, calcs: calcs, onReset: _handleReset); break;
      default:
        body = _HomeTab(
          profile: profile, calcs: calcs, log: _log,
          onAdd: _addFood, onRemove: _removeFood,
        );
    }
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Expanded(child: body),
          _TabBar(active: _tab, onChange: (i) => setState(() => _tab = i)),
        ]),
      ),
    );
  }
}

// ============================================================================
// SHARED UI
// ============================================================================

class _Divider extends StatelessWidget {
  final double mv;
  const _Divider({this.mv = 0});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: _C.border, margin: EdgeInsets.symmetric(vertical: mv));
}

class _MacroBar extends StatelessWidget {
  final String label;
  final int val;
  final int target;
  final Color color;
  const _MacroBar({required this.label, required this.val, required this.target, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = target > 0 ? math.min(val / target, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _C.txtSub)),
                Text('$val / $target g', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _C.txtSub)),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct, minHeight: 6,
              backgroundColor: _C.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ONBOARDING
// ============================================================================

class _ActOption {
  final ActivityLevel key;
  final String label;
  final String sub;
  const _ActOption(this.key, this.label, this.sub);
}

const List<_ActOption> _actOpts = [
  _ActOption(ActivityLevel.sedentary,        'Sedentary',         'Little or no exercise'),
  _ActOption(ActivityLevel.lightlyActive,    'Lightly Active',    'Exercise 1–3 days/week'),
  _ActOption(ActivityLevel.moderatelyActive, 'Moderately Active', 'Exercise 3–5 days/week'),
  _ActOption(ActivityLevel.veryActive,       'Very Active',       'Exercise 6–7 days/week'),
];

class _Onboarding extends StatefulWidget {
  final ValueChanged<UserProfile> onDone;
  const _Onboarding({required this.onDone});

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  int _step = 0;
  final _name = TextEditingController();
  Gender _gender = Gender.female;
  final _bday = TextEditingController(text: '1990-01-01');
  final _ht = TextEditingController(text: '165');
  final _wt = TextEditingController(text: '65');
  final _tw = TextEditingController(text: '60');
  ActivityLevel _act = ActivityLevel.moderatelyActive;

  static const int _stepsTotal = 7;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _step == 0) setState(() => _step = 1);
    });
  }

  @override
  void dispose() {
    _name.dispose(); _bday.dispose(); _ht.dispose(); _wt.dispose(); _tw.dispose();
    super.dispose();
  }

  void _alert(String msg) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      content: Text(msg),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  void _next() {
    if (_step == _stepsTotal) {
      final h = double.tryParse(_ht.text);
      final w = double.tryParse(_wt.text);
      final t = double.tryParse(_tw.text);
      if (_name.text.trim().isEmpty) { _alert('Enter your name'); return; }
      if (h == null || h < 50)       { _alert('Enter a valid height (cm)'); return; }
      if (w == null || w < 20)       { _alert('Enter a valid weight (kg)'); return; }
      widget.onDone(UserProfile(
        name: _name.text.trim(),
        gender: _gender,
        birthday: _bday.text,
        heightCm: h,
        weightKg: w,
        targetWeightKg: t ?? w,
        activityLevel: _act,
      ));
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 0) {
      return const Scaffold(
        backgroundColor: _C.lime,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite, size: 56, color: Colors.black),
                SizedBox(height: 20),
                Text('NUTRATRACK',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8, color: Colors.black)),
                SizedBox(height: 60),
                CircularProgressIndicator(color: Colors.black),
              ],
            ),
          ),
        ),
      );
    }

    final progress = _step / _stepsTotal;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress, minHeight: 6,
                            backgroundColor: _C.border,
                            valueColor: const AlwaysStoppedAnimation(_C.lime),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${_step - 1}/${_stepsTotal - 1}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _C.txtSub)),
                    ],
                  ),
                ),
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.55,
                child: _stepBody(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _next,
                  style: TextButton.styleFrom(
                    backgroundColor: _C.lime,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(_step == _stepsTotal ? 'See My Plan' : 'Continue',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 1:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88, height: 88,
              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.favorite, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text("Let's Get Started!",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _C.txt)),
            const SizedBox(height: 8),
            const Text("Let's dive in into NutraTrack",
                style: TextStyle(fontSize: 14, color: _C.txtSub)),
          ],
        );
      case 2:
        return _qBlock("What's Your Name?", _bigInput(_name, hint: 'e.g. Jane', autofocus: true));
      case 3:
        return _qBlock("What's Your Gender?", Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(child: _genderTile(Gender.female, '♀', 'Female')),
              const SizedBox(width: 12),
              Expanded(child: _genderTile(Gender.male,   '♂', 'Male')),
            ],
          ),
        ));
      case 4:
        return _qBlock('Your Birthday?', Column(children: [
          _bigInput(_bday, hint: 'YYYY-MM-DD',
              keyboard: TextInputType.datetime, allowChars: '0-9-'),
          const SizedBox(height: 6),
          const Text('Format: YYYY-MM-DD',
              textAlign: TextAlign.center,
              style: TextStyle(color: _C.txtMuted, fontSize: 12)),
        ]));
      case 5:
        return _qBlock('Your Height?', Row(children: [
          Expanded(child: _bigInput(_ht, hint: '165', keyboard: const TextInputType.numberWithOptions(decimal: true))),
          const SizedBox(width: 12),
          const Text('cm', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.txtSub)),
        ]));
      case 6:
        return _qBlock('Current & Target Weight?', Column(children: [
          Row(children: [
            Expanded(child: _bigInput(_wt, hint: '65', keyboard: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 12),
            const Text('kg now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.txtSub)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _bigInput(_tw, hint: '60', keyboard: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 12),
            const Text('kg target', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.txtSub)),
          ]),
        ]));
      case 7:
        return _qBlock('Activity Level?', Column(
          children: _actOpts.map((o) {
            final active = _act == o.key;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _act = o.key),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: active ? _C.lime : _C.border, width: 1.5),
                  color: active ? _C.limeLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: active ? _C.txt : _C.txtMuted)),
                  const SizedBox(height: 2),
                  Text(o.sub, style: const TextStyle(fontSize: 12, color: _C.txtMuted)),
                ]),
              ),
            );
          }).toList(),
        ));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _qBlock(String question, Widget child) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(question,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _C.txt)),
      ),
      child,
    ]);
  }

  Widget _bigInput(TextEditingController c, {String? hint, TextInputType? keyboard, bool autofocus = false, String? allowChars}) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      keyboardType: keyboard ?? TextInputType.text,
      inputFormatters: allowChars != null
          ? [FilteringTextInputFormatter.allow(RegExp('[$allowChars]'))]
          : (keyboard == const TextInputType.numberWithOptions(decimal: true)
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _C.txt),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _C.txtMuted),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.lime, width: 1.5),
        ),
      ),
    );
  }

  Widget _genderTile(Gender g, String symbol, String label) {
    final active = _gender == g;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _gender = g),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          border: Border.all(color: active ? _C.lime : _C.border, width: 1.5),
          color: active ? _C.limeLight : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Text(symbol, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: active ? _C.txt : _C.txtMuted)),
        ]),
      ),
    );
  }
}

// ============================================================================
// CALORIE RING (CustomPainter)
// ============================================================================

class _CalRing extends StatelessWidget {
  final int eaten;
  final int target;
  const _CalRing({required this.eaten, required this.target});

  @override
  Widget build(BuildContext context) {
    final pct = target > 0 ? math.min(eaten / target, 1.0) : 0.0;
    return SizedBox(
      width: 148, height: 148,
      child: CustomPaint(
        painter: _RingPainter(pct),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${math.max(target - eaten, 0)}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _C.txt)),
              const Text('KCAL LEFT',
                  style: TextStyle(fontSize: 10, color: _C.txtMuted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  const _RingPainter(this.pct);
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final bg = Paint()
      ..color = _C.border
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);
    if (pct > 0) {
      final fg = Paint()
        ..color = _C.lime
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * pct,
        false,
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

// ============================================================================
// FOOD SEARCH MODAL
// ============================================================================

class _FoodDetail extends StatefulWidget {
  final FoodItem food;
  final MealName meal;
  final void Function(double grams) onAdd;
  final VoidCallback onBack;
  const _FoodDetail({required this.food, required this.meal, required this.onAdd, required this.onBack});

  @override
  State<_FoodDetail> createState() => _FoodDetailState();
}

class _FoodDetailState extends State<_FoodDetail> {
  double _grams = 100;

  @override
  Widget build(BuildContext context) {
    final r = _grams / 100;
    final f = widget.food;
    final rows = <List<String>>[
      ['Calories',  '${(f.cal * r).round()} kcal'],
      ['Protein',   '${(f.pro * r).toStringAsFixed(1)} g'],
      ['Fat',       '${(f.fat * r).toStringAsFixed(1)} g'],
      ['Carbs',     '${(f.carb * r).toStringAsFixed(1)} g'],
      ['Fiber',     '${(f.fib * r).toStringAsFixed(1)} g'],
      ['Calcium',   '${(f.ca * r).round()} mg'],
      ['Magnesium', '${(f.mg * r).round()} mg'],
      ['Potassium', '${(f.k * r).round()} mg'],
      ['Sodium',    '${(f.na * r).round()} mg'],
    ];
    return Stack(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 180),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: widget.onBack,
              child: const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('← Back',
                    style: TextStyle(fontSize: 15, color: _C.green, fontWeight: FontWeight.w700)),
              ),
            ),
            Text(_capitalize(f.name),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _C.txt)),
            const SizedBox(height: 4),
            Text('Per ${_grams.toStringAsFixed(0)} g',
                style: const TextStyle(fontSize: 13, color: _C.txtMuted)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _C.surface, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.border),
              ),
              child: Column(children: [
                for (int i = 0; i < rows.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(rows[i][0],
                            style: const TextStyle(fontSize: 13, color: _C.txtSub, fontWeight: FontWeight.w600)),
                        Text(rows[i][1],
                            style: const TextStyle(fontSize: 13, color: _C.txt, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (i < rows.length - 1) const _Divider(),
                ],
              ]),
            ),
          ]),
        ),
      ),
      Positioned(
        left: 0, right: 0, bottom: 0,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: _C.surface,
            border: Border(top: BorderSide(color: _C.border)),
          ),
          child: SafeArea(
            top: false,
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Weight (grams)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.txtSub)),
                  Row(children: [
                    _stepBtn('−', () => setState(() => _grams = math.max(5, _grams - 10))),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 60,
                      child: Text('${_grams.toStringAsFixed(0)} g',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.txt)),
                    ),
                    const SizedBox(width: 16),
                    _stepBtn('+', () => setState(() => _grams += 10)),
                  ]),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => widget.onAdd(_grams),
                  style: TextButton.styleFrom(
                    backgroundColor: _C.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('+ Add to ${widget.meal.label}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _stepBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44, height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _C.green, width: 1.5),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 22, color: _C.green, fontWeight: FontWeight.w700, height: 1)),
      ),
    );
  }
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

class _SearchModal extends StatefulWidget {
  final MealName meal;
  final void Function(FoodItem food, double grams) onAdd;
  const _SearchModal({required this.meal, required this.onAdd});

  @override
  State<_SearchModal> createState() => _SearchModalState();
}

class _SearchModalState extends State<_SearchModal> {
  final _query = TextEditingController();
  FoodItem? _sel;
  List<FoodItem> _results = const [];

  @override
  void initState() {
    super.initState();
    _results = _searchFoods('');
    _query.addListener(() {
      setState(() => _results = _searchFoods(_query.text));
    });
  }

  @override
  void dispose() { _query.dispose(); super.dispose(); }

  void _close() { Navigator.pop(context); }

  @override
  Widget build(BuildContext context) {
    final sel = _sel;
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: sel != null
            ? _FoodDetail(
                food: sel, meal: widget.meal,
                onAdd: (g) { widget.onAdd(sel, g); _close(); },
                onBack: () => setState(() => _sel = null),
              )
            : Column(children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: _C.surface,
                    border: Border(bottom: BorderSide(color: _C.border)),
                  ),
                  child: Row(children: [
                    GestureDetector(
                      onTap: _close,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Text('✕', style: TextStyle(fontSize: 20, color: _C.txtSub)),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text('Add to ${widget.meal.label}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.txt)),
                      ),
                    ),
                    const SizedBox(width: 32),
                  ]),
                ),
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _C.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.border),
                  ),
                  child: Row(children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.search, color: _C.txtMuted, size: 20),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search foods…',
                          hintStyle: TextStyle(color: _C.txtMuted),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        style: const TextStyle(fontSize: 14, color: _C.txt),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: _results.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Text('No foods found', style: TextStyle(color: _C.txtMuted)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final item = _results[i];
                            return GestureDetector(
                              onTap: () => setState(() => _sel = item),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _C.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _C.border),
                                ),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_capitalize(item.name),
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.txt)),
                                        const SizedBox(height: 2),
                                        Text('${item.cal.round()} kcal · 100 g',
                                            style: const TextStyle(fontSize: 11, color: _C.txtMuted)),
                                      ],
                                    ),
                                  ),
                                  const Text('›', style: TextStyle(color: _C.txtMuted, fontSize: 18)),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
              ]),
      ),
    );
  }
}

// ============================================================================
// HOME TAB
// ============================================================================

const _mealIcons = <MealName, IconData>{
  MealName.breakfast: Icons.wb_sunny,
  MealName.lunch:     Icons.light_mode,
  MealName.dinner:    Icons.nightlight_round,
  MealName.snacks:    Icons.cookie,
};

class _HomeTab extends StatelessWidget {
  final UserProfile profile;
  final Calculations calcs;
  final DailyLog log;
  final void Function(MealName, FoodItem, double) onAdd;
  final void Function(MealName, String) onRemove;
  const _HomeTab({
    required this.profile, required this.calcs, required this.log,
    required this.onAdd, required this.onRemove,
  });

  Future<void> _openSearch(BuildContext context, MealName meal) async {
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _SearchModal(
        meal: meal,
        onAdd: (food, g) => onAdd(meal, food, g),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 90),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: _C.surface,
            border: Border(bottom: BorderSide(color: _C.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40, height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: _C.limeLight, shape: BoxShape.circle),
                child: Text(profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.green)),
              ),
              const Text('SmartNutrition',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _C.txt)),
              const SizedBox(width: 40),
            ],
          ),
        ),
        // Calorie card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _C.border),
          ),
          child: Column(children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _calStat('Eaten', calcs.totalCal),
                _CalRing(eaten: calcs.totalCal, target: calcs.adjustedTdee),
                _calStat('Target', calcs.adjustedTdee),
              ],
            ),
            const SizedBox(height: 16),
            _MacroBar(label: 'Carbs',   val: calcs.totalCarbs,   target: calcs.targetCarbs,   color: _C.red),
            _MacroBar(label: 'Protein', val: calcs.totalProtein, target: calcs.targetProtein, color: _C.orange),
            _MacroBar(label: 'Fat',     val: calcs.totalFat,     target: calcs.targetFat,     color: _C.blue),
          ]),
        ),
        // Meals
        ...MealName.values.map((mn) {
          final entries = log.meals[mn] ?? const <MealEntry>[];
          final eaten = calcs.perMeal[mn] ?? 0;
          final limit = calcs.mealLimits[mn] ?? 1;
          final pct = math.min(eaten / (limit == 0 ? 1 : limit), 1.0);
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _C.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Icon(_mealIcons[mn], size: 18, color: _C.green),
                      const SizedBox(width: 8),
                      Text(mn.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.txt)),
                    ]),
                    Row(children: [
                      Text('$eaten / $limit kcal',
                          style: const TextStyle(fontSize: 11, color: _C.txtSub, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => _openSearch(context, mn),
                        style: TextButton.styleFrom(
                          backgroundColor: _C.lime,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 0),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('+ Add',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: pct, minHeight: 4,
                  backgroundColor: _C.border,
                  valueColor: const AlwaysStoppedAnimation(_C.lime),
                ),
              ),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('Nothing logged yet',
                      style: TextStyle(fontSize: 12, color: _C.txtMuted))),
                )
              else
                ...entries.map((e) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _C.border))),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_capitalize(e.food.name),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _C.txt)),
                            const SizedBox(height: 2),
                            Text('${e.grams.toStringAsFixed(0)} g · ${(e.food.cal * e.grams / 100).round()} kcal',
                                style: const TextStyle(fontSize: 11, color: _C.txtMuted)),
                          ]),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onRemove(mn, e.id),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('✕', style: TextStyle(color: _C.txtMuted, fontSize: 18)),
                          ),
                        ),
                      ]),
                    )),
            ]),
          );
        }).toList(),
      ]),
    );
  }

  Widget _calStat(String label, int val) {
    return Expanded(
      child: Column(children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _C.txtMuted, letterSpacing: 0.5)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('$val',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _C.txt)),
        ),
        const Text('kcal', style: TextStyle(fontSize: 10, color: _C.txtMuted)),
      ]),
    );
  }
}

// ============================================================================
// INSIGHTS TAB
// ============================================================================

class _InsightsTab extends StatelessWidget {
  final Calculations calcs;
  const _InsightsTab({required this.calcs});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final remaining = math.max(calcs.adjustedTdee - calcs.totalCal, 0);
    final items = <_Insight>[
      _Insight('Calories', calcs.totalCal,     calcs.adjustedTdee,  'kcal', _C.lime,   '$remaining kcal remaining today.'),
      _Insight('Carbs',    calcs.totalCarbs,   calcs.targetCarbs,   'g',    _C.red,    'Aim for complex carbohydrates like oats, brown rice and legumes.'),
      _Insight('Protein',  calcs.totalProtein, calcs.targetProtein, 'g',    _C.orange, 'Protein supports muscle repair and keeps you feeling full.'),
      _Insight('Fat',      calcs.totalFat,     calcs.targetFat,     'g',    _C.blue,   'Healthy fats from nuts, avocado and olive oil support brain health.'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(dateStr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _C.txt)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.border),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Today's Overview",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _C.txt)),
            SizedBox(height: 6),
            Text('Compare your planned intake with what you have consumed across calories, protein, carbs, and fat.',
                style: TextStyle(fontSize: 13, color: _C.green, height: 1.45, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 12),
        ...items.map((ins) {
          final pct = ins.target > 0 ? ((ins.val / ins.target) * 100).round() : 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _C.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(ins.label,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _C.txt)),
                  Text('$pct%',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: ins.color)),
                ]),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: math.min(pct / 100, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: _C.border,
                  valueColor: AlwaysStoppedAnimation(ins.color),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Actual: ${ins.val} ${ins.unit}',
                      style: const TextStyle(fontSize: 11, color: _C.txtMuted, fontWeight: FontWeight.w600)),
                  Text('Target: ${ins.target} ${ins.unit}',
                      style: const TextStyle(fontSize: 11, color: _C.txtMuted, fontWeight: FontWeight.w600)),
                ]),
              ),
              Text(ins.tip,
                  style: const TextStyle(fontSize: 12, color: _C.txtSub, height: 1.45)),
            ]),
          );
        }).toList(),
      ]),
    );
  }
}

class _Insight {
  final String label;
  final int val, target;
  final String unit;
  final Color color;
  final String tip;
  const _Insight(this.label, this.val, this.target, this.unit, this.color, this.tip);
}

// ============================================================================
// PLAN TAB
// ============================================================================

class _PlanTab extends StatelessWidget {
  final Calculations calcs;
  const _PlanTab({required this.calcs});

  @override
  Widget build(BuildContext context) {
    const goalLabels = {
      Goal.lose:     'Weight Loss (−500 kcal/day)',
      Goal.gain:     'Weight Gain (+500 kcal/day)',
      Goal.maintain: 'Maintain Weight',
    };

    final notes = [
      ['Focus on protein intake.',  'Aim for lean proteins — chicken, fish, eggs or legumes at every meal.'],
      ['Stay hydrated.',            'Drink at least 8 cups of water daily. Hydration aids digestion and metabolism.'],
      ['Balance your macros.',      'Target: ${calcs.targetCarbs}g carbs · ${calcs.targetProtein}g protein · ${calcs.targetFat}g fat / day.'],
      ['Focus on whole foods.',     'Minimise ultra-processed foods. Choose foods with short ingredient lists.'],
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Your Plan',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _C.txt)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _C.limeLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.lime),
          ),
          child: Column(children: [
            Text('BMI: ${calcs.bmi.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _C.txt)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: const BoxDecoration(color: _C.lime, borderRadius: BorderRadius.all(Radius.circular(100))),
              child: Text(goalLabels[calcs.goal] ?? '',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black)),
            ),
            const SizedBox(height: 8),
            Text('Daily Target: ${calcs.adjustedTdee} kcal',
                style: const TextStyle(fontSize: 13, color: _C.txtSub, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 16),
        ...MealName.values.map((mn) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${mn.label} Plan',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _C.txt)),
                    const SizedBox(height: 2),
                    Text('${calcs.mealLimits[mn] ?? 0} kcal',
                        style: const TextStyle(fontSize: 12, color: _C.txtSub)),
                  ]),
                  Icon(_mealIcons[mn], size: 22, color: _C.green),
                ],
              ),
            )),
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 12),
          child: Text('Trainer Notes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _C.txt)),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (int i = 0; i < notes.length; i++)
              Container(
                padding: EdgeInsets.only(bottom: i < notes.length - 1 ? 14 : 0),
                margin: EdgeInsets.only(bottom: i < notes.length - 1 ? 14 : 0),
                decoration: i < notes.length - 1
                    ? const BoxDecoration(border: Border(bottom: BorderSide(color: _C.border)))
                    : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('• ${notes[i][0]}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _C.txt)),
                  const SizedBox(height: 4),
                  Text(notes[i][1],
                      style: const TextStyle(fontSize: 13, color: _C.green, height: 1.45, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ============================================================================
// ACCOUNT TAB
// ============================================================================

class _AccountTab extends StatelessWidget {
  final UserProfile profile;
  final Calculations calcs;
  final VoidCallback onReset;
  const _AccountTab({required this.profile, required this.calcs, required this.onReset});

  void _confirmReset(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Reset Profile'),
      content: const Text("Clear your profile and today's logs?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () { Navigator.pop(ctx); onReset(); },
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
          child: const Text('Reset'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    const menu1 = ['🔥  Calorie Counter', '💧  Water Tracker', '👟  Step Counter', '⚖️  Weight Tracker', '⚙️  Preferences'];
    const menu2 = ['🔔  Notifications', '💳  Payment Methods', '✅  Billing & Subscriptions', '🔒  Account & Security', '❓  Help & Support', '⭐  Rate Us'];

    final stats = [
      [calcs.bmi.toStringAsFixed(1), 'BMI'],
      [calcs.adjustedTdee.toString(), 'kcal/day'],
      [calcs.goal.name, 'Goal'],
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _C.border),
          ),
          child: Column(children: [
            Container(
              width: 72, height: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: _C.lime, shape: BoxShape.circle),
              child: Text(profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.black)),
            ),
            const SizedBox(height: 12),
            Text(profile.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _C.txt)),
            const SizedBox(height: 4),
            Text('${_calcAge(profile.birthday)} yrs · ${profile.weightKg} kg · ${profile.heightCm} cm',
                style: const TextStyle(fontSize: 13, color: _C.txtSub)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: stats.map((s) {
              return Column(children: [
                Text(s[0],
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _C.txt)),
                const SizedBox(height: 2),
                Text(s[1].toUpperCase(),
                    style: const TextStyle(fontSize: 10, color: _C.txtMuted, fontWeight: FontWeight.w600)),
              ]);
            }).toList()),
          ]),
        ),
        const SizedBox(height: 16),
        ..._menuCard(menu1),
        ..._menuCard(menu2),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _confirmReset(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: const Text('Reset Profile & Data',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFDC2626))),
          ),
        ),
      ]),
    );
  }

  List<Widget> _menuCard(List<String> items) {
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (int i = 0; i < items.length; i++) ...[
            InkWell(
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(
                    child: Text(items[i],
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.txt)),
                  ),
                  const Text('›', style: TextStyle(color: _C.txtMuted)),
                ]),
              ),
            ),
            if (i < items.length - 1) const _Divider(),
          ],
        ]),
      ),
    ];
  }
}

// ============================================================================
// BOTTOM TAB BAR
// ============================================================================

class _TabBar extends StatelessWidget {
  final int active;
  final ValueChanged<int> onChange;
  const _TabBar({required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) {
    const tabs = [
      [Icons.home, 'Home'],
      [Icons.bar_chart, 'Insights'],
      [Icons.assignment, 'Plan'],
      [Icons.person, 'Account'],
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _C.surface,
        border: Border(top: BorderSide(color: _C.border)),
      ),
      padding: const EdgeInsets.only(bottom: 8, top: 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final isActive = i == active;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChange(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tabs[i][0] as IconData,
                          size: 22, color: isActive ? _C.green : _C.txtMuted),
                      const SizedBox(height: 3),
                      Text(tabs[i][1] as String,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isActive ? _C.green : _C.txtMuted)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
