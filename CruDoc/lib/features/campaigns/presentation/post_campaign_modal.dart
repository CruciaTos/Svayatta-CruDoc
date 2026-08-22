import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import '../data/models/campaign_model.dart';
import '../data/models/campaign_enums.dart';
import '../data/services/campaign_audience_helper.dart';
import '../data/services/campaign_dispatch_service.dart';

/// Interactive modal wizard allowing doctors to compose, target, preview,
/// and dispatch campaigns to patients via Email and WhatsApp.
class PostCampaignModal extends StatefulWidget {
  const PostCampaignModal({
    super.key,
    this.initialCategory,
    this.onCampaignPublished,
  });

  final CampaignCategory? initialCategory;
  final VoidCallback? onCampaignPublished;

  static Future<bool?> show(
    BuildContext context, {
    CampaignCategory? initialCategory,
    VoidCallback? onCampaignPublished,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
          child: PostCampaignModal(
            initialCategory: initialCategory,
            onCampaignPublished: onCampaignPublished,
          ),
        ),
      ),
    );
  }

  @override
  State<PostCampaignModal> createState() => _PostCampaignModalState();
}

class _PostCampaignModalState extends State<PostCampaignModal> {
  static const _uuid = Uuid();
  final PatientRepository _patientRepository = PatientRepository();
  final CampaignDispatchService _dispatchService = CampaignDispatchService();

  int _currentStep = 0; // 0: Compose, 1: Audience & Channels, 2: Preview, 3: Dispatching

  // Step 1: Content
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _mediaUrlController = TextEditingController();
  late CampaignCategory _selectedCategory;

  // Step 2: Audience & Channels
  AudienceType _selectedAudienceType = AudienceType.all;
  final _conditionFilterController = TextEditingController();
  String _selectedGender = 'all';
  int _selectedAgeMin = 0;
  int _selectedAgeMax = 120;
  final Set<String> _selectedPatientIds = {};

  bool _enableEmail = true;
  bool _enableWhatsApp = true;

  // Patient Cache
  List<Patient> _allPatients = [];
  bool _isLoadingPatients = true;
  String _patientSearchQuery = '';

  // Doctor / Clinic Info
  String _doctorName = 'Dr. Specialist';
  String _clinicName = 'CruDoc Medical Center';

