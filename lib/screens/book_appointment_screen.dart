import 'package:flutter/material.dart';

class AppointmentBookingPage extends StatefulWidget {
  const AppointmentBookingPage({super.key});

  @override
  State<AppointmentBookingPage> createState() => _AppointmentBookingPageState();
}

class _AppointmentBookingPageState extends State<AppointmentBookingPage> {
  String tab = "cat";
  Map<String, dynamic>? activeCat;
  Map<String, dynamic>? activeSpec;
  final searchCtrl = TextEditingController();



final List<Map<String, dynamic>> hccTree = [
  {
    "id": "general",
    "label": "General & Everyday Care",
    "icon": "🩺",
    "specs": [
      {
        "name": "General Physician",
        "icon": "🩺",
        "live": true,
        "count": "98 doctors",
        "cost": 100,
        "conditions": [
          ["Fever", "🌡️"],
          ["Cold & flu", "🤧"],
          ["Cough & sore throat", "😷"],
          ["Headache", "🤕"],
          ["Sinus infection", "👃"],
          ["Body aches", "💪"],
          ["Fatigue", "😮‍💨"],
          ["Minor infections", "🩹"],
        ],
      },
      {
        "name": "Internal Medicine",
        "icon": "🏥",
        "cost": 100,
        "conditions": [
          ["Undiagnosed symptoms", "❓"],
          ["Multi-system complaints", "🩺"],
          ["Preventive screening", "🛡️"],
          ["Medication review", "💊"],
        ],
      },
      {
        "name": "Family Medicine",
        "icon": "👨‍👩‍👧",
        "cost": 100,
        "conditions": [
          ["Routine check-ups", "✅"],
          ["Whole-family illness", "👪"],
          ["Chronic-disease review", "📋"],
          ["Vaccination advice", "💉"],
        ],
      },
    ],
  },

  {
    "id": "mental",
    "label": "Mental Health",
    "icon": "🧠",
    "specs": [
      {
        "name": "Psychiatry",
        "icon": "🧠",
        "live": true,
        "count": "76 doctors",
        "cost": 1499,
        "conditions": [
          ["Anxiety", "😟"],
          ["Depression", "💭"],
          ["Bipolar follow-up", "🔄"],
          ["OCD", "🔁"],
          ["PTSD", "🌀"],
          ["Panic attacks", "⚡"],
          ["Insomnia", "😴"],
          ["ADHD follow-up", "🎯"],
        ],
      },
      {
        "name": "Psychology / Counselling",
        "icon": "💬",
        "cost": 1299,
        "conditions": [
          ["Stress", "😣"],
          ["Grief & loss", "🕊️"],
          ["Relationship issues", "💔"],
          ["Low self-esteem", "🪞"],
          ["Trauma support", "🤝"],
        ],
      },
      {
        "name": "Behavioral Health",
        "icon": "🧩",
        "cost": 999,
        "conditions": [
          ["Anger management", "🔥"],
          ["Adjustment difficulties", "🔀"],
          ["Substance-use concerns", "🚭"],
          ["Sleep-related anxiety", "🌙"],
        ],
      },
    ],
  },

  {
    "id": "skin",
    "label": "Skin & Hair",
    "icon": "🧴",
    "specs": [
      {
        "name": "Dermatology",
        "icon": "🧴",
        "live": true,
        "count": "35 doctors",
        "cost": 100,
        "conditions": [
          ["Acne", "🔴"],
          ["Eczema", "🌾"],
          ["Psoriasis", "🩹"],
          ["Skin rashes", "🌡️"],
          ["Hives", "🐝"],
          ["Rosacea", "🌹"],
          ["Fungal infections", "🍄"],
          ["Hair loss", "💈"],
          ["Nail problems", "💅"],
          ["Mole & skin checks", "🔎"],
        ],
      },
    ],
  },

  {
    "id": "women",
    "label": "Women's Health",
    "icon": "🌸",
    "specs": [
      {
        "name": "OB-GYN",
        "icon": "🌸",
        "count": "44 doctors",
        "cost": 1199,
        "conditions": [
          ["Irregular periods", "📅"],
          ["Painful periods", "😣"],
          ["PCOS", "🌺"],
          ["Contraception advice", "💊"],
          ["Vaginal infections", "🩺"],
          ["Pelvic pain", "⚡"],
          ["Prenatal teleconsult", "🤰"],
        ],
      },
      {
        "name": "Menopause Care",
        "icon": "🌙",
        "cost": 999,
        "conditions": [
          ["Hot flashes", "🔥"],
          ["Mood changes", "🎭"],
          ["Sleep disturbance", "😴"],
          ["HRT guidance", "💊"],
        ],
      },
      {
        "name": "Women's Mental Health",
        "icon": "💗",
        "cost": 1099,
        "conditions": [
          ["Postnatal depression", "🍼"],
          ["Perinatal anxiety", "🤱"],
          ["PMDD", "📆"],
        ],
      },
      {
        "name": "Lactation Consulting",
        "icon": "🤱",
        "cost": 699,
        "conditions": [
          ["Low milk supply", "🍼"],
          ["Latch problems", "👶"],
          ["Nipple pain", "🩹"],
          ["Weaning guidance", "🥄"],
        ],
      },
    ],
  },

  {
    "id": "men",
    "label": "Men's Health",
    "icon": "♂️",
    "specs": [
      {
        "name": "Men's Health",
        "icon": "♂️",
        "count": "19 doctors",
        "cost": 100,
        "conditions": [
          ["Erectile dysfunction", "💙"],
          ["Low testosterone", "📉"],
          ["Hair loss", "💈"],
          ["Prostate concerns", "🔬"],
          ["Low libido", "💤"],
        ],
      },
      {
        "name": "Urology",
        "icon": "🚹",
        "cost": 100,
        "conditions": [
          ["UTIs", "🚻"],
          ["Kidney stones follow-up", "🪨"],
          ["Blood in urine", "🩸"],
          ["Incontinence", "💧"],
          ["Bladder problems", "🚽"],
        ],
      },
    ],
  },

  {
    "id": "family",
    "label": "Children & Family",
    "icon": "🧒",
    "specs": [
      {
        "name": "Pediatrics",
        "icon": "🧒",
        "live": true,
        "count": "41 doctors",
        "cost": 699,
        "conditions": [
          ["Fever in children", "🌡️"],
          ["Cough & cold", "🤧"],
          ["Childhood rashes", "🌸"],
          ["Ear infections", "👂"],
          ["Feeding concerns", "🍼"],
          ["Growth & development", "📏"],
          ["Vaccination advice", "💉"],
        ],
      },
      {
        "name": "Adolescent Care",
        "icon": "🧑",
        "cost": 699,
        "conditions": [
          ["Teen acne", "🔴"],
          ["Puberty concerns", "🌱"],
          ["Teen mood & anxiety", "😟"],
          ["Menstrual problems", "📅"],
          ["Sports injuries", "🏃"],
        ],
      },
    ],
  },

  {
    "id": "weight",
    "label": "Weight & Nutrition",
    "icon": "🥗",
    "specs": [
      {
        "name": "Weight Management",
        "icon": "⚖️",
        "cost": 999,
        "conditions": [
          ["Obesity", "📊"],
          ["GLP-1 eligibility", "💉"],
          ["Metabolic syndrome", "🔬"],
          ["Weight-loss planning", "🎯"],
          ["Binge eating", "🍽️"],
        ],
      },
      {
        "name": "Nutrition & Dietetics",
        "icon": "🥗",
        "cost": 699,
        "conditions": [
          ["Diabetic diet", "🩸"],
          ["Cholesterol diet", "🫀"],
          ["Food-intolerance plan", "🚫"],
          ["Pregnancy nutrition", "🤰"],
          ["Sports nutrition", "🏋️"],
        ],
      },
      {
        "name": "Lifestyle Medicine",
        "icon": "🌱",
        "cost": 599,
        "conditions": [
          ["Healthy-habit coaching", "✅"],
          ["Diet & exercise plan", "🏃"],
          ["Sleep hygiene", "😴"],
          ["Stress reduction", "🧘"],
        ],
      },
    ],
  },

  {
    "id": "chronic",
    "label": "Chronic Care & Expert Opinion",
    "icon": "📋",
    "specs": [
      {
        "name": "Cardiology",
        "icon": "🫀",
        "live": true,
        "count": "48 doctors",
        "cost": 1799,
        "conditions": [
          ["High blood pressure", "💉"],
          ["Chest pain (non-emerg.)", "❤️"],
          ["Palpitations", "💓"],
          ["High cholesterol", "🩸"],
          ["Heart failure follow-up", "🫀"],
        ],
      },
      {
        "name": "Neurology",
        "icon": "🧬",
        "live": true,
        "count": "32 doctors",
        "cost": 1699,
        "conditions": [
          ["Migraine & headaches", "🤕"],
          ["Seizures follow-up", "⚡"],
          ["Numbness & tingling", "🖐️"],
          ["Tremor", "🤲"],
          ["Dizziness", "💫"],
          ["Memory concerns", "🧠"],
        ],
      },
      {
        "name": "Endocrinology",
        "icon": "⚕️",
        "cost": 1499,
        "conditions": [
          ["Thyroid disorders", "🦋"],
          ["Diabetes (Type 1 & 2)", "🩸"],
          ["PCOS", "🌺"],
          ["Hormone imbalance", "⚗️"],
          ["Osteoporosis", "🦴"],
        ],
      },
      {
        "name": "Gastroenterology",
        "icon": "🍽️",
        "cost": 1399,
        "conditions": [
          ["Acid reflux / GERD", "🔥"],
          ["IBS", "🌀"],
          ["Constipation", "🚽"],
          ["Stomach pain", "😣"],
          ["Bloating", "🎈"],
        ],
      },
      {
        "name": "Pulmonology",
        "icon": "🫁",
        "cost": 1299,
        "conditions": [
          ["Asthma", "💨"],
          ["COPD", "🫁"],
          ["Chronic cough", "😷"],
          ["Shortness of breath", "😮‍💨"],
          ["Sleep apnea screening", "😴"],
        ],
      },
      {
        "name": "Expert Medical Opinion",
        "icon": "📑",
        "cost": 2499,
        "conditions": [
          ["Cancer second opinion", "🎗️"],
          ["Surgery second opinion", "🏥"],
          ["Complex-diagnosis review", "🔍"],
          ["Treatment-plan review", "📋"],
        ],
      },
    ],
  },

  {
    "id": "eeb",
    "label": "Eye, Ear & Bone",
    "icon": "🦴",
    "specs": [
      {
        "name": "Ophthalmology",
        "icon": "👁️",
        "live": true,
        "count": "22 doctors",
        "cost": 999,
        "conditions": [
          ["Red / irritated eyes", "👁️"],
          ["Dry eyes", "🌵"],
          ["Vision changes", "🔭"],
          ["Eye infections", "🦠"],
          ["Stye", "💢"],
        ],
      },
      {
        "name": "ENT",
        "icon": "👂",
        "cost": 899,
        "conditions": [
          ["Sinusitis", "👃"],
          ["Sore throat / tonsillitis", "😮"],
          ["Ear infections", "👂"],
          ["Vertigo", "💫"],
          ["Nasal congestion", "🤧"],
        ],
      },
      {
        "name": "Orthopedics",
        "icon": "🦴",
        "live": true,
        "count": "29 doctors",
        "cost": 1299,
        "conditions": [
          ["Back pain", "🔙"],
          ["Neck pain", "🧍"],
          ["Knee & joint pain", "🦵"],
          ["Sprains & strains", "🤕"],
          ["Sports injuries", "🏃"],
        ],
      },
    ],
  },

  {
    "id": "sexual",
    "label": "Sexual Health",
    "icon": "💗",
    "specs": [
      {
        "name": "Sexual Health",
        "icon": "💗",
        "cost": 799,
        "conditions": [
          ["STI advice & testing", "🔬"],
          ["Contraception advice", "💊"],
          ["Erectile dysfunction", "💙"],
          ["Confidential care", "🤐"],
          ["Safe-sex counselling", "🤝"],
        ],
      },
    ],
  },

  {
    "id": "travel",
    "label": "Travel & Global Care",
    "icon": "✈️",
    "specs": [
      {
        "name": "Travel Medicine",
        "icon": "✈️",
        "cost": 899,
        "conditions": [
          ["Pre-travel vaccination", "💉"],
          ["Malaria prevention", "🦟"],
          ["Altitude sickness", "⛰️"],
          ["Travel-illness advice", "🤒"],
          ["Post-travel symptoms", "🌡️"],
        ],
      },
      {
        "name": "Global / Cross-Border Care",
        "icon": "🌍",
        "cost": 1999,
        "conditions": [
          ["Cross-border consult", "🌐"],
          ["Care continuity abroad", "🔄"],
          ["Referral coordination", "🗺️"],
          ["Travel medical assistance", "🆘"],
          ["Prescription continuity", "💊"],
        ],
      },
    ],
  },
];
  String get q => searchCtrl.text.trim().toLowerCase();

