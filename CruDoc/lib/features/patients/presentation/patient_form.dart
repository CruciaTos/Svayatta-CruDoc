import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _conditionController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactController = TextEditingController();
  final _secondContactController = TextEditingController();
  final _noteController = TextEditingController();
  String _gender = 'Female'; // default

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _conditionController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    _secondContactController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    // Collect data (for now, just print or show snackbar)
    final patientData = {
      'name': _nameController.text.trim(),
      'age': int.parse(_ageController.text.trim()),
      'gender': _gender,
      'condition': _conditionController.text.trim(),
      'address': _addressController.text.trim(),
      'contact': _contactController.text.trim(),
      'secondContact': _secondContactController.text.trim(),
      'note': _noteController.text.trim(),
    };

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Patient added successfully!')),
    );
    Navigator.pop(context); // go back to patient list
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2C3E50),
              Color(0xFFAED6F1),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: AppColors.textPrimary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Add New Patient',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTextField('Full Name *', _nameController),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildTextField(
                                'Age *',
                                _ageController,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: _buildGenderDropdown(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField('Condition *', _conditionController),
                        const SizedBox(height: 16),
                        _buildTextField('Address *', _addressController,
                            maxLines: 2),
                        const SizedBox(height: 16),
                        _buildTextField(
                            'Primary Contact *', _contactController,
                            keyboardType: TextInputType.phone),
                        const SizedBox(height: 16),
                        _buildTextField(
                            'Secondary Contact', _secondContactController,
                            keyboardType: TextInputType.phone),
                        const SizedBox(height: 16),
                        _buildTextField(
                            'Doctor\'s Note (private)', _noteController,
                            maxLines: 3, required: false),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.slateBlue,
                            foregroundColor: AppColors.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Save Patient',
                              style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text,
      int maxLines = 1,
      bool required = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        filled: true,
        fillColor: AppColors.cardSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.slateBlue, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: required
          ? (value) =>
              (value == null || value.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  Widget _buildGenderDropdown() {
    return DropdownButtonFormField<String>(
      value: _gender,
      dropdownColor: AppColors.cardSurface,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: 'Gender',
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        filled: true,
        fillColor: AppColors.cardSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'Female', child: Text('Female')),
        DropdownMenuItem(value: 'Male', child: Text('Male')),
        DropdownMenuItem(value: 'Other', child: Text('Other')),
      ],
      onChanged: (val) => setState(() => _gender = val!),
    );
  }
}