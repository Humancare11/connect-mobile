import 'package:flutter/material.dart';

import '../services/appointment_tree_service.dart';

class AppointmentBookingPage extends StatefulWidget {
  final String? initialCategoryLabel;
  final String? initialSpecialtyName;
  final String initialTab;

  const AppointmentBookingPage({
    super.key,
    this.initialCategoryLabel,
    this.initialSpecialtyName,
    this.initialTab = "cat",
  });

  @override
  State<AppointmentBookingPage> createState() => _AppointmentBookingPageState();
}

class _AppointmentBookingPageState extends State<AppointmentBookingPage> {
  final _treeService = AppointmentTreeService();
  final searchCtrl = TextEditingController();

  String tab = "cat";
  Map<String, dynamic>? activeCat;
  Map<String, dynamic>? activeSpec;
  List<Map<String, dynamic>> hccTree = const [];
  bool loadingTree = true;
  String? treeError;

  @override
  void initState() {
    super.initState();

    if (widget.initialTab == "spec" || widget.initialTab == "cond") {
      tab = widget.initialTab;
    }

    _loadAppointmentTree();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAppointmentTree() async {
    setState(() {
      loadingTree = true;
      treeError = null;
    });

    final result = await _treeService.fetchTree();
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        loadingTree = false;
        treeError = result.message;
      });
      return;
    }

    setState(() {
      hccTree = (result.data ?? const [])
          .map((category) => category.toUiMap())
          .toList();
      loadingTree = false;
    });
    _applyInitialSelection();
  }

  void _applyInitialSelection() {
    final initialSpecialty = widget.initialSpecialtyName;
    if (initialSpecialty != null) {
      _selectInitialSpecialty(initialSpecialty);
      return;
    }

    final initialLabel = widget.initialCategoryLabel;
    if (initialLabel == null) return;

    for (final cat in hccTree) {
      if (_normalizeLabel(cat["label"].toString()) ==
          _normalizeLabel(initialLabel)) {
        setState(() {
          activeCat = cat;
          tab = "spec";
        });
        break;
      }
    }
  }

  String _normalizeLabel(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  void _selectInitialSpecialty(String specialtyName) {
    final target = _normalizeLabel(specialtyName);

    for (final cat in hccTree) {
      for (final spec in cat["specs"] as List) {
        if (_normalizeLabel(spec["name"].toString()) == target) {
          setState(() {
            activeCat = cat;
            activeSpec = {
              ...Map<String, dynamic>.from(spec),
              "catLabel": cat["label"],
              "catIcon": cat["icon"],
            };
            tab = "cond";
          });
          return;
        }
      }
    }
  }

  String get q => searchCtrl.text.trim().toLowerCase();

  List<Map<String, dynamic>> get flatSpecs {
    return hccTree
        .expand((cat) {
          return (cat["specs"] as List).map((spec) {
            return {
              ...Map<String, dynamic>.from(spec),
              "catLabel": cat["label"],
              "catIcon": cat["icon"],
            };
          });
        })
        .where((spec) {
          return q.isEmpty || spec["name"].toString().toLowerCase().contains(q);
        })
        .toList();
  }

  List<Map<String, dynamic>> get flatConditions {
    return flatSpecs
        .expand((spec) {
          return (spec["conditions"] as List).map((cond) {
            return {
              "name": cond[0],
              "icon": cond.length > 1 ? cond[1] : "",
              "spec": spec,
            };
          });
        })
        .where((cond) {
          return q.isEmpty ||
              cond["name"].toString().toLowerCase().contains(q) ||
              cond["spec"]["name"].toString().toLowerCase().contains(q);
        })
        .toList();
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
            if (loadingTree) _loadingState(),
            if (!loadingTree && treeError != null) _errorState(treeError!),
            if (!loadingTree && treeError == null && hccTree.isEmpty)
              _emptyState("No appointment categories are available."),
            if (!loadingTree && treeError == null && hccTree.isNotEmpty) ...[
              if (tab == "cat") _categoryView(),
              if (tab == "spec") _specialtyView(),
              if (tab == "cond") _conditionView(),
            ],
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
      return q.isEmpty || cat["label"].toString().toLowerCase().contains(q);
    }).toList();

    if (cats.isEmpty) return _emptyState("No categories match your search.");

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
          subtitle: "${specs.length} specialties - $conditionCount conditions",
          trailing: "Explore",
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
        ? (activeCat!["specs"] as List)
              .map((s) {
                return {
                  ...Map<String, dynamic>.from(s),
                  "catLabel": activeCat!["label"],
                };
              })
              .where((s) {
                return q.isEmpty ||
                    s["name"].toString().toLowerCase().contains(q);
              })
              .toList()
        : flatSpecs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeCat != null)
          _backCrumb("All Categories", activeCat!["label"]),
        if (specs.isEmpty) _emptyState("No specialties are available."),
        ...specs.map((spec) {
          final count = spec["count"]?.toString().trim() ?? "";
          return _card(
            icon: spec["icon"],
            title: spec["name"],
            subtitle: count.isEmpty ? "Book now" : count,
            badge: spec["live"] == true ? "LIVE" : null,
            trailing: "Select",
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
              .map(
                (c) => {
                  "name": c[0],
                  "icon": c.length > 1 ? c[1] : "",
                  "spec": activeSpec!,
                },
              )
              .where((c) {
                return q.isEmpty ||
                    c["name"].toString().toLowerCase().contains(q);
              })
              .toList()
        : flatConditions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeSpec != null) _backCrumb("Specialties", activeSpec!["name"]),
        if (conditions.isEmpty) _emptyState("No conditions are available."),
        ...conditions.map((cond) {
          return _card(
            icon: cond["icon"],
            title: cond["name"],
            subtitle: cond["spec"]["name"],
            trailing: "Book",
            onTap: () {
              selectCondition(cond["name"], cond["icon"], cond["spec"]);
            },
          );
        }),
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
          const Text("  >  "),
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

  Widget _loadingState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _box(),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _errorState(String message) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Unable to load appointment options.",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            message.isEmpty ? "Please try again." : message,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _loadAppointmentTree,
            child: const Text("Try again"),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Text(message, style: const TextStyle(color: Colors.black54)),
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
    final hasIcon = icon.trim().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: _box(),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: hasIcon
                  ? Text(icon, style: const TextStyle(fontSize: 30))
                  : const Icon(Icons.medical_services_outlined, size: 30),
            ),
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
                  Text(subtitle, style: const TextStyle(color: Colors.black54)),
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

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
