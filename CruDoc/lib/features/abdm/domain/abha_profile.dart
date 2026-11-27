/// Profile returned by ABDM after verification or enrollment.
class AbhaProfile {
  const AbhaProfile({
    required this.abhaNumber,
    required this.abhaAddress,
    required this.name,
    required this.gender,
    required this.dateOfBirth,
    required this.mobile,
    required this.kycVerified,
  });

  final String abhaNumber;
  final String abhaAddress;
  final String name;
  final String gender;
  final DateTime? dateOfBirth;
  final String mobile;
  final bool kycVerified;

  factory AbhaProfile.fromMap(Map<String, dynamic> map) {
    final dobStr = map['dateOfBirth'] as String?;
    DateTime? dob;
    if (dobStr != null && dobStr.isNotEmpty) {
      dob = DateTime.tryParse(dobStr);
    }
    return AbhaProfile(
      abhaNumber: (map['abhaNumber'] as String? ?? '').trim(),
      abhaAddress: (map['abhaAddress'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      gender: (map['gender'] as String? ?? '').trim(),
      dateOfBirth: dob,
      mobile: (map['mobile'] as String? ?? '').trim(),
      kycVerified: map['kycVerified'] as bool? ?? false,
    );
  }
}

/// An ABHA account summary returned by mobile search.
class AbhaSearchAccount {
  const AbhaSearchAccount({
    required this.index,
    required this.name,
    required this.gender,
    required this.abhaNumberMasked,
  });

  final String index;
  final String name;
  final String gender;
  final String abhaNumberMasked;

  factory AbhaSearchAccount.fromMap(Map<String, dynamic> map) {
    return AbhaSearchAccount(
      index: '${map['index'] ?? ''}',
      name: (map['name'] as String? ?? '').trim(),
      gender: (map['gender'] as String? ?? '').trim(),
      abhaNumberMasked: (map['abhaNumberMasked'] as String? ?? '').trim(),
    );
  }
}

/// Result of searching an ABHA address.
class AbhaAddressSearchResult {
  const AbhaAddressSearchResult({
    required this.flowId,
    required this.methods,
    required this.name,
    required this.mobileMasked,
  });

  final String flowId;
  final List<String> methods;
  final String name;
  final String mobileMasked;
}

/// Result of OTP verification.
class AbhaVerifyResult {
  const AbhaVerifyResult({
    required this.profile,
    this.isNew = false,
    this.needsMobileOtp = false,
    this.existingPatientId,
  });

  final AbhaProfile profile;
  final bool isNew;
  final bool needsMobileOtp;
  final String? existingPatientId;
}

/// Downloaded ABHA card bytes.
class AbhaCardData {
  const AbhaCardData({required this.contentType, required this.base64});

  final String contentType;
  final String base64;
}
