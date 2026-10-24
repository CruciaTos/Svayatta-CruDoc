import 'package:pdf/pdf.dart';

import 'doc_body_sections.dart';

/// Bump when the stored shape changes in a way older apps can't read.
const int kDocSchemaVersion = 1;

enum DocKind {
  invoice('Invoice', 'INV'),
  prescription('Prescription', 'RX'),
  referral('Referral letter', 'REF'),
  report('Medical report', 'REP'),
  certificate('Medical certificate', 'CERT');

  const DocKind(this.label, this.defaultPrefix);
  final String label;
  final String defaultPrefix;
}

enum DocZone { header, footer }

enum DocBlockType { field, text, image, line, box, qr, doctorList }

enum DocImageRole { logo, signature, stamp, clinicStamp, custom }

enum DocShowOn { all, first, last, notFirst }

enum DocAlign { left, center, right }

enum DocScope { builtin, clinic, doctor }

enum InvoiceSignature { doctor, clinicStamp, line, none }

enum DocPaperFormat {
  a4('A4', 210, 297),
  a5('A5', 148, 210),
  letter('Letter', 215.9, 279.4),
  roll80('Receipt roll 80 mm', 80, 0),
  custom('Custom', 0, 0);

  const DocPaperFormat(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm;
  final double heightMm;
}

T docEnum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

DocKind? docKindOrNull(Object? name) {
  for (final k in DocKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

double _d(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;
bool _b(Object? v, bool fallback) => v is bool ? v : fallback;
int _i(Object? v, int fallback) => v is num ? v.toInt() : fallback;

class DocMargins {
  const DocMargins(this.left, this.top, this.right, this.bottom);
  const DocMargins.all(double v) : this(v, v, v, v);

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, dynamic> toMap() => {
    'l': left,
    't': top,
    'r': right,
    'b': bottom,
  };

  static DocMargins fromMap(Object? m) {
    if (m is! Map) return const DocMargins.all(12);
    return DocMargins(
      _d(m['l'], 12),
      _d(m['t'], 12),
      _d(m['r'], 12),
      _d(m['b'], 12),
    );
  }
}

class DocPaper {
  const DocPaper({
    this.format = DocPaperFormat.a4,
    this.widthMm = 210,
    this.heightMm = 297,
    this.margins = const DocMargins.all(12),
  });

  final DocPaperFormat format;
  final double widthMm;

  /// 0 for a receipt roll: the page is as long as its content.
  final double heightMm;
  final DocMargins margins;

  bool get isRoll => format == DocPaperFormat.roll80;
  double get contentWidthMm => widthMm - margins.left - margins.right;
  double get contentHeightMm => heightMm - margins.top - margins.bottom;

  PdfPageFormat toPdf() {
    const mm = PdfPageFormat.mm;
    return PdfPageFormat(
      widthMm * mm,
      isRoll ? double.infinity : heightMm * mm,
      marginLeft: margins.left * mm,
      marginTop: margins.top * mm,
      marginRight: margins.right * mm,
      marginBottom: margins.bottom * mm,
    );
  }

  DocPaper copyWith({
    DocPaperFormat? format,
    double? widthMm,
    double? heightMm,
    DocMargins? margins,
  }) => DocPaper(
    format: format ?? this.format,
    widthMm: widthMm ?? this.widthMm,
    heightMm: heightMm ?? this.heightMm,
    margins: margins ?? this.margins,
  );

  Map<String, dynamic> toMap() => {
    'format': format.name,
    'w': widthMm,
    'h': heightMm,
    'margins': margins.toMap(),
  };

  static DocPaper fromMap(Object? m) {
    if (m is! Map) return const DocPaper();
    return DocPaper(
      format: docEnum(DocPaperFormat.values, m['format'], DocPaperFormat.a4),
      widthMm: _d(m['w'], 210),
      heightMm: _d(m['h'], 297),
      margins: DocMargins.fromMap(m['margins']),
    );
  }
}

class DocStyle {
  const DocStyle({
    this.accent = 0xFF0D9488,
    this.text = 0xFF0F172A,
    this.muted = 0xFF64748B,
    this.border = 0xFFE2E8F0,
    this.soft = 0xFFF8FAFC,
    this.fontScale = 1.0,
  });

  final int accent;
  final int text;
  final int muted;
  final int border;
  final int soft;

  /// Multiplies body text sizes (0.85–1.2).
  final double fontScale;

  /// A colour token ('text', 'muted', 'accent', 'border', 'soft', 'white',
  /// 'none') or '#RRGGBB' → ARGB. 'none' returns 0 (transparent).
  int resolve(String? ref) => switch (ref) {
    null || '' || 'text' => text,
    'accent' => accent,
    'muted' => muted,
    'border' => border,
    'soft' => soft,
    'white' => 0xFFFFFFFF,
    'none' => 0x00000000,
    final String hex => _hex(hex) ?? text,
  };

  static int? _hex(String s) {
    final h = s.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return h.length == 6 ? (0xFF000000 | v) : v;
  }

  DocStyle copyWith({
    int? accent,
    int? text,
    int? muted,
    int? border,
    int? soft,
    double? fontScale,
  }) => DocStyle(
    accent: accent ?? this.accent,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    soft: soft ?? this.soft,
    fontScale: fontScale ?? this.fontScale,
  );

  Map<String, dynamic> toMap() => {
    'accent': accent,
    'text': text,
    'muted': muted,
    'border': border,
    'soft': soft,
    'fontScale': fontScale,
  };

  static DocStyle fromMap(Object? m) {
    if (m is! Map) return const DocStyle();
    return DocStyle(
      accent: _i(m['accent'], 0xFF0D9488),
      text: _i(m['text'], 0xFF0F172A),
      muted: _i(m['muted'], 0xFF64748B),
      border: _i(m['border'], 0xFFE2E8F0),
      soft: _i(m['soft'], 0xFFF8FAFC),
      fontScale: _d(m['fontScale'], 1.0).clamp(0.85, 1.2).toDouble(),
    );
  }
}

/// A picture of the doctor's own printed letterhead, behind the page.
class DocBackground {
  const DocBackground({
    required this.path,
    required this.sha,
    this.printOnPaper = false,
    this.opacity = 1,
  });

  final String path;
  final String sha;

  /// False for pre-printed letterhead paper: shared PDFs show the
  /// letterhead, printed pages leave it out.
  final bool printOnPaper;
  final double opacity;

  DocBackground copyWith({
    String? path,
    String? sha,
    bool? printOnPaper,
    double? opacity,
  }) => DocBackground(
    path: path ?? this.path,
    sha: sha ?? this.sha,
    printOnPaper: printOnPaper ?? this.printOnPaper,
    opacity: opacity ?? this.opacity,
  );

  Map<String, dynamic> toMap() => {
    'path': path,
    'sha': sha,
    'printOnPaper': printOnPaper,
    'opacity': opacity,
  };

  static DocBackground? fromMap(Object? m) {
    if (m is! Map || _s(m['path']).isEmpty) return null;
    return DocBackground(
      path: _s(m['path']),
      sha: _s(m['sha']),
      printOnPaper: _b(m['printOnPaper'], false),
      opacity: _d(m['opacity'], 1),
    );
  }
}

/// One element in the header or footer zone.
class DocBlock {
  const DocBlock({
    required this.id,
    required this.type,
    this.zone = DocZone.header,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.field = '',
    this.text = '',
    this.imageRole = DocImageRole.custom,
    this.imagePath = '',
    this.imageSha = '',
    this.qr = '',
    this.fontPt = 10,
    this.bold = false,
    this.align = DocAlign.left,
    this.color = 'text',
    this.fill = 'none',
    this.strokePt = 0,
    this.radiusMm = 0,
    this.opacity = 1,
    this.showOn = DocShowOn.all,
    this.locked = false,
    this.hidden = false,
    this.onlyWithLogo = false,
    this.noLogoDx = 0,
    this.noLogoDy = 0,
  });

  final String id;
  final DocBlockType type;
  final DocZone zone;

  /// Millimetres from the zone's top-left corner.
  final double x;
  final double y;
  final double w;
  final double h;

  /// type field: a key from `docFields`.
  final String field;

  /// type text: may contain {{field.key}} placeholders.
  final String text;

  /// type image.
  final DocImageRole imageRole;
  final String imagePath;
  final String imageSha;

  /// type qr: 'upi' (pay the balance) or text with placeholders.
  final String qr;

  final double fontPt;
  final bool bold;
  final DocAlign align;

  /// Text, line and border colour (token or '#RRGGBB').
  final String color;

  /// Box fill (token, '#RRGGBB' or 'none').
  final String fill;

  /// Line thickness / box border, in points.
  final double strokePt;
  final double radiusMm;
  final double opacity;
  final DocShowOn showOn;
  final bool locked;
  final bool hidden;

  /// Drawn only when the clinic has a logo (e.g. a white tile behind it).
  final bool onlyWithLogo;

  /// Shift (mm) applied when there is no logo, so text slides into the
  /// logo's empty space instead of leaving a gap.
  final double noLogoDx;
  final double noLogoDy;

  DocBlock copyWith({
    String? id,
    DocZone? zone,
    double? x,
    double? y,
    double? w,
    double? h,
    String? field,
    String? text,
    DocImageRole? imageRole,
    String? imagePath,
    String? imageSha,
    String? qr,
    double? fontPt,
    bool? bold,
    DocAlign? align,
    String? color,
    String? fill,
    double? strokePt,
    double? radiusMm,
    double? opacity,
    DocShowOn? showOn,
    bool? locked,
    bool? hidden,
    bool? onlyWithLogo,
    double? noLogoDx,
    double? noLogoDy,
  }) => DocBlock(
    id: id ?? this.id,
    type: type,
    zone: zone ?? this.zone,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    field: field ?? this.field,
    text: text ?? this.text,
    imageRole: imageRole ?? this.imageRole,
    imagePath: imagePath ?? this.imagePath,
    imageSha: imageSha ?? this.imageSha,
    qr: qr ?? this.qr,
    fontPt: fontPt ?? this.fontPt,
    bold: bold ?? this.bold,
    align: align ?? this.align,
    color: color ?? this.color,
    fill: fill ?? this.fill,
    strokePt: strokePt ?? this.strokePt,
    radiusMm: radiusMm ?? this.radiusMm,
    opacity: opacity ?? this.opacity,
    showOn: showOn ?? this.showOn,
    locked: locked ?? this.locked,
    hidden: hidden ?? this.hidden,
    onlyWithLogo: onlyWithLogo ?? this.onlyWithLogo,
    noLogoDx: noLogoDx ?? this.noLogoDx,
    noLogoDy: noLogoDy ?? this.noLogoDy,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'zone': zone.name,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'field': field,
    'text': text,
    'imageRole': imageRole.name,
    'imagePath': imagePath,
    'imageSha': imageSha,
    'qr': qr,
    'fontPt': fontPt,
    'bold': bold,
    'align': align.name,
    'color': color,
    'fill': fill,
    'strokePt': strokePt,
    'radiusMm': radiusMm,
    'opacity': opacity,
    'showOn': showOn.name,
    'locked': locked,
    'hidden': hidden,
    'onlyWithLogo': onlyWithLogo,
    'noLogoDx': noLogoDx,
    'noLogoDy': noLogoDy,
  };

  static DocBlock fromMap(Map m) => DocBlock(
    id: _s(m['id']),
    type: docEnum(DocBlockType.values, m['type'], DocBlockType.text),
    zone: docEnum(DocZone.values, m['zone'], DocZone.header),
    x: _d(m['x'], 0),
    y: _d(m['y'], 0),
    w: _d(m['w'], 20),
    h: _d(m['h'], 5),
    field: _s(m['field']),
    text: _s(m['text']),
    imageRole: docEnum(
      DocImageRole.values,
      m['imageRole'],
      DocImageRole.custom,
    ),
    imagePath: _s(m['imagePath']),
    imageSha: _s(m['imageSha']),
    qr: _s(m['qr']),
    fontPt: _d(m['fontPt'], 10),
    bold: _b(m['bold'], false),
    align: docEnum(DocAlign.values, m['align'], DocAlign.left),
    color: _s(m['color'], 'text'),
    fill: _s(m['fill'], 'none'),
    strokePt: _d(m['strokePt'], 0),
    radiusMm: _d(m['radiusMm'], 0),
    opacity: _d(m['opacity'], 1),
    showOn: docEnum(DocShowOn.values, m['showOn'], DocShowOn.all),
    locked: _b(m['locked'], false),
    hidden: _b(m['hidden'], false),
    onlyWithLogo: _b(m['onlyWithLogo'], false),
    noLogoDx: _d(m['noLogoDx'], 0),
    noLogoDy: _d(m['noLogoDy'], 0),
  );
}

/// One section of the flowing body (patient, items, signature…).
class DocBodySection {
  const DocBodySection(this.id, {this.visible = true});

  final String id;
  final bool visible;

  DocBodySection copyWith({bool? visible}) =>
      DocBodySection(id, visible: visible ?? this.visible);

  Map<String, dynamic> toMap() => {'id': id, 'on': visible};

  static DocBodySection fromMap(Map m) =>
      DocBodySection(_s(m['id']), visible: _b(m['on'], true));
}

class DocOptions {
  const DocOptions({
    this.invoiceSignature = InvoiceSignature.doctor,
    this.medicinesInCapitals = true,
    this.amountInWords = true,
    this.upiQr = true,
  });

  final InvoiceSignature invoiceSignature;
  final bool medicinesInCapitals;
  final bool amountInWords;
  final bool upiQr;

  DocOptions copyWith({
    InvoiceSignature? invoiceSignature,
    bool? medicinesInCapitals,
    bool? amountInWords,
    bool? upiQr,
  }) => DocOptions(
    invoiceSignature: invoiceSignature ?? this.invoiceSignature,
    medicinesInCapitals: medicinesInCapitals ?? this.medicinesInCapitals,
    amountInWords: amountInWords ?? this.amountInWords,
    upiQr: upiQr ?? this.upiQr,
  );

  Map<String, dynamic> toMap() => {
    'invoiceSignature': invoiceSignature.name,
    'medicinesInCapitals': medicinesInCapitals,
    'amountInWords': amountInWords,
    'upiQr': upiQr,
  };

  static DocOptions fromMap(Object? m) {
    if (m is! Map) return const DocOptions();
    return DocOptions(
      invoiceSignature: docEnum(
        InvoiceSignature.values,
        m['invoiceSignature'],
        InvoiceSignature.doctor,
      ),
      medicinesInCapitals: _b(m['medicinesInCapitals'], true),
      amountInWords: _b(m['amountInWords'], true),
      upiQr: _b(m['upiQr'], true),
    );
  }
}

class DocTemplate {
  const DocTemplate({
    required this.id,
    required this.name,
    this.scope = DocScope.builtin,
    this.ownerUid = '',
    this.presetId = '',
    this.kinds = const [],
    this.paper = const DocPaper(),
    this.headerMm = 40,
    this.footerMm = 14,
    this.style = const DocStyle(),
    this.background,
    this.blocks = const [],
    this.body = const {},
    this.options = const DocOptions(),
    this.schemaVersion = kDocSchemaVersion,
    this.updatedAt = 0,
    this.updatedByUid = '',
  });

  final String id;
  final String name;
  final DocScope scope;
  final String ownerUid;

  /// The ready-made template it started from.
  final String presetId;

  /// Empty = every kind.
  final List<DocKind> kinds;
  final DocPaper paper;
  final double headerMm;
  final double footerMm;
  final DocStyle style;
  final DocBackground? background;
  final List<DocBlock> blocks;
  final Map<DocKind, List<DocBodySection>> body;
  final DocOptions options;
  final int schemaVersion;

  /// Milliseconds since epoch; used to spot two people editing at once.
  final int updatedAt;
  final String updatedByUid;

  bool get isBuiltin => scope == DocScope.builtin;
  bool get freeLayout => !paper.isRoll;
  bool get tooNew => schemaVersion > kDocSchemaVersion;
  bool appliesTo(DocKind k) => kinds.isEmpty || kinds.contains(k);
  double zoneHeight(DocZone z) => z == DocZone.header ? headerMm : footerMm;

  /// The body sections for [k]: saved order first (unknown ids dropped),
  /// then any section added in a later app version.
  List<DocBodySection> bodyFor(DocKind k) {
    final defaults = defaultBodySections(k);
    final saved = body[k];
    if (saved == null) return defaults;
    final known = {for (final d in defaults) d.id};
    final ids = {for (final s in saved) s.id};
    return [
      ...saved.where((s) => known.contains(s.id)),
      ...defaults.where((d) => !ids.contains(d.id)),
    ];
  }

  DocTemplate withBodySections(DocKind k, List<DocBodySection> sections) {
    return copyWith(body: {...body, k: sections});
  }

  DocTemplate copyWith({
    String? id,
    String? name,
    DocScope? scope,
    String? ownerUid,
    String? presetId,
    List<DocKind>? kinds,
    DocPaper? paper,
    double? headerMm,
    double? footerMm,
    DocStyle? style,
    DocBackground? background,
    bool clearBackground = false,
    List<DocBlock>? blocks,
    Map<DocKind, List<DocBodySection>>? body,
    DocOptions? options,
    int? updatedAt,
    String? updatedByUid,
  }) => DocTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    scope: scope ?? this.scope,
    ownerUid: ownerUid ?? this.ownerUid,
    presetId: presetId ?? this.presetId,
    kinds: kinds ?? this.kinds,
    paper: paper ?? this.paper,
    headerMm: headerMm ?? this.headerMm,
    footerMm: footerMm ?? this.footerMm,
    style: style ?? this.style,
    background: clearBackground ? null : (background ?? this.background),
    blocks: blocks ?? this.blocks,
    body: body ?? this.body,
    options: options ?? this.options,
    schemaVersion: schemaVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByUid: updatedByUid ?? this.updatedByUid,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'scope': scope.name,
    'ownerUid': ownerUid,
    'presetId': presetId,
    'kinds': [for (final k in kinds) k.name],
    'paper': paper.toMap(),
    'headerMm': headerMm,
    'footerMm': footerMm,
    'style': style.toMap(),
    'background': background?.toMap(),
    'blocks': [for (final b in blocks) b.toMap()],
    'body': {
      for (final e in body.entries)
        e.key.name: [for (final s in e.value) s.toMap()],
    },
    'options': options.toMap(),
    'schemaVersion': schemaVersion,
    'updatedAt': updatedAt,
    'updatedByUid': updatedByUid,
  };

  static DocTemplate fromMap(String id, Map<String, dynamic> m) {
    final rawBody = m['body'];
    final body = <DocKind, List<DocBodySection>>{};
    if (rawBody is Map) {
      for (final e in rawBody.entries) {
        final kind = docKindOrNull(e.key);
        if (kind == null || e.value is! List) continue;
        body[kind] = [
          for (final s in e.value as List)
            if (s is Map) DocBodySection.fromMap(s),
        ];
      }
    }
    return DocTemplate(
      id: id,
      name: _s(m['name'], 'Template'),
      scope: docEnum(DocScope.values, m['scope'], DocScope.clinic),
      ownerUid: _s(m['ownerUid']),
      presetId: _s(m['presetId']),
      kinds: [
        for (final k in (m['kinds'] as List? ?? const [])) ?docKindOrNull(k),
      ],
      paper: DocPaper.fromMap(m['paper']),
      headerMm: _d(m['headerMm'], 40),
      footerMm: _d(m['footerMm'], 14),
      style: DocStyle.fromMap(m['style']),
      background: DocBackground.fromMap(m['background']),
      blocks: [
        for (final b in (m['blocks'] as List? ?? const []))
          if (b is Map) DocBlock.fromMap(b),
      ],
      body: body,
      options: DocOptions.fromMap(m['options']),
      schemaVersion: _i(m['schemaVersion'], 1),
      updatedAt: _i(m['updatedAt'], 0),
      updatedByUid: _s(m['updatedByUid']),
    );
  }
}
