import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_form.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';

/// Screen that lets the doctor add a new patient.
///
/// Owns the [PatientRepository] instance, the submit button, and the
/// loading/error state. The actual input fields live in [PatientForm].
class AddPatientPage extends StatefulWidget {
  const AddPatientPage({super.key, PatientRepository? repository})
      : _repository = repository;

  final PatientRepository? _repository;

  @override
  State<AddPatientPage> createState() => _AddPatientPageState();
}

class _AddPatientPageState extends State<AddPatientPage> {
  final _formKey = GlobalKey<FormState>();
  final _formStateKey = GlobalKey<PatientFormState>();

  late final PatientRepository _repository =
      widget._repository ?? PatientRepository();

  bool _isSaving = false;

  Future<void> _handleSubmit(PatientFormResult result) async {
    setState(() => _isSaving = true);

    final now = DateTime.now();
    final patient = Patient(
      id: '', // Firestore assigns the id on create.
      firstName: result.firstName,
      lastName: result.lastName,
      phone: result.phone,
      gender: result.gender,
      dateOfBirth: result.dateOfBirth,
      diagnosis: result.diagnosis,
      packageBalance: result.packageBalance,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _repository.createPatient(patient);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient added successfully')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save patient: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onSavePressed() {
    _formStateKey.currentState?.submit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              children: [
                const _TopBar(),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: PatientForm(
                      key: _formStateKey,
                      formKey: _formKey,
                      onSubmit: _handleSubmit,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _onSavePressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.slateBlue,
                      disabledBackgroundColor:
                          AppColors.slateBlue.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.textPrimary,
                            ),
                          )
                        : const Text(
                            'Save Patient',
                            style: TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Top Bar ----------
// Lives inside the ShellBackground-wrapped body (rather than Scaffold's
// appBar slot) so the gradient shows behind it instead of a solid bar.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 10),
        const Text(
          'Add Patient',
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}