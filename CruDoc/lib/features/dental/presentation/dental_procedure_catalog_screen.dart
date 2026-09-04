import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../data/models/dental_procedure_catalog_model.dart';
import '../data/seed/dental_catalog_seed.dart';
import 'providers/dental_providers.dart';

const Color _accentTeal = Color(0xFF0D9488);

/// Procedure Catalog Screen for Dental Clinics.
///
/// Allows dentists to browse, search, filter, create, edit, and archive dental procedures.
class DentalProcedureCatalogScreen extends ConsumerStatefulWidget {
  const DentalProcedureCatalogScreen({super.key});

  @override
  ConsumerState<DentalProcedureCatalogScreen> createState() =>
      _DentalProcedureCatalogScreenState();
}

class _DentalProcedureCatalogScreenState
    extends ConsumerState<DentalProcedureCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();

  String get _currentDoctorId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';

  static const List<String> _categories = [
    'All',
    'General',
    'Preventive',
    'Restorative',
    'Endodontic',
    'Prosthodontic',
    'Periodontic',
    'Surgery',
    'Cosmetic',
  ];

  String _selectedCategory = 'All';
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openProcedureDialog({DentalProcedureCatalogModel? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final codeController = TextEditingController(text: existing?.code ?? '');
    final priceController = TextEditingController(
      text: existing?.defaultPrice != null ? existing!.defaultPrice!.toStringAsFixed(0) : '',
    );
    String selectedCategory = existing?.category ?? 'General';
    bool requiresToothSelection = existing?.requiresToothSelection ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Procedure' : 'Edit Procedure'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Procedure Name *',
                        hintText: 'e.g. Ceramic Crown',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'Procedure Code *',
                        hintText: 'e.g. CROWN',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _categories.contains(selectedCategory)
                          ? selectedCategory
                          : 'General',
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: _categories
                          .where((c) => c != 'All')
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedCategory = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Default Fee (₹)',
                        hintText: 'e.g. 5000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Requires Tooth Selection'),
                      subtitle: const Text('Tooth number needed when logging'),
                      value: requiresToothSelection,
                      onChanged: (val) {
                        setDialogState(() => requiresToothSelection = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                  onPressed: () {
                    if (nameController.text.trim().isEmpty ||
                        codeController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name and Code are required')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      final now = DateTime.now();
      final price = double.tryParse(priceController.text.trim());
      final item = DentalProcedureCatalogModel(
        id: existing?.id ?? const Uuid().v4(),
        doctorId: _currentDoctorId,
        code: codeController.text.trim().toUpperCase(),
        name: nameController.text.trim(),
        category: selectedCategory,
        defaultPrice: price,
        requiresToothSelection: requiresToothSelection,
        isActive: existing?.isActive ?? true,
        isDeleted: false,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        syncStatus: 'pending',
      );

      await ref.read(dentalRepositoryProvider).saveCatalogItem(item);
      ref.invalidate(dentalCatalogProvider(_currentDoctorId));
    }
  }

  Future<void> _toggleArchive(DentalProcedureCatalogModel item) async {
    final repo = ref.read(dentalRepositoryProvider);
    if (item.isActive) {
      await repo.archiveCatalogItem(item.id);
    } else {
      await repo.restoreCatalogItem(item.id);
    }
    ref.invalidate(dentalCatalogProvider(_currentDoctorId));
  }

  Future<void> _seedStandardProcedures() async {
    final repo = ref.read(dentalRepositoryProvider);
    final count = await DentalCatalogSeed.seedIfNeeded(repo, _currentDoctorId);
    ref.invalidate(dentalCatalogProvider(_currentDoctorId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0
              ? 'Added $count standard dental procedures'
              : 'Standard dental procedures already loaded'),
        ),
      );
    }
  }

  List<DentalProcedureCatalogModel> _filterProcedures(
    List<DentalProcedureCatalogModel> list,
  ) {
    return list.where((p) {
      final matchesCategory = _selectedCategory == 'All' ||
          p.category.toLowerCase() == _selectedCategory.toLowerCase();
      final matchesQuery = _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery) ||
          p.code.toLowerCase().contains(_searchQuery);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rawCatalog = ref.watch(dentalCatalogProvider(_currentDoctorId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dental Procedure Catalog'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Seed Standard Procedures',
            icon: const Icon(Icons.auto_fix_high_rounded, color: _accentTeal),
            onPressed: _seedStandardProcedures,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accentTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Procedure'),
        onPressed: () => _openProcedureDialog(),
      ),
      body: Column(
        children: [
          // Search & Filter header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search procedure or code...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val.trim().toLowerCase());
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (context, sepIndex) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final cat = _categories[idx];
                      final isSelected = cat == _selectedCategory;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: const Color(0xFFCCFBF1),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected ? _accentTeal : const Color(0xFF64748B),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCategory = cat);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Catalog List
          Expanded(
            child: rawCatalog.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading catalog: $err')),
              data: (allProcedures) {
                final procedures = _filterProcedures(allProcedures);

                if (procedures.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.menu_book_rounded, size: 48, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 12),
                        const Text(
                          'No procedures found',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.download_rounded, color: _accentTeal),
                          label: const Text('Load Standard Indian Dental Procedures'),
                          onPressed: _seedStandardProcedures,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 80, top: 8),
                  itemCount: procedures.length,
                  separatorBuilder: (context, sepIndex) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final proc = procedures[index];
                    return ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              proc.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: proc.isActive ? null : TextDecoration.lineThrough,
                                color: proc.isActive
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                          if (!proc.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ARCHIVED',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${proc.code} • ${proc.category}${proc.requiresToothSelection ? ' • Tooth-specific' : ' • Clinic-level'}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (proc.defaultPrice != null)
                            Text(
                              '₹${proc.defaultPrice!.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF64748B)),
                            onSelected: (val) {
                              if (val == 'edit') {
                                _openProcedureDialog(existing: proc);
                              } else if (val == 'archive') {
                                _toggleArchive(proc);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text(proc.isActive ? 'Archive' : 'Restore'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