  List<Map<String, dynamic>> get flatSpecs {
    return hccTree.expand((cat) {
      return (cat["specs"] as List).map((spec) {
        return {
          ...Map<String, dynamic>.from(spec),
          "catLabel": cat["label"],
          "catIcon": cat["icon"],
        };
      });
    }).where((spec) {
      return q.isEmpty || spec["name"].toString().toLowerCase().contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get flatConditions {
    return flatSpecs.expand((spec) {
      return (spec["conditions"] as List).map((cond) {
        return {
          "name": cond[0],
          "icon": cond[1],
          "spec": spec,
        };
      });
    }).where((cond) {
      return q.isEmpty ||
          cond["name"].toString().toLowerCase().contains(q) ||
          cond["spec"]["name"].toString().toLowerCase().contains(q);
    }).toList();
  }

  void selectCondition(String name, String icon, Map<String, dynamic> spec) {
    Navigator.pushNamed(
      context,
      "/appointment-form",
      arguments: {
        "specName": spec["name"],
        "specIcon": spec["icon"],
        "catLabel": spec["catLabel"] ?? activeCat?["label"],
        "cost": spec["cost"],
        "condName": name,
        "condIcon": icon,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = tab == "cat"
        ? "Search categories..."
        : tab == "spec"
            ? "Search specialties..."
            : "Search conditions / symptoms...";

    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text("Find Doctor"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "Find the right online doctor for your needs.",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              "Book an online doctor appointment in minutes.",
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                _tabButton("01", "Categories", "cat"),
                _tabButton("02", "Specialties", "spec"),
                _tabButton("03", "Conditions", "cond"),
              ],
            ),

            const SizedBox(height: 14),

            TextField(
              controller: searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: placeholder,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 18),

            if (tab == "cat") _categoryView(),
            if (tab == "spec") _specialtyView(),
            if (tab == "cond") _conditionView(),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String num, String label, String value) {
    final active = tab == value;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            tab = value;
            activeCat = null;
            activeSpec = null;
            searchCtrl.clear();
          });
        },
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                num,
                style: TextStyle(
                  color: active ? Colors.white : Colors.black54,
                  fontSize: 11,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryView() {
    final cats = hccTree.where((cat) {
      return q.isEmpty ||
          cat["label"].toString().toLowerCase().contains(q);
    }).toList();

    return Column(
      children: cats.map((cat) {
        final specs = cat["specs"] as List;
        final conditionCount = specs.fold<int>(
          0,
          (sum, spec) => sum + (spec["conditions"] as List).length,
        );

        return _card(
          icon: cat["icon"],
          title: cat["label"],
          subtitle: "${specs.length} specialties · $conditionCount conditions",
          trailing: "Explore →",
          onTap: () {
            setState(() {
              activeCat = cat;
              tab = "spec";
              searchCtrl.clear();
            });
          },
        );
      }).toList(),
    );
  }

  Widget _specialtyView() {
    final specs = activeCat != null
        ? (activeCat!["specs"] as List).map((s) {
            return {
              ...Map<String, dynamic>.from(s),
              "catLabel": activeCat!["label"],
            };
          }).where((s) {
            return q.isEmpty ||
                s["name"].toString().toLowerCase().contains(q);
          }).toList()
        : flatSpecs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeCat != null) _backCrumb("All Categories", activeCat!["label"]),
        ...specs.map((spec) {
          return _card(
            icon: spec["icon"],
            title: spec["name"],
            subtitle: spec["count"] ?? "Book now",
            badge: spec["live"] == true ? "LIVE" : null,
            trailing: "Select →",
            onTap: () {
              setState(() {
                activeSpec = spec;
                tab = "cond";
                searchCtrl.clear();
              });
            },
          );
        }),
      ],
    );
  }