  // Step 4: Dispatch State
  bool _isDispatching = false;
  int _dispatchProcessed = 0;
  int _dispatchTotal = 0;
  CampaignModel? _dispatchedCampaign;
  String? _dispatchError;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? CampaignCategory.generalAnnouncement;
    _loadInitialData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _mediaUrlController.dispose();
    _conditionFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final profileSnap = await DoctorProfileHelper.watchDoctorProfile(user).first;
        if (profileSnap != null) {
          final dName = DoctorProfileHelper.formatDoctorName(user, profileSnap);
          final cName = DoctorProfileHelper.formatClinicName(user, profileSnap);
          if (mounted) {
            setState(() {
              _doctorName = dName;
              _clinicName = cName;
            });
          }
        }
      }

      final patients = await _patientRepository.getAllPatients();
      if (mounted) {
        setState(() {
          _allPatients = patients;
          _isLoadingPatients = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPatients = false);
      }
    }
  }

  List<Patient> get _filteredAudience {
    final Map<String, dynamic> filters = {};
    if (_selectedAudienceType == AudienceType.byDiagnosis) {
      filters['condition'] = _conditionFilterController.text;
    } else if (_selectedAudienceType == AudienceType.byGender) {
      filters['gender'] = _selectedGender;
    } else if (_selectedAudienceType == AudienceType.byAgeGroup) {
      filters['minAge'] = _selectedAgeMin;
      filters['maxAge'] = _selectedAgeMax;
    }

    return CampaignAudienceHelper.filterPatients(
      allPatients: _allPatients,
      audienceType: _selectedAudienceType,
      filters: filters,
      selectedPatientIds: _selectedPatientIds.toList(),
    );
  }

  void _insertPlaceholder(String token) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final newText = text.replaceRange(
      selection.start < 0 ? text.length : selection.start,
      selection.end < 0 ? text.length : selection.end,
      token,
    );
    _messageController.text = newText;
    _messageController.selection = TextSelection.collapsed(
      offset: (selection.start < 0 ? text.length : selection.start) + token.length,
    );
  }

  Future<void> _handlePublish() async {
    final user = FirebaseAuth.instance.currentUser;
    final doctorId = user?.uid ?? 'anonymous';
    final targetList = _filteredAudience;

    if (targetList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible patients found for the selected audience.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _currentStep = 3;
      _isDispatching = true;
      _dispatchProcessed = 0;
      _dispatchTotal = targetList.length;
      _dispatchError = null;
    });

    final channel = (_enableEmail && _enableWhatsApp)
        ? CampaignChannel.both
        : (_enableEmail ? CampaignChannel.email : CampaignChannel.whatsapp);

    final campaign = CampaignModel(
      id: 'camp_${_uuid.v4()}',
      doctorId: doctorId,
      title: _titleController.text.trim(),
      message: _messageController.text.trim(),
      category: _selectedCategory,
      channels: channel,
      audienceType: _selectedAudienceType,
      targetFilters: {
        if (_selectedAudienceType == AudienceType.byDiagnosis)
          'condition': _conditionFilterController.text.trim(),
        if (_selectedAudienceType == AudienceType.byGender)
          'gender': _selectedGender,
        if (_selectedAudienceType == AudienceType.byAgeGroup) ...{
          'minAge': _selectedAgeMin,
          'maxAge': _selectedAgeMax,
        },
      },
      selectedPatientIds: _selectedPatientIds.toList(),
      mediaUrl: _mediaUrlController.text.trim().isNotEmpty
          ? _mediaUrlController.text.trim()
          : null,
      status: CampaignStatus.processing,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      totalRecipients: targetList.length,
    );

    try {
      final result = await _dispatchService.dispatchCampaign(
        campaign: campaign,
        targetPatients: targetList,
        clinicName: _clinicName,
        doctorName: _doctorName,
        onProgress: (processed, total) {
          if (mounted) {
            setState(() {
              _dispatchProcessed = processed;
              _dispatchTotal = total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDispatching = false;
          _dispatchedCampaign = result;
        });
        widget.onCampaignPublished?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDispatching = false;
          _dispatchError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Modal Header with Steps Indicator
            _buildModalHeader(),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Dynamic Step Body
            Expanded(
              child: _isLoadingPatients
                  ? const Center(child: CircularProgressIndicator())
                  : _buildStepBody(),
            ),

            // Modal Footer Buttons
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildModalFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildModalHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Post Patient Campaign & Broadcast',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Send health advisories, checkup camps, and updates via Email & WhatsApp',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          // Step Badges
          Row(
            children: [
              _buildStepIndicator(0, 'Compose'),
              _buildStepSeparator(),
              _buildStepIndicator(1, 'Audience'),
              _buildStepSeparator(),
              _buildStepIndicator(2, 'Preview'),
            ],
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int stepIndex, String title) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? const Color(0xFF10B981)
                : (isActive ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text(
                    '${stepIndex + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildStepSeparator() {
    return Container(
      width: 20,
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0xFFCBD5E1),
    );
  }

  Widget _buildStepBody() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Compose();
      case 1:
        return _buildStep2Audience();
      case 2:
        return _buildStep3Preview();
      case 3:
        return _buildStep4DispatchProgress();
      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // STEP 1: COMPOSE CONTENT
  // ===========================================================================
  Widget _buildStep1Compose() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category selector pills
          const Text(
            'Campaign Category',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CampaignCategory.values.map((category) {
              final isSelected = _selectedCategory == category;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(category.icon, size: 16, color: isSelected ? Colors.white : category.color),
                    const SizedBox(width: 6),
                    Text(category.label),
                  ],
                ),
                selected: isSelected,
                selectedColor: category.color,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
                backgroundColor: const Color(0xFFF1F5F9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected ? category.color : const Color(0xFFE2E8F0),
                  ),
                ),
                onSelected: (_) => setState(() => _selectedCategory = category),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Title
          const Text(
            'Campaign Title / Subject *',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: 'e.g. Free Blood Sugar & Diabetes Screening Camp this Sunday',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),

          const SizedBox(height: 20),

          // Personalization Tags Toolbar
          Row(
            children: [
              const Text(
                'Campaign Message / Body *',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
              ),
              const Spacer(),
              const Text(
                'Insert Tag: ',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
              _buildTagPill('+ Patient Name', '{{patient_name}}'),
              const SizedBox(width: 6),
              _buildTagPill('+ Clinic Name', '{{clinic_name}}'),
              const SizedBox(width: 6),
              _buildTagPill('+ Doctor Name', '{{doctor_name}}'),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            maxLines: 7,
            decoration: InputDecoration(
              hintText: 'Dear {{patient_name}},\n\nWe are pleased to invite you to our comprehensive health checkup camp at {{clinic_name}}...\n\nStay healthy,\n{{doctor_name}}',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),

          const SizedBox(height: 16),

          // Banner Image URL (Optional)
          const Text(
            'Banner Image URL (Optional)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _mediaUrlController,
            decoration: InputDecoration(
              hintText: 'https://example.com/banner.jpg (Included in Email header & WhatsApp media)',
              prefixIcon: const Icon(Icons.image_outlined, size: 20, color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagPill(String label, String token) {
    return InkWell(
      onTap: () => _insertPlaceholder(token),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2563EB),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // STEP 2: AUDIENCE & CHANNELS
  // ===========================================================================
  Widget _buildStep2Audience() {
    final eligibleCount = _filteredAudience.length;
    final emailEligible = _filteredAudience.where((p) => CampaignAudienceHelper.isValidEmail(p.email)).length;
    final waEligible = _filteredAudience.where((p) => WhatsAppTemplateService.isValidWhatsAppPhone(p.phone)).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cohort Selector
          const Text(
            'Target Patient Cohort',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AudienceType.values.map((type) {
              final isSelected = _selectedAudienceType == type;
              return InkWell(
                onTap: () => setState(() => _selectedAudienceType = type),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 16,
                        color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? const Color(0xFF1E40AF) : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Dynamic filter options based on audience type
          if (_selectedAudienceType == AudienceType.byDiagnosis) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filter by Diagnosis / Medical Tag:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _conditionFilterController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'e.g. Diabetes, Hypertension, Asthma, Thyroid',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: ['Diabetes', 'Hypertension', 'Asthma', 'Cardiac', 'Thyroid'].map((cond) {
                      return ActionChip(
                        label: Text(cond),
                        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        onPressed: () {
                          _conditionFilterController.text = cond;
                          setState(() {});
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedAudienceType == AudienceType.byGender) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Text('Select Gender: ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedGender,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Genders')),
                      DropdownMenuItem(value: 'female', child: Text('Female Only')),
                      DropdownMenuItem(value: 'male', child: Text('Male Only')),
                    ],
                    onChanged: (val) => setState(() => _selectedGender = val ?? 'all'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedAudienceType == AudienceType.byAgeGroup) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Age Bracket:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildAgePresetChip('All Ages (0-120)', 0, 120),
                      _buildAgePresetChip('Senior Citizens (60+)', 60, 120),
                      _buildAgePresetChip('Adults (18-59)', 18, 59),
                      _buildAgePresetChip('Children (<18)', 0, 17),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedAudienceType == AudienceType.customSelection) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Select Specific Patients:',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedPatientIds.length == _allPatients.length) {
                              _selectedPatientIds.clear();
                            } else {
                              _selectedPatientIds.addAll(_allPatients.map((p) => p.id));
                            }
                          });
                        },
                        child: Text(
                          _selectedPatientIds.length == _allPatients.length
                              ? 'Deselect All'
                              : 'Select All (${_allPatients.length})',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    onChanged: (q) => setState(() => _patientSearchQuery = q.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search patients by name or phone...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView(
                      shrinkWrap: true,
                      children: _allPatients
                          .where((p) =>
                              _patientSearchQuery.isEmpty ||
                              p.fullName.toLowerCase().contains(_patientSearchQuery) ||
                              p.phone.contains(_patientSearchQuery))
                          .map((patient) {
                        final isChecked = _selectedPatientIds.contains(patient.id);
                        return CheckboxListTile(
                          dense: true,
                          value: isChecked,
                          title: Text(patient.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(
                            '${patient.phone} • ${patient.email.isNotEmpty ? patient.email : "No Email"}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedPatientIds.add(patient.id);
                              } else {
                                _selectedPatientIds.remove(patient.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Recipient Cohort Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups_rounded, color: Color(0xFF16A34A), size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$eligibleCount Patients Targeted',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF14532D),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '📧 $emailEligible with verified Email  •  💬 $waEligible with valid WhatsApp number',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Communication Channels
          const Text(
            'Broadcast Channels *',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  value: _enableEmail,
                  tileColor: _enableEmail ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _enableEmail ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                  ),
                  secondary: const Icon(Icons.email_rounded, color: Color(0xFF2563EB)),
                  title: const Text('Email Notification', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: const Text('Rich HTML email with clinic header', style: TextStyle(fontSize: 11)),
                  onChanged: (val) {
                    if (val == false && !_enableWhatsApp) return;
                    setState(() => _enableEmail = val ?? true);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CheckboxListTile(
                  value: _enableWhatsApp,
                  tileColor: _enableWhatsApp ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _enableWhatsApp ? const Color(0xFF16A34A) : const Color(0xFFE2E8F0)),
                  ),
                  secondary: const Icon(Icons.chat_rounded, color: Color(0xFF16A34A)),
                  title: const Text('WhatsApp Message', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: const Text('Direct mobile chat notification', style: TextStyle(fontSize: 11)),
                  onChanged: (val) {
                    if (val == false && !_enableEmail) return;
                    setState(() => _enableWhatsApp = val ?? true);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgePresetChip(String label, int min, int max) {
    final isSelected = _selectedAgeMin == min && _selectedAgeMax == max;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedAgeMin = min;
          _selectedAgeMax = max;
        });
      },
    );
  }

  // ===========================================================================
  // STEP 3: LIVE PREVIEW & CONFIRMATION
  // ===========================================================================
  Widget _buildStep3Preview() {
    final samplePatient = _filteredAudience.isNotEmpty
        ? _filteredAudience.first
        : Patient(
            id: 'sample',
            firstName: 'Rahul',
            lastName: 'Sharma',
            phone: '+91 98765 43210',
            email: 'rahul.sharma@example.com',
            gender: 'Male',
            dateOfBirth: DateTime(1985, 4, 12),
            diagnosis: ['Diabetes'],
            packageBalance: 0,
            isArchived: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

    final whatsAppText = CampaignAudienceHelper.buildFormattedWhatsAppText(
      _messageController.text.trim().isNotEmpty
          ? _messageController.text.trim()
          : 'Campaign message content here...',
      title: _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : 'Campaign Title',
      patient: samplePatient,
      category: _selectedCategory,
      clinicName: _clinicName,
      doctorName: _doctorName,
    );

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF1F5F9),
            child: const TabBar(
              labelColor: Color(0xFF2563EB),
              unselectedLabelColor: Color(0xFF64748B),
              indicatorColor: Color(0xFF2563EB),
              indicatorWeight: 3,
              tabs: [
                Tab(icon: Icon(Icons.email_outlined, size: 18), text: 'Email Preview'),
                Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'WhatsApp Preview'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 1. Email Preview Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 580),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Email Header
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _clinicName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const Text('Patient Care & Health Advisory', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                  ],
                                ),
                                Chip(
                                  label: Text(_selectedCategory.label.toUpperCase()),
                                  backgroundColor: Colors.white12,
                                  labelStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          // Email Body
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _titleController.text.isNotEmpty ? _titleController.text : 'Campaign Title',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  CampaignAudienceHelper.interpolateVariables(
                                    _messageController.text.isNotEmpty
                                        ? _messageController.text
                                        : 'Dear {{patient_name}},\n\nYour campaign content will appear here.',
                                    patient: samplePatient,
                                    clinicName: _clinicName,
                                    doctorName: _doctorName,
                                  ),
                                  style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border(left: BorderSide(color: _selectedCategory.color, width: 4)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_doctorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text(_clinicName, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Footer
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
                            ),
                            child: Center(
                              child: Text(
                                'Sent to ${samplePatient.fullName} • Official Healthcare Advisory',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. WhatsApp Preview Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5DDD5), // WhatsApp chat background
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // WhatsApp Message Bubble
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCF8C6), // WhatsApp bubble green
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  whatsAppText,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.5,
                                    color: Color(0xFF111B21),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Text('Just now', style: TextStyle(fontSize: 10, color: Color(0xFF667781))),
                                      SizedBox(width: 4),
                                      Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF53BDEB)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STEP 4: DISPATCH PROGRESS & CONFIRMATION
  // ===========================================================================
  Widget _buildStep4DispatchProgress() {
    if (_isDispatching) {
      final percent = _dispatchTotal > 0 ? (_dispatchProcessed / _dispatchTotal) : 0.0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Broadcasting Campaign...',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              Text(
                'Processing $_dispatchProcessed of $_dispatchTotal targeted patients',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_dispatchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 56),
              const SizedBox(height: 16),
              const Text(
                'Dispatch Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
              ),
              const SizedBox(height: 8),
              Text(_dispatchError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => setState(() => _currentStep = 2),
                child: const Text('Back to Review'),
              ),
            ],
          ),
        ),
      );
    }

    // Success confirmation
    final campaign = _dispatchedCampaign;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFDCFCE7),
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 54),
            ),
            const SizedBox(height: 20),
            const Text(
              'Campaign Published Successfully! 🎉',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              'Campaign broadcast dispatched to ${campaign?.totalRecipients ?? _dispatchTotal} eligible patients.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMetricBadge('📧 Emails Sent', '${campaign?.emailsSent ?? 0}', const Color(0xFF2563EB)),
                const SizedBox(width: 16),
                _buildMetricBadge('💬 WhatsApp Sent', '${campaign?.whatsAppSent ?? 0}', const Color(0xFF16A34A)),
              ],
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Done & Return to Dashboard'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBadge(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(width: 8),
          Text(count, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  // ===========================================================================
  // FOOTER BUTTONS
  // ===========================================================================
  Widget _buildModalFooter() {
    if (_currentStep == 3) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Previous'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          const SizedBox(width: 12),
          if (_currentStep < 2)
            ElevatedButton.icon(
              onPressed: () {
                if (_currentStep == 0) {
                  if (_titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a campaign title.')),
                    );
                    return;
                  }
                  if (_messageController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter campaign message body.')),
                    );
                    return;
                  }
                }
                setState(() => _currentStep++);
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Next Step'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _handlePublish,
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Publish & Send Campaign'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }
}
