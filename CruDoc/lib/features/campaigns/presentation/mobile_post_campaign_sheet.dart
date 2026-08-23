import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_auth_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import '../data/models/campaign_model.dart';
import '../data/models/campaign_enums.dart';
import '../data/services/campaign_audience_helper.dart';
import '../data/services/campaign_dispatch_service.dart';

/// Touch-friendly, CruDoc-themed Campaign composer bottom sheet modal.
class MobilePostCampaignSheet extends StatefulWidget {
  const MobilePostCampaignSheet({
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
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MobilePostCampaignSheet(
        initialCategory: initialCategory,
        onCampaignPublished: onCampaignPublished,
      ),
    );
  }

  @override
  State<MobilePostCampaignSheet> createState() => _MobilePostCampaignSheetState();
}

class _MobilePostCampaignSheetState extends State<MobilePostCampaignSheet> {
  static const _uuid = Uuid();
  final PatientRepository _patientRepository = PatientRepository();
  final CampaignDispatchService _dispatchService = CampaignDispatchService();
  final GmailAuthService _gmailAuthService = GmailAuthService();

  int _currentStep = 0; // 0: Compose, 1: Audience, 2: Preview, 3: Dispatching

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

  // Doctor / Clinic / Gmail Info
  String _doctorName = 'Dr. Specialist';
  String _clinicName = 'CruDoc Healthcare';
  String? _connectedGmail;

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
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final profile = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final data = profile.data();
        final docName = DoctorProfileHelper.formatDoctorName(user, data);
        final clName = DoctorProfileHelper.formatClinicName(user, data);
        await _gmailAuthService.restoreSession();
        final gmail = _gmailAuthService.connectedEmail;
        if (mounted) {
          setState(() {
            _doctorName = docName.isNotEmpty ? docName : 'Dr. Specialist';
            _clinicName = clName.isNotEmpty ? clName : 'CruDoc Healthcare';
            _connectedGmail = gmail;
          });
        }
      } catch (_) {}
    }

    try {
      final patients = await _patientRepository.watchPatients().first;
      if (mounted) {
        setState(() {
          _allPatients = patients;
          _isLoadingPatients = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPatients = false);
    }
  }

  List<Patient> get _filteredAudience {
    return CampaignAudienceHelper.filterPatients(
      allPatients: _allPatients,
      audienceType: _selectedAudienceType,
      filters: {
        'condition': _conditionFilterController.text.trim(),
        'gender': _selectedGender,
        'minAge': _selectedAgeMin,
        'maxAge': _selectedAgeMax,
      },
      selectedPatientIds: _selectedPatientIds.toList(),
    );
  }

  void _insertPlaceholder(String token) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, token);
      _messageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + token.length),
      );
    } else {
      _messageController.text = '$text $token';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.silver.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),

          // Header
          _buildSheetHeader(),
          const Divider(height: 1, color: AppColors.divider),

          // Body Step
          Expanded(
            child: _isLoadingPatients
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.chartBarLight),
                  )
                : _buildStepBody(),
          ),

          // Footer Actions
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildSheetHeader() {
    final stepTitles = ['1. Compose Message', '2. Target Audience', '3. Live Previews', '4. Broadcasting'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.chartBarLight.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.campaign_rounded, color: AppColors.chartBarLight, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stepTitles[_currentStep.clamp(0, 3)],
                      style: const TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Step ${_currentStep + 1} of 4',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress Step Indicators
          Row(
            children: List.generate(4, (index) {
              final isDone = index < _currentStep;
              final isCurrent = index == _currentStep;
              return Expanded(
                child: Container(
                  height: 3.5,
                  margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: isDone || isCurrent
                        ? AppColors.chartBarLight
                        : AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
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
        return _buildStep4Dispatch();
      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // STEP 1: COMPOSE
  // ===========================================================================
  Widget _buildStep1Compose() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Campaign Category',
            style: TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: CampaignCategory.values.map((category) {
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCategory = category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected ? category.color : category.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? category.color : category.color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(category.icon, size: 14, color: isSelected ? Colors.white : category.color),
                          const SizedBox(width: 5),
                          Text(
                            category.label,
                            style: TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : category.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          const Text(
            'Campaign Title *',
            style: TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            style: AppColors.bodyMedium,
            decoration: InputDecoration(
              hintText: 'e.g. Free Diabetes Screening & Checkup Camp',
              hintStyle: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.chartBarLight, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              const Text(
                'Message Body *',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _buildTagChip('+ Patient', '{{patient_name}}'),
              const SizedBox(width: 5),
              _buildTagChip('+ Clinic', '{{clinic_name}}'),
              const SizedBox(width: 5),
              _buildTagChip('+ Doctor', '{{doctor_name}}'),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _messageController,
            maxLines: 5,
            style: AppColors.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Dear {{patient_name}},\n\nWe are hosting a free health checkup camp at {{clinic_name}} this Sunday.\n\nBest regards,\n{{doctor_name}}',
              hintStyle: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.chartBarLight, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 18),

          const Text(
            'Banner Image URL (Optional)',
            style: TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _mediaUrlController,
            style: AppColors.bodyMedium,
            decoration: InputDecoration(
              hintText: 'https://example.com/clinic-camp.jpg',
              hintStyle: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.image_outlined, size: 20, color: AppColors.slateBlue),
              filled: true,
              fillColor: AppColors.inputBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.chartBarLight, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String label, String token) {
    return InkWell(
      onTap: () => _insertPlaceholder(token),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: AppColors.chartBarLight.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.chartBarLight,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // STEP 2: AUDIENCE & CHANNELS
  // ===========================================================================
  Widget _buildStep2Audience() {
    final count = _filteredAudience.length;
    final emailEligible = _filteredAudience.where((p) => CampaignAudienceHelper.isValidEmail(p.email)).length;
    final waEligible = _filteredAudience.where((p) => WhatsAppTemplateService.isValidWhatsAppPhone(p.phone)).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Target Patient Cohort',
            style: TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...AudienceType.values.map((type) {
            final isSelected = _selectedAudienceType == type;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedAudienceType = type),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.chartBarLight.withValues(alpha: 0.08) : AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.chartBarLight : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18,
                        color: isSelected ? AppColors.chartBarLight : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 13.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppColors.chartBarLight : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          if (_selectedAudienceType == AudienceType.byDiagnosis) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _conditionFilterController,
              onChanged: (_) => setState(() {}),
              style: AppColors.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Condition filter: Diabetes, Hypertension...',
                hintStyle: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.inputBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Audience Summary Badge Tile
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.positiveGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.positiveGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups_rounded, color: AppColors.positiveGreen, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count Patients Targeted',
                        style: const TextStyle(
                          fontFamily: AppColors.headingFontFamily,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.positiveGreen,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '📧 $emailEligible with Email • 💬 $waEligible with WhatsApp',
                        style: const TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'Broadcast Channels',
            style: TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            dense: true,
            activeColor: AppColors.chartBarLight,
            contentPadding: EdgeInsets.zero,
            value: _enableEmail,
            title: const Text(
              'Email Broadcast',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: _connectedGmail != null
                ? Text('Sending from: $_connectedGmail', style: const TextStyle(fontSize: 11, color: AppColors.positiveGreen))
                : const Text('Connect Gmail in Profile to send live emails.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            onChanged: (v) {
              if (v == false && !_enableWhatsApp) return;
              setState(() => _enableEmail = v);
            },
          ),
          SwitchListTile(
            dense: true,
            activeColor: const Color(0xFF10B981),
            contentPadding: EdgeInsets.zero,
            value: _enableWhatsApp,
            title: const Text(
              'WhatsApp Broadcast',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: const Text('Delivers automatically via WhatsApp Business Cloud API.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            onChanged: (v) {
              if (v == false && !_enableEmail) return;
              setState(() => _enableWhatsApp = v);
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STEP 3: PREVIEW
  // ===========================================================================
  Widget _buildStep3Preview() {
    final samplePatient = _filteredAudience.isNotEmpty
        ? _filteredAudience.first
        : Patient(
            id: 'sample',
            firstName: 'Rahul',
            lastName: 'Sharma',
            phone: '+919876543210',
            email: 'rahul@example.com',
            gender: 'Male',
            dateOfBirth: DateTime(1985, 4, 12),
            diagnosis: const [],
            packageBalance: 0,
            isArchived: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

    final whatsAppText = CampaignAudienceHelper.buildFormattedWhatsAppText(
      _messageController.text.trim().isNotEmpty ? _messageController.text.trim() : 'Campaign message content',
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
          TabBar(
            labelColor: AppColors.chartBarLight,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.chartBarLight,
            labelStyle: const TextStyle(fontFamily: AppColors.bodyFontFamily, fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontFamily: AppColors.bodyFontFamily, fontWeight: FontWeight.w500, fontSize: 13),
            tabs: const [
              Tab(text: '📧 Email Preview'),
              Tab(text: '💬 WhatsApp Preview'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Email Preview Card
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.chartBarLight.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.local_hospital_rounded, size: 16, color: AppColors.chartBarLight),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _clinicName,
                              style: const TextStyle(
                                fontFamily: AppColors.headingFontFamily,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _titleController.text.isNotEmpty ? _titleController.text : 'Campaign Title',
                          style: const TextStyle(
                            fontFamily: AppColors.headingFontFamily,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          CampaignAudienceHelper.interpolateVariables(
                            _messageController.text.isNotEmpty ? _messageController.text : 'Dear {{patient_name}}, message body here...',
                            patient: samplePatient,
                            clinicName: _clinicName,
                            doctorName: _doctorName,
                          ),
                          style: const TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontSize: 13,
                            height: 1.5,
                            color: AppColors.charcoalGray,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: AppColors.divider),
                        const SizedBox(height: 10),
                        Text(
                          'Warm regards,\n$_doctorName • $_clinicName',
                          style: const TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // WhatsApp Preview Bubble
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCF8C6),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      whatsAppText,
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF111B21),
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
  // STEP 4: DISPATCH
  // ===========================================================================
  Widget _buildStep4Dispatch() {
    if (_isDispatching) {
      final percent = _dispatchTotal > 0 ? (_dispatchProcessed / _dispatchTotal) : 0.0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.chartBarLight),
              const SizedBox(height: 20),
              const Text(
                'Broadcasting Campaign...',
                style: TextStyle(
                  fontFamily: AppColors.headingFontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Processed $_dispatchProcessed of $_dispatchTotal patients',
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 6,
                  backgroundColor: AppColors.inputBackground,
                  valueColor: const AlwaysStoppedAnimation(AppColors.positiveGreen),
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
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
              const SizedBox(height: 14),
              Text(
                _dispatchError!,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: Colors.red,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => setState(() => _currentStep = 2),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.chartBarLight,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back to Review'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.positiveGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.positiveGreen, size: 52),
            ),
            const SizedBox(height: 16),
            const Text(
              'Campaign Published! 🎉',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Dispatched to ${_dispatchedCampaign?.totalRecipients ?? _dispatchTotal} patients.',
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                widget.onCampaignPublished?.call();
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.chartBarLight,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontFamily: AppColors.bodyFontFamily, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // FOOTER ACTIONS
  // ===========================================================================
  Widget _buildFooter() {
    if (_currentStep == 3) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Row(
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: () => setState(() => _currentStep--),
              child: const Text(
                'Back',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.slateBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
          if (_currentStep < 2)
            FilledButton(
              onPressed: () {
                if (_currentStep == 0 &&
                    (_titleController.text.trim().isEmpty || _messageController.text.trim().isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill out the campaign title and message.')),
                  );
                  return;
                }
                setState(() => _currentStep++);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.chartBarLight,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Next Step',
                style: TextStyle(fontFamily: AppColors.bodyFontFamily, fontWeight: FontWeight.w600),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _handlePublish,
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text(
                'Publish & Send',
                style: TextStyle(fontFamily: AppColors.bodyFontFamily, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handlePublish() async {
    final audience = _filteredAudience;
    if (audience.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target audience is empty. Please choose eligible patients.')),
      );
      return;
    }

    final doctorId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final campaignId = _uuid.v4();

    final CampaignChannel channel;
    if (_enableEmail && _enableWhatsApp) {
      channel = CampaignChannel.both;
    } else if (_enableEmail) {
      channel = CampaignChannel.email;
    } else {
      channel = CampaignChannel.whatsapp;
    }

    final campaign = CampaignModel(
      id: campaignId,
      doctorId: doctorId,
      title: _titleController.text.trim(),
      message: _messageController.text.trim(),
      category: _selectedCategory,
      channels: channel,
      audienceType: _selectedAudienceType,
      totalRecipients: audience.length,
      mediaUrl: _mediaUrlController.text.trim().isNotEmpty ? _mediaUrlController.text.trim() : null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    setState(() {
      _currentStep = 3;
      _isDispatching = true;
      _dispatchTotal = audience.length;
      _dispatchProcessed = 0;
      _dispatchError = null;
    });

    try {
      final finished = await _dispatchService.dispatchCampaign(
        campaign: campaign,
        targetPatients: audience,
        doctorName: _doctorName,
        clinicName: _clinicName,
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
          _dispatchedCampaign = finished;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDispatching = false;
          _dispatchError = 'Failed to broadcast campaign: $e';
        });
      }
    }
  }
}
