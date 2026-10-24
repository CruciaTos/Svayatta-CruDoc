import '../templates/doc_template.dart';

String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;
bool _b(Object? v, bool fallback) => v is bool ? v : fallback;
int _i(Object? v, int fallback) => v is num ? v.toInt() : fallback;

Map<String, String> _mapSS(Object? v) {
  if (v is! Map) return const {};
  return {
    for (final e in v.entries)
      if (e.key is String && e.value is String)
        e.key as String: e.value as String,
  };
}

class ClinicDocSettings {
  const ClinicDocSettings({
    this.name = '',
    this.tagline = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.timings = '',
    this.regNo = '',
    this.gstin = '',
    this.footerText = '',
    this.termsText = '',
    this.upiId = '',
    this.upiName = '',
    this.logoPath = '',
    this.logoSha = '',
    this.clinicStampPath = '',
    this.clinicStampSha = '',
    this.gstEnabled = false,
    this.roundOff = true,
    this.lockTemplates = false,
    this.prefixes = const {},
    this.defaults = const {},
    this.updatedAt = 0,
  });

  final String name;
  final String tagline;
  final String address;
  final String phone;
  final String email;
  final String website;
  final String timings;
  final String regNo;
  final String gstin;
  final String footerText;
  final String termsText;
  final String upiId;
  final String upiName;
  final String logoPath;
  final String logoSha;
  final String clinicStampPath;
  final String clinicStampSha;
  final bool gstEnabled;
  final bool roundOff;
  final bool lockTemplates;
  final Map<String, String> prefixes;
  final Map<String, String> defaults;
  final int updatedAt;

  String prefixFor(DocKind k) {
    final p = prefixes[k.name]?.trim() ?? '';
    if (RegExp(r'^[A-Za-z0-9]{1,5}$').hasMatch(p)) return p;
    return k.defaultPrefix;
  }

  ClinicDocSettings copyWith({
    String? name,
    String? tagline,
    String? address,
    String? phone,
    String? email,
    String? website,
    String? timings,
    String? regNo,
    String? gstin,
    String? footerText,
    String? termsText,
    String? upiId,
    String? upiName,
    String? logoPath,
    String? logoSha,
    String? clinicStampPath,
    String? clinicStampSha,
    bool? gstEnabled,
    bool? roundOff,
    bool? lockTemplates,
    Map<String, String>? prefixes,
    Map<String, String>? defaults,
    int? updatedAt,
  }) => ClinicDocSettings(
    name: name ?? this.name,
    tagline: tagline ?? this.tagline,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    website: website ?? this.website,
    timings: timings ?? this.timings,
    regNo: regNo ?? this.regNo,
    gstin: gstin ?? this.gstin,
    footerText: footerText ?? this.footerText,
    termsText: termsText ?? this.termsText,
    upiId: upiId ?? this.upiId,
    upiName: upiName ?? this.upiName,
    logoPath: logoPath ?? this.logoPath,
    logoSha: logoSha ?? this.logoSha,
    clinicStampPath: clinicStampPath ?? this.clinicStampPath,
    clinicStampSha: clinicStampSha ?? this.clinicStampSha,
    gstEnabled: gstEnabled ?? this.gstEnabled,
    roundOff: roundOff ?? this.roundOff,
    lockTemplates: lockTemplates ?? this.lockTemplates,
    prefixes: prefixes ?? this.prefixes,
    defaults: defaults ?? this.defaults,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'tagline': tagline,
    'address': address,
    'phone': phone,
    'email': email,
    'website': website,
    'timings': timings,
    'regNo': regNo,
    'gstin': gstin,
    'footerText': footerText,
    'termsText': termsText,
    'upiId': upiId,
    'upiName': upiName,
    'logoPath': logoPath,
    'logoSha': logoSha,
    'clinicStampPath': clinicStampPath,
    'clinicStampSha': clinicStampSha,
    'gstEnabled': gstEnabled,
    'roundOff': roundOff,
    'lockTemplates': lockTemplates,
    'prefixes': prefixes,
    'defaults': defaults,
    'updatedAt': updatedAt,
  };

