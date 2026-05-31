# Virtual Gum Health Analyzer (طبيب اللثة الافتراضي)

An interactive clinical screening tool that assesses patient gum health based on standard periodontal indicators: tissue color, bleeding tendencies, swelling, plaque/calculus buildup, breath odor, and smoking status. It computes a cumulative severity score and generates custom clinical recommendations.

---

## 🩺 Diagnostic Criteria & Input Metrics

The analyzer evaluates six diagnostic components:

1. **Gingival Color (اللون)**: Evaluates signs of capillary congestion/hyperemia.
   * وردي طبيعي (Natural Pink): **0 points**
   * أحمر زاهي (Bright Red): **1 point**
   * داكن (Dark Red/Purple): **2 points**
2. **Gingival Bleeding (النزيف)**: Measured using an incremental sensitivity scale.
   * لا يوجد (None): **0 points**
   * بسيط (Mild): **1 point**
   * واضح (Moderate): **2 points**
   * تلقائي (Spontaneous): **3 points**
3. **Gingival Swelling (التورم)**: Measures edema severity.
   * لا يوجد (None): **0 points**
   * بسيط (Mild): **1 point**
   * شديد (Severe): **2 points**
4. **Calculus/Plaque Buildup (الجير)**: Measures calcified mineral deposits.
   * لا يوجد (None): **0 points**
   * بسيط (Mild): **1 point**
   * كثيف (Heavy): **2 points**
5. **Halitosis (رائحة الفم)**: Indication of volatile sulfur compounds (VSCs) produced by anaerobic bacteria.
   * No: **0 points**
   * Yes: **1 point**
6. **Smoking Status (التدخين)**: Critical vasoconstrictive cofactor (nicotine hides bleeding while accelerating alveolar bone loss).
   * No: **0 points**
   * Yes: **1 point**

---

## ⚖️ Scoring Weights & Math

Each indicator is assigned a clinical weight reflecting its diagnostic importance:

| Indicator | Metric Variable | Clinical Weight | Max Subscore |
| :--- | :--- | :--- | :--- |
| **Bleeding** | $B$ | $\times 3$ | $9$ |
| **Redness** | $R$ | $\times 2$ | $4$ |
| **Swelling** | $S$ | $\times 2$ | $4$ |
| **Calculus** | $C$ | $\times 2$ | $4$ |
| **Halitosis** | $H$ | $\times 1$ | $1$ |
| **Smoking** | $K$ | $\times 1$ | $1$ |

$$\text{Total Score} = (B \times 3) + (R \times 2) + (S \times 2) + (C \times 2) + (H \times 1) + (K \times 1)$$

* *Maximum Possible Score*: **23**

---

## 📊 Severity Classification Bands

Based on the total score, the patient's gum health is classified into four diagnostic bands:

| Score Range | Severity Status | UI Theme Gradient | Visual Status Icon |
| :--- | :--- | :--- | :--- |
| **$0 - 5$** | **لثة سليمة (Healthy Gums)** | `#11998e` $\rightarrow$ `#38ef7d` (Teal/Green) | `✅` |
| **$6 - 11$** | **التهاب خفيف (Mild Gingivitis)** | `#f7971e` $\rightarrow$ `#ffd200` (Orange/Yellow) | `⚠️` |
| **$12 - 18$** | **التهاب متوسط (Moderate Gingivitis)** | `#cb2d3e` $\rightarrow$ `#ef473a` (Red/Bright Red) | `🚨` |
| **$19 - 23$** | **التهاب شديد (Severe Periodontitis)** | `#4b1248` $\rightarrow$ `#f03023` (Purple/Dark Red) | `🛑` |

---

## 💡 Personalized Advice Engine

Specific, actionable clinical advice is dynamically selected depending on the severity of the symptoms:

* **Bleeding (نزيف $\ge 2$)**:
  > 🩸 **للنزيف:** لا تتوقف عن التفريش بسبب الدم؛ النزيف دليل التهاب بكتيري يحتاج تنظيفاً أعمق ولكن بلطف.
* **Redness (احمرار $\ge 1$)**:
  > 🎨 **للون:** احمرار اللثة يعني احتقان الأوعية؛ استخدم مضمضة تحتوي على مياه دافئة وملح لتهدئة الأنسجة.
* **Swelling (تورم $\ge 1$)**:
  > 🎈 **للتورم:** تجنب الأطعمة الصلبة التي قد تجرح اللثة المنفوخة، واستخدم فرشاة أسنان فائقة النعومة (Ultra-Soft).
* **Calculus (جير $\ge 1$)**:
  > 🧱 **للجير:** الجير لا يزول بالفرشاة؛ أنت بحاجة لتنظيف احترافي في العيادة لمنع تآكل العظم السنخي.
* **Halitosis (رائحة الفم)**:
  > 🌬️ **للرائحة:** اهتم بتنظيف سطح اللسان، فهو مخزن رئيسي للبكتيريا المسببة للرائحة.
* **Smoking (مدخن)**:
  > 🚬 **للتدخين:** النيكوتين يضيق الأوعية ويخفي النزيف؛ لثتك قد تكون أسوأ مما تبدو عليه، لذا الفحص الدوري ضروري.
* **Healthy Gums (No tips generated)**:
  > ✨ لثتك تبدو مثالية! استمر على غسل الأسنان مرتين يومياً واستخدم الخيط.

---

## 📂 Source Notebooks
* **`Gingivitis.ipynb`**: Contains the full Python implementation using `ipywidgets` to render a patient-friendly graphical simulator interface and run the diagnostic advice calculations.
