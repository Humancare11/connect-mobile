import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
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

  // Scaffold tint — swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);
  // "LIVE" badge accent (on-brand green, matches the app's status colours).
  static const Color _live = Color(0xFF63C06B);

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
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: const Text("Find Doctor"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              "Find the right online doctor for your needs.",
              style: AppType.display(size: 23, height: 1.15),
            ),
            const SizedBox(height: 8),
            Text(
              "Book an online doctor appointment in minutes.",
              style: AppType.body(size: 14)
                  .copyWith(color: AppColors.textSecondary),
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
              style: AppType.body(size: 14)
                  .copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: AppType.body(size: 14)
                    .copyWith(color: AppColors.textSecondary),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide:
                      const BorderSide(color: AppColors.border, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.6),
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
            color: active ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              Text(
                num,
                style: AppType.body(size: 11).copyWith(
                  color:
                      active ? Colors.white.withValues(alpha: 0.75) : AppColors.textSecondary,
                ),
              ),
              Text(
                label,
                style: AppType.body(size: 12, weight: FontWeight.w700).copyWith(
                  color: active ? Colors.white : AppColors.textPrimary,
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
          subtitle: "${specs.length} specialties · $conditionCount conditions",
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
              style: AppType.body(size: 13, weight: FontWeight.w700)
                  .copyWith(color: AppColors.primary),
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: AppColors.textSecondary),
          Expanded(
            child: Text(
              second,
              style: AppType.body(size: 13, weight: FontWeight.w700)
                  .copyWith(color: AppColors.textPrimary),
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
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  Widget _errorState(String message) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Unable to load appointment options.",
            style: AppType.display(size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            message.isEmpty ? "Please try again." : message,
            style: AppType.body(size: 13)
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _loadAppointmentTree,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
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
      child: Text(
        message,
        style: AppType.body(size: 13)
            .copyWith(color: AppColors.textSecondary),
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
    final hasIcon = icon.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: _box(),
            child: Row(
              children: [
                // Soft tinted icon square (consistent with the rest of the app)
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: hasIcon
                      ? Text(icon,
                          style: const TextStyle(fontSize: 22, height: 1))
                      : const Icon(Icons.medical_services_outlined,
                          size: 22, color: AppColors.primary),
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.body(
                                  size: 15.5, weight: FontWeight.w700),
                            ),
                          ),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _live.withValues(alpha: 0.14),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.chip),
                              ),
                              child: Text(
                                badge,
                                style: AppType.body(
                                        size: 10, weight: FontWeight.w700)
                                    .copyWith(color: _live),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(size: 12.5)
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  trailing,
                  style: AppType.body(size: 13, weight: FontWeight.w700)
                      .copyWith(color: AppColors.primary),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border, width: 1.2),
      boxShadow: AppShadows.subtle,
    );
  }
}