  static ClinicDocSettings fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ClinicDocSettings();
    return ClinicDocSettings(
      name: _s(m['name']),
      tagline: _s(m['tagline']),
      address: _s(m['address']),
      phone: _s(m['phone']),
      email: _s(m['email']),
      website: _s(m['website']),
      timings: _s(m['timings']),
      regNo: _s(m['regNo']),
      gstin: _s(m['gstin']),
      footerText: _s(m['footerText']),
      termsText: _s(m['termsText']),
      upiId: _s(m['upiId']),
      upiName: _s(m['upiName']),
      logoPath: _s(m['logoPath']),
      logoSha: _s(m['logoSha']),
      clinicStampPath: _s(m['clinicStampPath']),
      clinicStampSha: _s(m['clinicStampSha']),
      gstEnabled: _b(m['gstEnabled'], false),
      roundOff: _b(m['roundOff'], true),
      lockTemplates: _b(m['lockTemplates'], false),
      prefixes: _mapSS(m['prefixes']),
      defaults: _mapSS(m['defaults']),
      updatedAt: _i(m['updatedAt'], 0),
    );
  }
}

class DoctorDocProfile {
  const DoctorDocProfile({
    required this.uid,
    this.nameOnDocs = '',
    this.qualification = '',
    this.specialty = '',
    this.regNo = '',
    this.regCouncil = '',
    this.phone = '',
    this.email = '',
    this.signaturePath = '',
    this.signatureSha = '',
    this.stampPath = '',
    this.stampSha = '',
    this.consultFeePaise = 0,
    this.defaults = const {},
    this.updatedAt = 0,
  });

  final String uid;
  final String nameOnDocs;
  final String qualification;
  final String specialty;
  final String regNo;
  final String regCouncil;
  final String phone;
  final String email;
  final String signaturePath;
  final String signatureSha;
  final String stampPath;
  final String stampSha;
  final int consultFeePaise;
  final Map<String, String> defaults;
  final int updatedAt;

  DoctorDocProfile copyWith({
    String? uid,
    String? nameOnDocs,
    String? qualification,
    String? specialty,
    String? regNo,
    String? regCouncil,
    String? phone,
    String? email,
    String? signaturePath,
    String? signatureSha,
    String? stampPath,
    String? stampSha,
    int? consultFeePaise,
    Map<String, String>? defaults,
    int? updatedAt,
  }) => DoctorDocProfile(
    uid: uid ?? this.uid,
    nameOnDocs: nameOnDocs ?? this.nameOnDocs,
    qualification: qualification ?? this.qualification,
    specialty: specialty ?? this.specialty,
    regNo: regNo ?? this.regNo,
    regCouncil: regCouncil ?? this.regCouncil,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    signaturePath: signaturePath ?? this.signaturePath,
    signatureSha: signatureSha ?? this.signatureSha,
    stampPath: stampPath ?? this.stampPath,
    stampSha: stampSha ?? this.stampSha,
    consultFeePaise: consultFeePaise ?? this.consultFeePaise,
    defaults: defaults ?? this.defaults,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'nameOnDocs': nameOnDocs,
    'qualification': qualification,
    'specialty': specialty,
    'regNo': regNo,
    'regCouncil': regCouncil,
    'phone': phone,
    'email': email,
    'signaturePath': signaturePath,
    'signatureSha': signatureSha,
    'stampPath': stampPath,
    'stampSha': stampSha,
    'consultFeePaise': consultFeePaise,
    'defaults': defaults,
    'updatedAt': updatedAt,
  };

  static DoctorDocProfile fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DoctorDocProfile(uid: '');
    return DoctorDocProfile(
      uid: _s(m['uid']),
      nameOnDocs: _s(m['nameOnDocs']),
      qualification: _s(m['qualification']),
      specialty: _s(m['specialty']),
      regNo: _s(m['regNo']),
      regCouncil: _s(m['regCouncil']),
      phone: _s(m['phone']),
      email: _s(m['email']),
      signaturePath: _s(m['signaturePath']),
      signatureSha: _s(m['signatureSha']),
      stampPath: _s(m['stampPath']),
      stampSha: _s(m['stampSha']),
      consultFeePaise: _i(m['consultFeePaise'], 0),
      defaults: _mapSS(m['defaults']),
      updatedAt: _i(m['updatedAt'], 0),
    );
  }
}