  Widget _conditionView() {
    final conditions = activeSpec != null
        ? (activeSpec!["conditions"] as List)
            .map((c) => {
                  "name": c[0],
                  "icon": c[1],
                  "spec": activeSpec!,
                })
            .where((c) {
              return q.isEmpty ||
                  c["name"].toString().toLowerCase().contains(q);
            }).toList()
        : flatConditions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeSpec != null) _backCrumb("Specialties", activeSpec!["name"]),
        ...conditions.map((cond) {
          return _card(
            icon: cond["icon"],
            title: cond["name"],
            subtitle: cond["spec"]["name"],
            trailing: "Book →",
            onTap: () {
              selectCondition(
                cond["name"],
                cond["icon"],
                cond["spec"],
              );
            },
          );
        }),
        if (activeSpec != null)
          _card(
            icon: "💬",
            title: "Other / not listed",
            subtitle: activeSpec!["name"],
            trailing: "Book →",
            onTap: () {
              selectCondition(
                "General Consultation",
                "🩺",
                activeSpec!,
              );
            },
          ),
      ],
    );
  }

  Widget _backCrumb(String first, String second) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                tab = first == "All Categories" ? "cat" : "spec";
                activeSpec = null;
              });
            },
            child: Text(
              first,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Text("  ›  "),
          Expanded(
            child: Text(
              second,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String icon,
    required String title,
    required String subtitle,
    required String trailing,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              trailing,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
