import 'package:flutter/material.dart';
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

/// Mobile-optimized, touch-friendly Campaign composer modal sheet.
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

      final hasGmail = await _gmailAuthService.restoreSession();
      if (mounted) {
        setState(() {
          _connectedGmail = hasGmail ? _gmailAuthService.connectedEmail : null;
        });
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
    final media = MediaQuery.of(context);
    final height = media.size.height * 0.90;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.divider),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            // Sheet Handle & Header
            _buildHeader(),
            const Divider(height: 1, color: AppColors.divider),

            // Step Body
            Expanded(
              child: _isLoadingPatients
                  ? const Center(child: CircularProgressIndicator())
                  : _buildStepBody(),
            ),

            // Footer Navigation Buttons
            const Divider(height: 1, color: AppColors.divider),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.campaign_rounded, color: Color(0xFF2563EB), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _currentStep == 0
                      ? '1. Compose Campaign'
                      : (_currentStep == 1
                          ? '2. Target Audience'
                          : (_currentStep == 2
                              ? '3. Live Previews'
                              : '4. Broadcasting')),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Campaign Category',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: CampaignCategory.values.map((category) {
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(category.icon, size: 14, color: isSelected ? Colors.white : category.color),
                        const SizedBox(width: 4),
                        Text(category.label, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    selected: isSelected,
                    selectedColor: category.color,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                    backgroundColor: AppColors.inputBackground,
                    onSelected: (_) => setState(() => _selectedCategory = category),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Campaign Title *',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. Free Diabetes Screening Camp',
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              filled: true,
              fillColor: AppColors.inputBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              const Text(
                'Message Body *',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
              const Spacer(),
              _buildTagChip('+ Name', '{{patient_name}}'),
              const SizedBox(width: 4),
              _buildTagChip('+ Clinic', '{{clinic_name}}'),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _messageController,
            maxLines: 5,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Dear {{patient_name}},\n\nWe invite you to our health checkup at {{clinic_name}}...\n\nRegards,\n{{doctor_name}}',
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              filled: true,
              fillColor: AppColors.inputBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Banner Image URL (Optional)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _mediaUrlController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'https://example.com/banner.jpg',
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              prefixIcon: const Icon(Icons.image_outlined, size: 18, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String label, String token) {
    return InkWell(
      onTap: () => _insertPlaceholder(token),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB).withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Target Patient Cohort',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          ...AudienceType.values.map((type) {
            final isSelected = _selectedAudienceType == type;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => setState(() => _selectedAudienceType = type),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2563EB).withOpacity(0.08) : AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF2563EB) : AppColors.divider,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 16,
                        color: isSelected ? const Color(0xFF2563EB) : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? const Color(0xFF2563EB) : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          if (_selectedAudienceType == AudienceType.byDiagnosis) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _conditionFilterController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Condition: Diabetes, Hypertension...',
                hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                filled: true,
                fillColor: AppColors.inputBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Summary Tile
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups_rounded, color: Color(0xFF10B981), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count Patients Targeted',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF10B981)),
                      ),
                      Text(
                        '📧 $emailEligible with Email • 💬 $waEligible with WhatsApp',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'Channels',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _enableEmail,
            title: const Text('Email Notification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
            subtitle: _connectedGmail != null
                ? Text('Sending from: $_connectedGmail', style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)))
                : const Text('Gmail not connected in Profile. Connect in Profile to send live emails.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            onChanged: (v) {
              if (v == false && !_enableWhatsApp) return;
              setState(() => _enableEmail = v);
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _enableWhatsApp,
            title: const Text('WhatsApp Message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
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
          const TabBar(
            labelColor: Color(0xFF2563EB),
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: Color(0xFF2563EB),
            tabs: [
              Tab(text: 'Email Preview'),
              Tab(text: 'WhatsApp Preview'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Email Preview
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_clinicName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                        const SizedBox(height: 8),
                        Text(_titleController.text.isNotEmpty ? _titleController.text : 'Title', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                        const SizedBox(height: 8),
                        Text(
                          CampaignAudienceHelper.interpolateVariables(
                            _messageController.text.isNotEmpty ? _messageController.text : 'Body text...',
                            patient: samplePatient,
                            clinicName: _clinicName,
                            doctorName: _doctorName,
                          ),
                          style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
                        ),
                        const SizedBox(height: 14),
                        Text('Doctor: $_doctorName', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                ),

                // WhatsApp Preview
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCF8C6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      whatsAppText,
                      style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF111B21)),
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
              const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF2563EB))),
              const SizedBox(height: 16),
              const Text('Broadcasting...', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text('$_dispatchProcessed of $_dispatchTotal patients', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: percent, backgroundColor: AppColors.divider, valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981))),
            ],
          ),
        ),
      );
    }

    if (_dispatchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_dispatchError!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => setState(() => _currentStep = 2), child: const Text('Back')),
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
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 54),
            const SizedBox(height: 14),
            const Text('Campaign Published! 🎉', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Dispatched to ${_dispatchedCampaign?.totalRecipients ?? _dispatchTotal} patients.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // FOOTER
  // ===========================================================================
  Widget _buildFooter() {
    if (_currentStep == 3) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: () => setState(() => _currentStep--),
              child: const Text('Back'),
            ),
          const Spacer(),
          if (_currentStep < 2)
            ElevatedButton(
              onPressed: () {
                if (_currentStep == 0 && (_titleController.text.trim().isEmpty || _messageController.text.trim().isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill title and message.')));
                  return;
                }
                setState(() => _currentStep++);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Next'),
            )
          else
            ElevatedButton(
              onPressed: _handlePublish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Publish & Send'),
            ),
        ],
      ),
    );
  }
}
