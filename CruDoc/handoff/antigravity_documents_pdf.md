# Antigravity brief: Documents & PDF templates (bills, prescriptions, referrals, reports, certificates)

This file is the whole brief. Open it from the repo (`CruDoc/handoff/antigravity_documents_pdf.md`)
and do what **▶ DO NOW** says. Claude (the lead) reviews at each GATE and then updates DO NOW.

## ▶ DO NOW

**Phase 2: tasks T15 to T22, in order.** Write every task first, then run the Phase 2 Checks once.
Then **STOP at GATE 2** and report (see "Reporting").

Do not start Phase 3. Phase 1 is done — don't redo it; read "Gate 1 notes" below first.

## Status (Claude updates this)

- Phase 1 (engine, data, rules): **done, passed GATE 1 on 2026-10-25** (see Gate 1 notes)
- Phase 2 (bill flow, preview, all document kinds, Settings): **do now**
- Phase 3 (layout editor, letterhead paper, Indian scripts): not started

## Gate 1 notes (changes Claude made after reviewing Phase 1 — build on them)

- `DocBlock` has three new fields: `onlyWithLogo` (bool), `noLogoDx`, `noLogoDy` (mm). Without a clinic logo the
  renderer skips `onlyWithLogo` blocks and shifts the others by `noLogoDx/Dy`, so headers have no empty logo space.
  The Classic, Colour band and Compact A5 presets use them (helper `_logoAware` in `doc_presets.dart`).
  Keep these fields in every `copyWith`/`toMap`; Phase 3's editor canvas must apply the same shift when there is no logo.
- `resolveTemplate` now skips a template that doesn't fit the kind (`appliesTo`) or is too new, and falls to the
  next choice. Do the same filtering anywhere you list templates for a kind.
- The `doctorList` block falls back to the issuing doctor when there is no member list (solo practice).
  `docSampleContext` takes an optional `doctors:` list (a second made-up doctor appears only in fully sample previews).
- Watermarks are drawn through `pw.Opacity` (the PDF library ignores a colour's alpha for text).
- The 80 mm receipt prints "CANCELLED" at the top for cancelled bills. Prescription title is now "PRESCRIPTION".
- Rules tests: port 8080 on this PC is taken by Jenkins. Run them with a temporary copy of `firebase.json` whose
  Firestore port is 8085 and UI is off: `firebase emulators:exec -c firebase.rulestest.json --project demo-crudoc --only firestore "npm test --prefix tests/firestore-rules"`
  (Storage: `--only storage,firestore` and `tests/storage-rules`), then delete the temporary file.
  At GATE 1 they passed: Firestore 208/208, Storage 57 + 1 old skip.

---

## Rules (how to work)

- Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc` (Flutter + Firebase). Paths starting with
  `lib/`, `test/`, `tests/`, `firestore.rules`, `storage.rules` are relative to that folder.
  Dart package name: `doctor_management_app`.
- Work without pausing. Write every task in DO NOW first, then run all Checks once at the end.
  Start slow commands (tests) in the background and keep going.
- Create or change only the files a task names. Do not rename, move or reformat anything else.
  Run `dart format` only on files you touched.
- If the code you find doesn't match a step (a name or field differs), make the smallest change that
  keeps the meaning, write down what you changed, and carry on. If you can't, skip that one step,
  note it, carry on. Only a **GATE** line stops the run.
- **Never deploy** (no `firebase deploy`, no functions/rules/index deploys). **Never** `git commit`/`push`.
  Do not run `flutter run` or a release build; the user tests on the phone and PC.
- Never run the whole `flutter test` suite (parallel runs crash on sqlite3.dll). Run only the test
  files a Check names, one at a time.
- UI code: read `.claude/rules/crudoc-ui.md` and follow it (`context.cru` colours, `CruSpace`,
  `CruRadius`, `CruType`, Geist font, no hard-coded colours/sizes, one filled button per region).
  Reuse the `Cru*` widgets from `lib/shared/widgets/cru/cru.dart` (`CruFormDialog`, `CruFormSection`,
  `CruFieldRow`, `CruPickerField`, `CruFieldFrame`, `CruSquareButton`, …).
- **Never print made-up data.** No sample registration numbers, phones, addresses or clinic names in
  any real PDF or screen. Missing value → hide that element (and show a warning in the preview).
  Sample data is allowed only in template previews, which always carry a big "SAMPLE" watermark.
- Money is calculated in **whole paise (`int`)**, never by adding doubles. Show it with Indian
  grouping: `₹1,25,000` / `₹1,250.50`.
- Never put a patient's name in a file name.
- Dart in this repo uses Dart 3 (records, patterns, `switch` expressions, `?element` in lists). Fine to use.

## Reporting (at each GATE)

1. Every file you created/changed/deleted.
2. Output of each Check (paste the end of each command's output).
3. Anything you skipped or changed from the brief, and why.
4. Phase 1 only: the list of PDFs written to `build/doc_samples/`.

---

## What we're building

Like **Vyapar**: fill a few details → the bill (or prescription, referral, report, certificate) appears
→ Print / Share / WhatsApp. On top of that:

1. **Ready-made templates** to pick from (Classic, Centered, Colour band, Polyclinic, Compact A5,
   My letterhead paper, 80 mm receipt).
2. **Own branding**: clinic logo, clinic stamp, each doctor's **e-signature** (draw or photo) and stamp.
3. **Multi-doctor clinics**: clinic details are shared, each doctor's name / qualifications /
   registration / signature are their own, the document shows the doctor it is **for**, and nobody
   can put another doctor's signature on anything.
4. **One engine for every document**: invoice, prescription, referral letter, medical report, medical
   certificate (and the dental lab Rx).
5. **Proper preview**: the real PDF page, with a template switcher, warnings for missing details, and
   Print / Share / Save / WhatsApp.
6. **Own templates with a layout editor** (Phase 3): like PUBG Mobile's control layout screen. Every
   element on the letterhead (logo, clinic name, doctor name, signature, QR, lines, boxes, custom text)
   can be dragged, resized, hidden, styled. Only for the doctor's/clinic's own templates; ready-made
   ones are copied first ("Customize").

---

## Design (decisions; follow exactly)

### D1. Document kinds
`DocKind`: `invoice`, `prescription`, `referral`, `report`, `certificate`. The existing
`PdfMedicalDocumentType` enum gains `referral` and `certificate` and a `kind` getter that maps to `DocKind`.

### D2. What a template is
A template is **one letterhead design used by all kinds** (unless its `kinds` list narrows it):

- **Paper**: A4 / A5 / Letter / Custom (mm) / 80 mm receipt roll, plus margins (mm).
- **Header zone** (top, `headerMm` tall) and **footer zone** (bottom, `footerMm` tall), repeated on every
  page. Inside them, **free blocks** sit at any position: `x, y, w, h` in **millimetres from the zone's
  top-left corner** (zone left = left margin). Each block can show on all pages / first / last / not first.
- **Body** (between the zones): the document's content flowing over as many pages as needed.
  Its **sections** (patient, items table, totals, Rx table, signature, …) can be reordered and hidden
  per kind, but not free-positioned (they flow across pages).
- **Style**: accent / text / muted / border / soft colours, body text size (`fontScale`).
- **Background** (optional): a scan/photo/PDF of the doctor's own printed letterhead paper. Shown in the
  shared PDF; **left out when printing** if `printOnPaper` is false (they print on that paper).
- **Options**: invoice signature (doctor / clinic stamp / blank line / none), medicine names in
  capitals, amount in words, UPI QR.
- Receipt-roll templates (`roll80`) have no free layout: a fixed receipt layout is used.

### D3. Where data lives (Firestore, all under the clinic; `clinicId` = tenant id)

| Path | What | Read | Write |
|---|---|---|---|
| `clinics/{c}/doc_settings/clinic` | Clinic details for documents, logo, clinic stamp, GST, UPI, number prefixes, default template per kind, lock | any member | `settings` permission |
| `clinics/{c}/doc_doctors/{uid}` | One doctor's name on documents, qualifications, specialty, reg. no., council, signature, stamp, consultation fee, own default template per kind | any member | **only that doctor** |
| `clinics/{c}/doc_templates/{id}` | Templates. `scope` = `clinic` or `doctor`; `ownerUid` | any member | clinic: `settings`; doctor: only `ownerUid` |
| `clinics/{c}/doc_counters/{kind}_{fy}` | Last used number per kind per financial year | any member | `billing` or `clinical.edit`, +1 only |

Solo doctors have no clinic document, but their tenant id is their uid, so the same paths work
(the rules' `clinicAllows` already treats the owner uid as the clinic).

Storage (images; always PNG):

| Path | What | Write |
|---|---|---|
| `doctors/{c}/clinic/branding/logo.png`, `…/clinic-stamp.png` | clinic images | `settings` (existing rule) |
| `doctors/{c}/clinic/branding/templates/{templateId}/{sha8}.png` | clinic template images, letterhead background | `settings` (existing rule) |
| `doctors/{c}/doctor-files/{uid}/signature.png`, `stamp.png`, `templates/{id}/{sha8}.png` | one doctor's own images | only that doctor (new rule) |

Every stored image reference is a pair `path` + `sha256` (hex). The PDF uses an image **only if the
downloaded bytes match the sha256 saved in the owner's document** — so a swapped file is never printed.
Images are cached on the device by sha256, so documents print offline.

### D4. Which doctor, which template, whose signature
- **Issuing doctor** = the doctor the document is for: invoice → `attendingDoctorUid` (picked on the bill;
  default = the visit's doctor, else the signed-in doctor); prescription/report/certificate/referral →
  the signed-in doctor (or the visit's doctor when a doctor opens it from a visit).
  A receptionist's bill with no doctor chosen shows clinic details only.
- **Doctor details** come from `doc_doctors/{uid}`, then `clinics/{c}/members/{uid}` (name,
  qualification, registrationNo, specialty), then the signed-in user's old letterhead fields.
- **Clinic details** come from `doc_settings/clinic`, then the old letterhead fields on the owner's
  `users/{uid}` profile (only readable by the owner) — so existing solo doctors see their details
  without re-typing anything.
- **Signature rule**: a document carries `signedByUid`, set **only** when the signed-in user *is* the
  issuing doctor (helper `docSignerFor`). The signature image is printed only when
  `signedByUid == issuing doctor uid`, that doctor is still active, and the image hash matches.
  So a receptionist printing a bill made by Dr A still shows Dr A's signature (Dr A created it), but a
  receptionist can never create a prescription with Dr A's signature.
- **Invoices** follow the template option `invoiceSignature`: `doctor` (rule above; falls back to a blank
  line), `clinicStamp` (clinic stamp + "Authorised signatory"), `line`, `none`.
- **Template choice**, first that exists: the one stored on the document (`templateId`) → the issuing
  doctor's default for this kind → the clinic default for this kind → `builtin.classic`.
  If the clinic turns on **"Everyone uses clinic templates"** (`lockTemplates`), doctors' own templates
  and defaults are ignored and hidden.
- A template saved by a newer app version (`schemaVersion` > ours) → use `builtin.classic` and warn
  "Update CruDoc to use the template ‘…’".

### D5. Numbers (like Vyapar)
- Format `PREFIX-FY/NNNN`, e.g. `INV-26-27/0042`. FY = Indian financial year of the **document date**
  (April–March). Prefixes per kind, editable in Settings (default INV, RX, REF, REP, CERT; max 5 letters).
- Assigned **on save** (never while the form is open, so cancelled forms don't burn numbers) with a
  Firestore transaction on the counter document.
- Offline (transaction fails or 6 s timeout): `PREFIX-FY/XY007` where `XY` is a random 2-letter code
  made once per device (SharedPreferences `docs.deviceCode`) and `007` a per-device counter
  (`docs.localSeq.<kind>.<fy>`). Still unique, no clash with online numbers.
- The number can be edited on the bill; on save, refuse a number that another invoice already has.
- Invoices are never deleted from the bill screens: **Cancel invoice** keeps the number and stamps the PDF
  "CANCELLED" (no gaps in the series). Cancelled invoices are left out of all revenue totals.

### D6. Rendering rules
- Font: **Geist** (bundled, has ₹) embedded in every PDF. Never Helvetica (no ₹ sign).
- Text goes through `pdfSafe()` (drops emoji/variation selectors that the font can't draw).
- Long text is split into paragraphs (never one giant `Text` inside a box — `MultiPage` can't split it).
  Tables go straight into the page's widget list so they split across pages and repeat their header.
- Free-block text: one-line fields shrink to fit their box; multi-line fields wrap and clip at the
  box height.
- Empty value → the block is not drawn. Missing image → not drawn (no "+" placeholder).
- Up to 60 pages; more → show "This document is too long to print" instead of crashing.
- Watermarks: "CANCELLED" (cancelled invoices), "SAMPLE" (template previews).
- Indian scripts (Devanagari etc.): Phase 3 renders those strings as images (the PDF library can't shape
  them). Until then they may print wrongly; the preview warns.

### D7. Preview and actions
After saving a bill (or tapping Print on any document) the **preview** opens: real PDF pages,
a **template switcher** (only templates that apply to this kind), "Use for all future …" switch,
amber warnings with a **Fix** button (missing registration number, logo not downloaded…), and actions:
**Print** (filled), **Share PDF**, **Save PDF** (desktop), **WhatsApp**, **Edit**.
- Print uses the "for print" render (letterhead background left out when `printOnPaper` is false).
  Share/Save/WhatsApp use the digital render (background included).
- The cloud copy (`GeneratedDocumentSync.enqueue`) happens **once, when the user prints/shares/saves**,
  not every time the preview re-renders.

### D8. Edge cases this design must handle (checklist for GATE reviews)
1. No logo / no signature / no stamp → hidden, never a placeholder.
2. Image not on this device and offline → hidden + warning "Logo not downloaded yet".
3. Image file swapped in storage → hash mismatch → hidden + warning.
4. Photo of a signature on white paper → background removed (white → transparent).
5. HEIC/SVG/GIF/huge files → converted or refused with a clear message (JPG/PNG/WebP accepted, ≤ 15 MB).
6. Old fake letterhead fallbacks (`MMC-2024/98765` etc.) → removed everywhere.
7. Receptionist bills for a doctor → doctor's details shown; signature only if that doctor made it.
8. Doctor left the clinic → name still printed on old documents, signature never.
9. Clinic forces clinic templates → doctors' own templates hidden.
10. Template from a newer app → classic + warning.
11. Two admins edit the same template → "Someone changed this template since you opened it" (Overwrite / Reload).
12. Long clinic names/addresses → shrink/wrap inside their box; never overlap the body.
13. 60 bill lines / long notes → multiple pages, table header repeats, totals and signature after the table.
14. Discount bigger than the bill → capped. Received more than total → capped. Paise maths exact.
15. Backdated document → number uses that date's financial year.
16. Offline → numbers still unique; templates/settings from Firestore's offline cache; images from device cache.
17. Pre-printed letterhead paper → nothing printed in the header/footer zones; background only in shared copies.
18. A5 template printed on an A4 printer → the PDF keeps its own paper size; the printer dialog scales.
19. 80 mm thermal printers → receipt-roll template (invoices only).
20. Patient without phone → WhatsApp disabled. Walk-in without patient record → no cloud copy (as today).
21. Cancelled invoice → "CANCELLED" watermark, out of revenue.
22. File names never contain patient names.
23. Web: no device cache (memory only); everything else works.

---

# PHASE 1 — Engine, data, rules (T1–T14)

New folders: `lib/core/pdf/render/`, `lib/core/pdf/data/`. Existing: `lib/core/pdf/models/`,
`lib/core/pdf/templates/`, `lib/core/pdf/services/`, `lib/core/pdf/presentation/`.

## T1. Fonts, safe text, money, words, dates

Create `lib/core/pdf/render/pdf_text.dart` with exactly this:

```dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

/// Geist, the app font, embedded in every PDF. It has the ₹ sign; the
/// PDF library's built-in Helvetica does not.
class PdfFonts {
  PdfFonts._(this.regular, this.medium, this.bold);

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;

  static PdfFonts? _cached;

  static Future<PdfFonts> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    Future<pw.Font> font(String file) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/Geist/$file'));
    return _cached = PdfFonts._(
      await font('Geist-Regular.ttf'),
      await font('Geist-Medium.ttf'),
      await font('Geist-Bold.ttf'),
    );
  }

  pw.ThemeData theme() => pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: regular,
    boldItalic: bold,
  );
}

final _undrawable = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE00}-\u{FE0F}\u{200D}]',
  unicode: true,
);

/// Text the PDF font can draw: emoji and joiners removed, tabs as spaces.
String pdfSafe(String? s) =>
    (s ?? '').replaceAll(_undrawable, '').replaceAll('\t', ' ').trim();

/// True when [s] has letters of scripts Geist cannot draw (Hebrew/Arabic
/// to Sinhala, which covers Devanagari, Gujarati, Tamil, Telugu, Kannada…).
bool needsScriptFallback(String s) =>
    s.runes.any((r) => r >= 0x0590 && r <= 0x0DFF);

/// Rupees → whole paise.
int toPaise(num rupees) => (rupees * 100).round();

final _inr2 = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);
final _inr0 = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

/// "₹1,25,000" for whole rupees, "₹1,250.50" otherwise.
String formatPaise(int paise) => paise % 100 == 0
    ? _inr0.format(paise ~/ 100)
    : _inr2.format(paise / 100);

/// "24 Oct 2026".
String formatDocDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

/// Indian financial year of [d]: April 2026 – March 2027 → "26-27".
String financialYear(DateTime d) {
  final start = d.month >= 4 ? d.year : d.year - 1;
  String two(int y) => (y % 100).toString().padLeft(2, '0');
  return '${two(start)}-${two(start + 1)}';
}

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight',
  'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
  'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = [
  '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy',
  'Eighty', 'Ninety',
];

String _below100(int n) => n < 20
    ? _ones[n]
    : '${_tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${_ones[n % 10]}'}';

String _below1000(int n) {
  final h = n ~/ 100;
  final r = n % 100;
  return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) _below100(r)].join(' ');
}

/// Indian system: 1,23,45,678 → "One Crore Twenty Three Lakh Forty Five
/// Thousand Six Hundred Seventy Eight".
String _indianWords(int n) {
  if (n == 0) return 'Zero';
  final crore = n ~/ 10000000;
  final lakh = (n % 10000000) ~/ 100000;
  final thousand = (n % 100000) ~/ 1000;
  final rest = n % 1000;
  return [
    if (crore > 0) '${_indianWords(crore)} Crore',
    if (lakh > 0) '${_below100(lakh)} Lakh',
    if (thousand > 0) '${_below100(thousand)} Thousand',
    if (rest > 0) _below1000(rest),
  ].join(' ');
}

/// "Rupees One Thousand Two Hundred Fifty and Fifty Paise Only".
String rupeesInWords(int paise) {
  final p = paise.abs();
  final words = StringBuffer(paise < 0 ? 'Minus ' : '')
    ..write('Rupees ${_indianWords(p ~/ 100)}');
  if (p % 100 > 0) words.write(' and ${_below100(p % 100)} Paise');
  words.write(' Only');
  return words.toString();
}
```

## T2. Template model

Create `lib/core/pdf/templates/doc_template.dart`. Use this code as written (add nothing else):

```dart
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
    imageRole: docEnum(DocImageRole.values, m['imageRole'], DocImageRole.custom),
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
        for (final k in (m['kinds'] as List? ?? const []))
          ?docKindOrNull(k),
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
```

(`docKindOrNull` is used where an unknown kind must be dropped rather than defaulted.)

## T3. Field catalogue

Create `lib/core/pdf/templates/doc_fields.dart`:

```dart
/// A value a header/footer block can show. Values are filled in by
/// `DocContext.field` (lib/core/pdf/render/doc_context.dart).
class DocFieldDef {
  const DocFieldDef(this.key, this.label, this.group, {this.multiline = false});

  final String key;
  final String label;
  final String group;
  final bool multiline;
}

const docFields = <DocFieldDef>[
  DocFieldDef('clinic.name', 'Clinic name', 'Clinic'),
  DocFieldDef('clinic.tagline', 'Tagline', 'Clinic'),
  DocFieldDef('clinic.address', 'Address', 'Clinic', multiline: true),
  DocFieldDef('clinic.phone', 'Phone', 'Clinic'),
  DocFieldDef('clinic.email', 'Email', 'Clinic'),
  DocFieldDef('clinic.website', 'Website', 'Clinic'),
  DocFieldDef('clinic.timings', 'Timings', 'Clinic', multiline: true),
  DocFieldDef('clinic.regNo', 'Clinic registration no.', 'Clinic'),
  DocFieldDef('clinic.gstin', 'GSTIN', 'Clinic'),
  DocFieldDef('clinic.contactLine', 'Phone · email · website', 'Clinic', multiline: true),
  DocFieldDef('clinic.addressContact', 'Address · phone · email', 'Clinic', multiline: true),
  DocFieldDef('doctor.name', 'Doctor name', 'Doctor'),
  DocFieldDef('doctor.qualification', 'Qualifications', 'Doctor'),
  DocFieldDef('doctor.specialty', 'Specialty', 'Doctor'),
  DocFieldDef('doctor.regNo', 'Registration no.', 'Doctor'),
  DocFieldDef('doctor.nameQual', 'Name · qualifications', 'Doctor'),
  DocFieldDef('doctor.specReg', 'Specialty · registration', 'Doctor'),
  DocFieldDef('doctor.phone', 'Doctor phone', 'Doctor'),
  DocFieldDef('doctor.email', 'Doctor email', 'Doctor'),
  DocFieldDef('doc.title', 'Document title', 'Document'),
  DocFieldDef('doc.number', 'Number', 'Document'),
  DocFieldDef('doc.numberLine', 'No. …', 'Document'),
  DocFieldDef('doc.date', 'Date', 'Document'),
  DocFieldDef('doc.dateLine', 'Date: …', 'Document'),
  DocFieldDef('doc.status', 'Paid / balance due', 'Document'),
  DocFieldDef('patient.name', 'Patient name', 'Patient'),
  DocFieldDef('patient.ageSex', 'Age / sex', 'Patient'),
  DocFieldDef('patient.phone', 'Patient phone', 'Patient'),
  DocFieldDef('patient.line', 'Name · age/sex · phone', 'Patient'),
  DocFieldDef('page.number', 'Page 1 of 2', 'Page'),
  DocFieldDef('footer.text', 'Footer note', 'Page', multiline: true),
];

DocFieldDef? docFieldDef(String key) {
  for (final f in docFields) {
    if (f.key == key) return f;
  }
  return null;
}
```

## T4. Body sections

Create `lib/core/pdf/templates/doc_body_sections.dart`:

```dart
import 'doc_template.dart';

/// Body section ids. The renderer has one builder per id.
abstract final class DocSection {
  static const meta = 'meta';
  static const patient = 'patient';
  static const items = 'items';
  static const totals = 'totals';
  static const words = 'words';
  static const payment = 'payment';
  static const upi = 'upi';
  static const notes = 'notes';
  static const terms = 'terms';
  static const vitals = 'vitals';
  static const complaints = 'complaints';
  static const diagnosis = 'diagnosis';
  static const rx = 'rx';
  static const investigations = 'investigations';
  static const advice = 'advice';
  static const followUp = 'followUp';
  static const recipient = 'recipient';
  static const reason = 'reason';
  static const findings = 'findings';
  static const question = 'question';
  static const teeth = 'teeth';
  static const sections = 'sections';
  static const certificate = 'certificate';
  static const signature = 'signature';

  static const labels = <String, String>{
    meta: 'Title, number and date',
    patient: 'Patient details',
    items: 'Items table',
    totals: 'Totals',
    words: 'Amount in words',
    payment: 'Payment received / balance',
    upi: 'UPI pay QR',
    notes: 'Notes',
    terms: 'Terms',
    vitals: 'Vitals',
    complaints: 'Complaints',
    diagnosis: 'Diagnosis',
    rx: 'Medicines (Rx)',
    investigations: 'Investigations',
    advice: 'Advice',
    followUp: 'Follow-up',
    recipient: 'Referred to',
    reason: 'Reason',
    findings: 'Findings / summary',
    question: 'Question for the specialist',
    teeth: 'Teeth',
    sections: 'Report sections',
    certificate: 'Certificate text',
    signature: 'Signature',
  };
}

/// Default body for [kind]. `meta` is hidden by default; templates whose
/// header has no title/number/date turn it on.
List<DocBodySection> defaultBodySections(DocKind kind, {bool meta = false}) {
  final ids = switch (kind) {
    DocKind.invoice => [
      DocSection.meta, DocSection.patient, DocSection.items, DocSection.totals,
      DocSection.words, DocSection.payment, DocSection.upi, DocSection.notes,
      DocSection.terms, DocSection.signature,
    ],
    DocKind.prescription => [
      DocSection.meta, DocSection.patient, DocSection.vitals,
      DocSection.complaints, DocSection.diagnosis, DocSection.rx,
      DocSection.investigations, DocSection.advice, DocSection.followUp,
      DocSection.notes, DocSection.signature,
    ],
    DocKind.referral => [
      DocSection.meta, DocSection.patient, DocSection.recipient,
      DocSection.reason, DocSection.findings, DocSection.question,
      DocSection.teeth, DocSection.notes, DocSection.signature,
    ],
    DocKind.report => [
      DocSection.meta, DocSection.patient, DocSection.sections,
      DocSection.notes, DocSection.signature,
    ],
    DocKind.certificate => [
      DocSection.meta, DocSection.patient, DocSection.certificate,
      DocSection.signature,
    ],
  };
  return [
    for (final id in ids)
      DocBodySection(id, visible: id != DocSection.meta || meta),
  ];
}

/// Every kind's default body, with `meta` on or off.
Map<DocKind, List<DocBodySection>> defaultBodies({required bool meta}) => {
  for (final k in DocKind.values) k: defaultBodySections(k, meta: meta),
};
```

## T5. Ready-made templates

Create `lib/core/pdf/templates/doc_presets.dart`. Write helpers and the 7 presets below. Coordinates are mm
inside the zone. A4 content width = 210 − 12 − 12 = **186 mm**. A5 content width = 148 − 8 − 8 = **132 mm**.

```dart
import 'doc_body_sections.dart';
import 'doc_template.dart';

DocBlock _f(String id, String field, double x, double y, double w, double h,
        {double pt = 9,
        bool bold = false,
        DocAlign align = DocAlign.left,
        String color = 'text',
        DocZone zone = DocZone.header}) =>
    DocBlock(id: id, type: DocBlockType.field, field: field, zone: zone,
        x: x, y: y, w: w, h: h, fontPt: pt, bold: bold, align: align,
        color: color);

DocBlock _img(String id, DocImageRole role, double x, double y, double w,
        double h, {DocAlign align = DocAlign.left}) =>
    DocBlock(id: id, type: DocBlockType.image, imageRole: role,
        x: x, y: y, w: w, h: h, align: align);

DocBlock _line(String id, double x, double y, double w,
        {String color = 'accent',
        double stroke = 1.2,
        DocZone zone = DocZone.header}) =>
    DocBlock(id: id, type: DocBlockType.line, zone: zone, x: x, y: y, w: w,
        h: 1, color: color, strokePt: stroke);

DocBlock _box(String id, double x, double y, double w, double h,
        {String fill = 'soft', String color = 'border', double stroke = 0.6,
        double radius = 2}) =>
    DocBlock(id: id, type: DocBlockType.box, x: x, y: y, w: w, h: h,
        fill: fill, color: color, strokePt: stroke, radiusMm: radius);

/// Footer used by the A4 presets.
List<DocBlock> _a4Footer() => [
  _line('footRule', 0, 0, 186, color: 'border', stroke: 0.6, zone: DocZone.footer),
  _f('footer', 'footer.text', 0, 3, 150, 8, pt: 7.5, color: 'muted', zone: DocZone.footer),
  _f('page', 'page.number', 150, 3, 36, 4, pt: 7.5, color: 'muted',
      align: DocAlign.right, zone: DocZone.footer),
];
```

Then `const`-free lists (they use helpers) in a top-level `final builtinTemplates = <DocTemplate>[…]` with
these entries (all `scope: DocScope.builtin`, `presetId` = their own id):

**1. `builtin.classic` — "Classic"** — A4, headerMm 40, footerMm 14, accent `0xFF0D9488`,
body `defaultBodies(meta: false)`, blocks:
| id | type | field/role | x | y | w | h | style |
|---|---|---|---|---|---|---|---|
| logo | image | logo | 0 | 0 | 22 | 22 | |
| clinicName | field | clinic.name | 26 | 0 | 108 | 8 | 16 pt bold |
| tagline | field | clinic.tagline | 26 | 8.5 | 108 | 4.5 | 8.5 pt bold accent |
| doctor | field | doctor.nameQual | 26 | 14 | 108 | 4.5 | 9.5 pt bold |
| doctorReg | field | doctor.specReg | 26 | 18.5 | 108 | 4 | 8 pt muted |
| metaBox | box | — | 138 | 0 | 48 | 22 | fill soft, border 0.6, radius 2 |
| docTitle | field | doc.title | 141 | 2.5 | 42 | 4.5 | 8.5 pt bold accent |
| docNo | field | doc.numberLine | 141 | 8.5 | 42 | 4.5 | 8.5 pt |
| docDate | field | doc.dateLine | 141 | 13.5 | 42 | 4.5 | 8.5 pt |
| address | field | clinic.address | 0 | 26 | 112 | 8 | 8 pt muted |
| contact | field | clinic.contactLine | 116 | 26 | 70 | 8 | 8 pt muted, right |
| rule | line | — | 0 | 36 | 186 | 1 | accent 1.6 pt |
plus `_a4Footer()`.

**2. `builtin.centered` — "Centered"** — A4, headerMm 46, footerMm 14, accent `0xFF1E3A5F`,
body `defaultBodies(meta: true)`, blocks:
logo image (83, 0, 20, 20, align center); clinicName (0, 21, 186, 8, 16 pt bold, center);
tagline (0, 29.5, 186, 4.5, 8.5 pt accent, center); doctor `doctor.nameQual` (0, 34, 186, 4.5, 9.5 pt bold, center);
addr `clinic.addressContact` (0, 38.5, 186, 4, 7.5 pt muted, center); rule line (0, 43.5, 186) accent 1.2; plus `_a4Footer()`.

**3. `builtin.band` — "Colour band"** — A4, headerMm 46, footerMm 14, accent `0xFF0F766E`,
body `defaultBodies(meta: false)`, blocks:
band box (0, 0, 186, 26, fill accent, stroke 0, radius 2); logoBg box (4, 3, 20, 20, fill white, stroke 0, radius 2);
logo image (5, 4, 18, 18); clinicName (28, 4, 108, 8, 16 pt bold, color white); tagline (28, 12.5, 108, 4.5, 8.5 pt, white);
docTitle (140, 4, 42, 4.5, 8.5 pt bold white right); docNo (140, 10, 42, 4.5, 8 pt white right);
docDate (140, 15, 42, 4.5, 8 pt white right); doctor `doctor.nameQual` (0, 29, 120, 4.5, 9.5 pt bold);
doctorReg `doctor.specReg` (0, 33.5, 120, 4, 8 pt muted); address `clinic.address` (120, 29, 66, 8, 7.5 pt muted right);
contact `clinic.contactLine` (0, 39, 186, 4, 7.5 pt muted); plus `_a4Footer()`.

**4. `builtin.polyclinic` — "Polyclinic (all doctors)"** — A4, headerMm 48, footerMm 14, accent `0xFF334155`,
body `defaultBodies(meta: true)`, blocks:
logo (0, 0, 18, 18); clinicName (22, 0, 142, 8, 16 pt bold center); tagline (22, 8.5, 142, 4.5, 8.5 pt accent center);
addr `clinic.addressContact` (0, 14, 186, 4, 7.5 pt muted center); rule1 line (0, 19.5, 186) border 0.6;
doctors `DocBlockType.doctorList` (0, 22, 186, 20, 8.5 pt, center); rule2 line (0, 44, 186) accent 1.2; plus `_a4Footer()`.

**5. `builtin.preprinted` — "My letterhead paper"** — A4, headerMm 45, footerMm 25, **no blocks**,
body `defaultBodies(meta: true)`. (For doctors who print on their own printed pads. In Phase 3 they can add a
photo of the pad as a background guide.)

**6. `builtin.compactA5` — "Compact A5"** — paper `DocPaper(format: a5, widthMm: 148, heightMm: 210, margins: DocMargins.all(8))`,
headerMm 30, footerMm 10, style `fontScale: 0.85`, accent `0xFF0D9488`, body `defaultBodies(meta: false)`, blocks:
logo (0, 0, 14, 14); clinicName (17, 0, 80, 6, 12 pt bold); doctor `doctor.nameQual` (17, 6.5, 80, 4, 8 pt bold);
doctorReg `doctor.specReg` (17, 10.5, 80, 3.5, 6.5 pt muted); docTitle (100, 0, 32, 4, 7 pt bold accent right);
docNo (100, 4.5, 32, 3.5, 6.5 pt right); docDate (100, 8.5, 32, 3.5, 6.5 pt right);
addr `clinic.addressContact` (0, 17, 132, 7, 6.5 pt muted); rule line (0, 26, 132) accent 1;
footer: `footer.text` (0, 2, 100, 6, 6 pt muted, zone footer); `page.number` (100, 2, 32, 3, 6 pt muted right, zone footer).

**7. `builtin.receipt80` — "80 mm receipt"** — paper `DocPaper(format: roll80, widthMm: 80, heightMm: 0, margins: DocMargins.all(3))`,
`kinds: [DocKind.invoice]`, headerMm 0, footerMm 0, no blocks.

Also add:

```dart
DocTemplate builtinById(String id) => builtinTemplates.firstWhere(
  (t) => t.id == id,
  orElse: () => builtinTemplates.first,
);
```

## T6. Settings models

Create `lib/core/pdf/data/doc_settings_models.dart` with two immutable classes, each with
`toMap()`, `static fromMap(Map<String, dynamic>? m)` (missing/odd values → defaults, never throw) and `copyWith`:

`ClinicDocSettings` fields (all `String` default `''` unless noted):
`name, tagline, address, phone, email, website, timings, regNo, gstin, footerText, termsText, upiId, upiName,
logoPath, logoSha, clinicStampPath, clinicStampSha`, `bool gstEnabled = false`, `bool roundOff = true`,
`bool lockTemplates = false`, `Map<String, String> prefixes` (kind name → prefix), `Map<String, String> defaults`
(kind name → template id), `int updatedAt = 0`.
Add `String prefixFor(DocKind k)` → `prefixes[k.name]` if it is 1–5 letters/digits, else `k.defaultPrefix`.

`DoctorDocProfile` fields: `String uid` (required), `nameOnDocs, qualification, specialty, regNo, regCouncil,
phone, email, signaturePath, signatureSha, stampPath, stampSha` (default `''`), `int consultFeePaise = 0`,
`Map<String, String> defaults`, `int updatedAt = 0`. **`toMap()` must include `'uid': uid`** (the rules check it).

## T7. Repository

Create `lib/core/pdf/data/doc_repository.dart`:

- `class DocRepository { DocRepository._(); static final instance = DocRepository._(); }`
- Private helpers: `String? get _tenant` → `ClinicSession.instance.tenantId`, but `null` when it is null, empty or
  `kLocalDoctorId` (import it the same way `lib/core/pdf/services/generated_document_sync.dart` does).
  `String? get _me` → `FirebaseAuth.instance.currentUser?.uid`.
  `DocumentReference<Map<String, dynamic>> _clinic(String t) => FirebaseFirestore.instance.collection('clinics').doc(t);`
- **One-shot reads** (used while building a PDF): `Future<ClinicDocSettings> clinicSettingsOnce()`,
  `Future<DoctorDocProfile?> doctorProfileOnce(String uid)`, `Future<Map<String, dynamic>?> memberOnce(String uid)`
  (reads `clinics/{t}/members/{uid}`), `Future<List<DocTemplate>> templatesOnce()` (builtins + stored),
  `Future<Map<String, dynamic>?> myLegacyProfileOnce()` (reads the signed-in user's own `users/{me}` document —
  the old letterhead fields live there), `Future<List<ClinicMember>> activeDoctorsOnce()`
  (`clinics/{t}/members` where `active == true`, mapped with `ClinicMember.fromMap`, only `kind == MemberKind.doctor`).
  Each: no tenant → defaults/builtins; otherwise `.get()` with `.timeout(const Duration(seconds: 4))`, and on any
  error retry once with `GetOptions(source: Source.cache)`; if that fails too → defaults/builtins. Never throw.
- **Streams** for screens (Riverpod, in the same file):
  ```dart
  final clinicDocSettingsProvider = StreamProvider<ClinicDocSettings>((ref) { ref.watch(clinicAccessProvider); … });
  final myDocProfileProvider = StreamProvider<DoctorDocProfile?>((ref) { … });
  final docTemplatesProvider = StreamProvider<List<DocTemplate>>((ref) { … }); // builtins + stored
  ```
  On stream errors emit the defaults instead of failing:
  `.transform(StreamTransformer.fromHandlers(handleError: (e, st, sink) => sink.add(<defaults>)))`.
- `List<DocTemplate> visibleTemplates(List<DocTemplate> all, ClinicDocSettings s, {DocKind? kind})`:
  builtins + `scope == clinic` + (`scope == doctor && ownerUid == _me`, unless `s.lockTemplates`);
  when `kind` is given, only `appliesTo(kind)`. When `lockTemplates` is on and at least one clinic template applies
  to the kind, hide builtins.
- `Future<DocTemplate> resolveTemplate(DocKind kind, {String? issuingDoctorUid, String? explicitId})` — order from D4.
  A found template that is `tooNew` → `builtinById('builtin.classic')` (the context builder adds the warning).
- Writes (each sets `updatedAt: DateTime.now().millisecondsSinceEpoch` and `updatedByUid: _me`):
  - `saveClinicSettings(ClinicDocSettings s)` → `doc_settings/clinic` (`set`, merge false).
  - `saveMyProfile(DoctorDocProfile p)` → `doc_doctors/{_me}`; throw `StateError` if `p.uid != _me`.
  - `saveTemplate(DocTemplate t, {required int loadedUpdatedAt, bool force = false})` → new id
    (`doc_templates` `.doc().id`) when `t.isBuiltin` or `t.id` is empty; otherwise read the stored doc first and,
    unless `force`, throw `DocTemplateConflict` (a small exception class) if its `updatedAt != loadedUpdatedAt`.
    Returns the saved template (with id and new updatedAt).
  - `deleteTemplate(DocTemplate t)` → delete the doc, then remove its id from `defaults` in clinic settings
    (if the user has `settings`) and in my profile.
  - `setDefault(DocKind kind, String templateId, {required bool forClinic})` → updates `defaults[kind.name]`
    in clinic settings (`forClinic`) or my profile.

## T8. Security rules (+ rule tests)

**`firestore.rules`** — inside `match /clinics/{clinicId} {`, after the `match /roles/{roleId} {…}` block, add:

```
      // ---- Printable documents (handoff/antigravity_documents_pdf.md) ----
      // Clinic print details: everyone in the clinic reads them (staff print
      // bills too); only people with the settings permission edit them.
      match /doc_settings/{docId} {
        allow read: if clinicAllows(clinicId, 'member');
        allow write: if clinicAllows(clinicId, 'settings');
      }

      // A doctor's details for documents (registration no., signature).
      // Only that doctor may change them, so nobody can swap a signature.
      match /doc_doctors/{uid} {
        allow read: if clinicAllows(clinicId, 'member');
        allow create, update: if isSelf(uid)
          && clinicAllows(clinicId, 'member')
          && request.resource.data.uid == uid;
        allow delete: if isSelf(uid);
      }

      // Templates: clinic ones need 'settings'; a doctor's own ones only
      // their owner may write. Scope and owner never change.
      match /doc_templates/{templateId} {
        allow read: if clinicAllows(clinicId, 'member');
        allow create: if clinicAllows(clinicId, 'member')
          && request.resource.data.scope in ['clinic', 'doctor']
          && (request.resource.data.scope == 'clinic'
            ? clinicAllows(clinicId, 'settings')
            : request.resource.data.ownerUid == request.auth.uid);
        allow update: if clinicAllows(clinicId, 'member')
          && request.resource.data.scope == resource.data.scope
          && request.resource.data.ownerUid == resource.data.ownerUid
          && (resource.data.scope == 'clinic'
            ? clinicAllows(clinicId, 'settings')
            : resource.data.ownerUid == request.auth.uid);
        allow delete: if clinicAllows(clinicId, 'member')
          && (resource.data.scope == 'clinic'
            ? clinicAllows(clinicId, 'settings')
            : resource.data.ownerUid == request.auth.uid);
      }

      // Document numbers: a counter only ever goes up by one.
      match /doc_counters/{counterId} {
        allow read: if clinicAllows(clinicId, 'member');
        allow create: if (clinicAllows(clinicId, 'billing')
            || clinicAllows(clinicId, 'clinical.edit'))
          && request.resource.data.keys().hasOnly(['last', 'updatedAt'])
          && request.resource.data.last == 1;
        allow update: if (clinicAllows(clinicId, 'billing')
            || clinicAllows(clinicId, 'clinical.edit'))
          && request.resource.data.keys().hasOnly(['last', 'updatedAt'])
          && request.resource.data.last == resource.data.last + 1;
        allow delete: if false;
      }
```

**`storage.rules`** — directly after the `match /doctors/{doctorId}/clinic/branding/{allPaths=**} {…}` block, add:

```
    // A doctor's own signature, stamp and template images. Only that doctor
    // writes; everyone in the clinic reads them (to print documents).
    match /doctors/{doctorId}/doctor-files/{uid}/{allPaths=**} {
      allow read: if can(doctorId, 'member');
      allow create, update: if request.auth != null
        && request.auth.uid == uid
        && can(doctorId, 'member')
        && withinSizeLimit()
        && isAllowedMedicalType();
      allow delete: if request.auth != null
        && request.auth.uid == uid
        && can(doctorId, 'member');
    }
```

**Rule tests** — add cases to `tests/firestore-rules/firestore.rules.test.js` and
`tests/storage-rules/storage.rules.test.js`, following the existing setup in those files (same helpers,
same seeded clinic/member docs). Cases:
- member reads `doc_settings/clinic` ✔; receptionist without `settings` writes it ✘; admin with `settings` ✔.
- doctor A writes `doc_doctors/A` ✔; doctor B writes `doc_doctors/A` ✘; owner writes `doc_doctors/A` ✘;
  doctor A writes `doc_doctors/A` with `uid: 'B'` ✘.
- doctor A creates a `doctor` template with `ownerUid: A` ✔, with `ownerUid: B` ✘; receptionist creates a
  `clinic` template ✘; admin ✔; doctor B updates A's template ✘; anyone changes `scope` or `ownerUid` ✘.
- counter: create with `last: 1` ✔, `last: 5` ✘; update 4→5 ✔, 4→6 ✘, 4→3 ✘; extra key ✘; delete ✘;
  receptionist with only `schedule` ✘.
- storage: doctor A uploads `doctors/{c}/doctor-files/A/signature.png` ✔; doctor B uploads there ✘; member reads ✔.
Run them the way the files' header comments / `package.json` say (with the emulators). If the emulators
cannot start on this machine, write the tests anyway, skip running, and say so in the report.

## T9. Branding images (process, upload, cache)

1. In `lib/core/services/medical_storage_service.dart`:
   - add `clinicStamp('clinic-stamp')` to `enum ClinicBrandingKind`.
   - add a method next to `uploadClinicBranding`:
     ```dart
     /// A clinic document image (template picture, letterhead background):
     /// doctors/{clinic}/clinic/branding/templates/{templateId}/{name}.png
     Future<StoredFile> uploadClinicTemplateImage({required String doctorId, required String templateId, required String name, required Uint8List png});

     /// One doctor's own image (signature, stamp, template picture):
     /// doctors/{clinic}/doctor-files/{uid}/{relativePath}.png
     Future<StoredFile> uploadDoctorFile({required String doctorId, required String uid, required String relativePath, required Uint8List png});
     ```
     Both: `_requireSignedInAs(doctorId)`, content type `image/png`, upload with the same private `_put(...)`
     used by `uploadClinicBranding` (metadata `{'doctorId': doctorId, 'category': 'branding'}`).
     `uploadDoctorFile` also throws `StateError` when `uid != FirebaseAuth.instance.currentUser?.uid`.
2. Create `lib/core/pdf/data/branding_image_store.dart`:
   ```dart
   /// Turns a picked file into a clean PNG: decode (JPG/PNG/WebP), apply
   /// EXIF rotation, shrink so the longer side is at most [maxSide], and
   /// optionally make the paper white transparent (signature photos).
   /// Throws FormatException('Use a JPG, PNG or WebP picture') when it can't decode.
   Future<Uint8List> prepareBrandingImage(Uint8List raw, {required int maxSide, bool cleanBackground = false});
   ```
   Do the work in `compute(...)` with a top-level function (package `image`, already a dependency):
   `img.decodeImage` → `img.bakeOrientation` → if longer side > maxSide `img.copyResize(width: …)` or `(height: …)`
   → if `cleanBackground`: convert to 4 channels (`image.convert(numChannels: 4)` when `numChannels < 4`) and for
   every pixel compute `lum = 0.299*r + 0.587*g + 0.114*b`; `lum >= 215` → `a = 0`; `160 < lum < 215` →
   `a = ((215 - lum) / 55 * 255).round()`; else keep → `img.encodePng`. Refuse input over 15 MB before decoding.
   Max sides: logo 1200, signature 1000, stamp 800, template picture 1600, letterhead background 2480.

   And a class:
   ```dart
   class BrandingImageStore {
     static final instance = BrandingImageStore._();
     /// Bytes for [path] when they hash to [sha] (sha256, hex). Order:
     /// memory → device cache file → download (then cached). Null when
     /// missing, offline and not cached, or the hash doesn't match.
     Future<BrandingImageResult> load(String path, String sha);
     /// Puts freshly uploaded bytes straight into the caches.
     Future<void> remember(String sha, Uint8List bytes);
   }
   enum BrandingImageProblem { none, notDownloaded, mismatch }
   class BrandingImageResult { final Uint8List? bytes; final BrandingImageProblem problem; … }
   ```
   Cache file: `<getApplicationSupportDirectory()>/doc_assets/<sha>.png` (skip on web; memory only).
   Download: `FirebaseStorage.instance.ref(path).getData(15 * 1024 * 1024)` with a 10 s timeout.
   Hash: `sha256.convert(bytes).toString()` (`package:crypto`). Empty `path` or `sha` → `(null, none)`.
3. Add a helper used by Settings later: `String sha256Hex(Uint8List b)` in the same file.

## T10. Document numbers

Create `lib/core/pdf/data/doc_numbering.dart` with `class DocNumbering { static Future<String> next(DocKind kind, DateTime date) }`:

```dart
static Future<String> next(DocKind kind, DateTime date) async {
  final settings = await DocRepository.instance.clinicSettingsOnce();
  final prefix = settings.prefixFor(kind);
  final fy = financialYear(date);
  final tenant = DocRepository.instance.tenantOrNull; // expose the private getter as a public one
  if (tenant == null) return _offline(prefix, kind, fy);
  final ref = FirebaseFirestore.instance
      .collection('clinics').doc(tenant)
      .collection('doc_counters').doc('${kind.name}_$fy');
  try {
    final n = await FirebaseFirestore.instance.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final last = (snap.data()?['last'] as num?)?.toInt() ?? 0;
      tx.set(ref, {'last': last + 1, 'updatedAt': FieldValue.serverTimestamp()});
      return last + 1;
    }).timeout(const Duration(seconds: 6));
    return '$prefix-$fy/${n.toString().padLeft(4, '0')}';
  } catch (_) {
    return _offline(prefix, kind, fy);
  }
}
```

`_offline`: SharedPreferences; `docs.deviceCode` = 2 random uppercase letters (create once, keep forever);
`docs.localSeq.<kind>.<fy>` += 1; return `'$prefix-$fy/$code${seq.toString().padLeft(3, '0')}'`.

Also `static bool isValidPrefix(String p) => RegExp(r'^[A-Za-z0-9]{1,5}$').hasMatch(p);`

## T11. Context (the values a PDF is filled with)

Create `lib/core/pdf/render/doc_context.dart`:

- `DocClinicInfo` (all strings default `''`, plus `bool gstEnabled`, `bool roundOff`): name, tagline, address,
  phone, email, website, timings, regNo, gstin, footerText, termsText, upiId, upiName.
- `DocDoctorInfo`: uid, name, qualification, specialty, regNo, regCouncil, phone, email, `bool active = true`.
- `DocImages`: `Uint8List? logo, signature, stamp, clinicStamp, background`, `Map<String, Uint8List> custom`
  (by sha), and `Uint8List? forBlock(DocBlock b)` → by `imageRole` (`custom` → `custom[b.imageSha]`).
- `enum DocFix { clinicDetails, myDetails, none }`; `class DocWarning { final String message; final DocFix fix; }`.
- `DocContext` with: `PdfMedicalDocumentData data`, `DocClinicInfo clinic`, `DocDoctorInfo? doctor`,
  `List<DocDoctorInfo> doctors` (active clinic doctors, for `doctorList`), `DocImages images`, `bool sample`,
  `List<DocWarning> warnings`, `Map<String, Uint8List> scriptImages` (Phase 3; default empty).
  Methods:
  ```dart
  String _join(List<String> parts) =>
      parts.map((s) => s.trim()).where((s) => s.isNotEmpty).join(' · ');

  /// The text for a field key ('' when unknown or empty). Page values
  /// come from the PDF page being drawn.
  String field(String key, {int page = 1, int pages = 1}) {
    final c = clinic;
    final d = doctor;
    final p = data.patient;
    String reg(String no) => no.trim().isEmpty ? '' : 'Reg. No. ${no.trim()}';
    return pdfSafe(switch (key) {
      'clinic.name' => c.name,
      'clinic.tagline' => c.tagline,
      'clinic.address' => c.address,
      'clinic.phone' => c.phone,
      'clinic.email' => c.email,
      'clinic.website' => c.website,
      'clinic.timings' => c.timings,
      'clinic.regNo' => reg(c.regNo),
      'clinic.gstin' => c.gstin.trim().isEmpty ? '' : 'GSTIN: ${c.gstin.trim()}',
      'clinic.contactLine' => _join([c.phone, c.email, c.website]),
      'clinic.addressContact' =>
        _join([c.address.replaceAll('\n', ', '), c.phone, c.email]),
      'doctor.name' => d?.name ?? '',
      'doctor.qualification' => d?.qualification ?? '',
      'doctor.specialty' => d?.specialty ?? '',
      'doctor.regNo' => d == null ? '' : _join([reg(d.regNo), d.regCouncil]),
      'doctor.nameQual' => d == null ? '' : _join([d.name, d.qualification]),
      'doctor.specReg' => d == null ? '' : _join([d.specialty, reg(d.regNo)]),
      'doctor.phone' => d?.phone ?? '',
      'doctor.email' => d?.email ?? '',
      'doc.title' => data.titleFor(c.gstEnabled),
      'doc.number' => data.documentNumber,
      'doc.numberLine' =>
        data.documentNumber.isEmpty ? '' : 'No. ${data.documentNumber}',
      'doc.date' => formatDocDate(data.documentDate),
      'doc.dateLine' => 'Date: ${formatDocDate(data.documentDate)}',
      'doc.status' => _status(),
      'patient.name' => p.fullName,
      'patient.ageSex' => p.ageGender ?? '',
      'patient.phone' => p.phone ?? '',
      'patient.line' => _join([p.fullName, p.ageGender ?? '', p.phone ?? '']),
      'page.number' => pages > 1 ? 'Page $page of $pages' : '',
      'footer.text' => c.footerText,
      _ => '',
    });
  }

  /// Fills {{field.key}} placeholders in a text block.
  String fill(String text, {int page = 1, int pages = 1}) => text.replaceAllMapped(
    RegExp(r'\{\{([a-zA-Z.]+)\}\}'),
    (m) => field(m[1]!, page: page, pages: pages),
  );

  /// upi://pay link for the invoice balance; null when there is nothing to pay or no UPI ID.
  String? upiUri() { … }   // see below
  ```
  `_status()`: only for `PdfInvoiceDocumentData`: balance > 0 → `'Balance due ${formatPaise(toPaise(balance))}'`,
  else `'PAID'`. `upiUri()`: only for invoices, `clinic.upiId` not empty, balance in paise > 0; query parameters
  `pa` (UPI id), `pn` (upiName, else clinic name), `am` (balance, 2 decimals), `cu=INR`, `tn` = `Bill <number>`,
  each value `Uri.encodeComponent`-ed: `upi://pay?pa=…&pn=…&am=…&cu=INR&tn=…`.

Create `lib/core/pdf/render/doc_context_builder.dart`:

```dart
/// The uid to record as signer: the signed-in user, but only when they
/// are the issuing doctor (and a doctor). Null otherwise.
String? docSignerFor(String? issuingDoctorUid) { … }

/// Who a new document is for when nobody picked: the signed-in doctor;
/// a solo user (no clinic access) is their own doctor; staff → null.
String? defaultIssuingDoctorUid() { … }

Future<DocContext> buildDocContext({
  required PdfMedicalDocumentData data,
  required DocTemplate template,
  bool sample = false,
}) async { … }
```

`buildDocContext` steps (never throws; anything that fails becomes a warning):
0. **Old letterhead** (so existing users see their details without re-typing): `legacy` = `data.letterheadConfig`
   when it has a clinic or doctor name; otherwise
   `DoctorLetterheadConfig.fromProfileData(await myLegacyProfileOnce(), FirebaseAuth.instance.currentUser)`.
   `me` = signed-in uid; `iAmOwner` = `me == tenant` (or no tenant).
1. `settings = clinicSettingsOnce()`. Build `DocClinicInfo` from it; for each **empty** text field fall back to
   `legacy` (clinicName, tagline, clinicAddress, clinicPhone, clinicEmail, footerDisclaimer) — **only when
   `iAmOwner`** or when `data.letterheadConfig` was given by the caller (a member's own profile is not the clinic's).
2. `uid = data.issuingDoctorUid ?? defaultIssuingDoctorUid()`. If `uid != null`: `prof = doctorProfileOnce(uid)`,
   `member = memberOnce(uid)`. Name: `prof.nameOnDocs` → `member['name']` → (only if `uid == me`) `legacy.doctorName`.
   Same pattern for qualification (`member['qualification']` → `legacy.qualifications`), regNo
   (`member['registrationNo']` → `legacy.registrationNumber`), specialty (`member['specialty']` → `legacy.specialty`).
   `active = member == null || member['active'] != false`. If every value is empty → `doctor = null`.
3. `doctors` = `activeDoctorsOnce()` mapped to `DocDoctorInfo` (use each one's `doc_doctors` profile when present).
   Max 4, by name. Only when the template has a visible `doctorList` block — skip the query otherwise.
4. Images via `BrandingImageStore.instance.load(path, sha)`:
   - logo, clinic stamp: from settings. Background: from `template.background`. Custom: every `image` block with
     `imageRole == custom`.
   - signature and stamp: from `prof`, **only if** `doctor != null && doctor.active && data.signedByUid == doctor.uid`.
   - For each result with a problem add a warning: notDownloaded → "Logo not downloaded yet — connect to the
     internet once" (use the right name); mismatch → "Your signature file was changed outside CruDoc and was left
     out. Upload it again in Settings › Clinic & documents." (fix: myDetails or clinicDetails).
5. Warnings for missing details (only when not `sample`):
   - `clinic.name` empty → "Add your clinic name" (clinicDetails).
   - kind is prescription / certificate / referral and (`doctor == null` or `doctor.regNo` empty) →
     "Add your registration number — it must be on prescriptions and certificates" (myDetails).
   - `template.tooNew` → "Update CruDoc to use the template ‘<name>’" (none).
   - any text in patient name / clinic name / clinic address / doctor name with `needsScriptFallback` (until
     Phase 3) → "Some Indian-language text may not print correctly yet" (none).
6. Return the `DocContext`.

## T12. Renderer

Create `lib/core/pdf/render/doc_renderer.dart`, `lib/core/pdf/render/doc_body.dart`,
`lib/core/pdf/render/receipt_layout.dart`.

**`doc_renderer.dart`:**

```dart
class DocRenderer {
  DocRenderer(this.t, this.ctx, this.fonts, {this.forPrint = false});

  final DocTemplate t;
  final DocContext ctx;
  final PdfFonts fonts;

  /// True for the copy sent to the printer: a letterhead background that
  /// is already printed on the paper is left out.
  final bool forPrint;

  static const mm = PdfPageFormat.mm;

  static Future<Uint8List> render(
    DocTemplate t,
    DocContext ctx, {
    bool forPrint = false,
  }) async {
    final fonts = await PdfFonts.load();
    return DocRenderer(t, ctx, fonts, forPrint: forPrint)._build();
  }

  PdfColor color(String ref) => PdfColor.fromInt(t.style.resolve(ref));

  pw.TextStyle style(double pt, {bool bold = false, String color = 'text'}) =>
      pw.TextStyle(
        font: bold ? fonts.bold : fonts.regular,
        fontSize: pt,
        color: this.color(color),
      );

  Future<Uint8List> _build() async {
    final doc = pw.Document(
      title: ctx.data.previewTitle,
      author: ctx.doctor?.name.isNotEmpty == true
          ? ctx.doctor!.name
          : ctx.clinic.name,
      creator: 'CruDoc',
      subject: ctx.data.type.title,
    );
    if (t.paper.isRoll) {
      doc.addPage(ReceiptLayout(this).page());
    } else {
      final m = t.paper.margins;
      doc.addPage(
        pw.MultiPage(
          maxPages: 60,
          pageTheme: pw.PageTheme(
            pageFormat: t.paper.toPdf(),
            margin: pw.EdgeInsets.fromLTRB(
              m.left * mm, m.top * mm, m.right * mm, m.bottom * mm),
            theme: fonts.theme(),
            buildBackground: _background,
            buildForeground: _watermark,
          ),
          header: (c) => zone(DocZone.header, c.pageNumber, c.pagesCount),
          footer: (c) => zone(DocZone.footer, c.pageNumber, c.pagesCount),
          build: (c) => DocBody(this).build(),
        ),
      );
    }
    return doc.save();
  }
```

Then (same class):

- `pw.Widget zone(DocZone z, int page, int pages)`: `heightMm = t.zoneHeight(z)`; if `<= 0` return
  `pw.SizedBox()`. Otherwise a `pw.SizedBox(width: t.paper.contentWidthMm * mm, height: heightMm * mm,
  child: pw.Stack(children: [...]))` with, for every block in this zone that is not hidden and whose `showOn`
  matches (`all`; `first` → page == 1; `last` → page == pages; `notFirst` → page > 1) and whose widget is not
  null: `pw.Positioned(left: b.x * mm, top: b.y * mm, child: pw.SizedBox(width: b.w * mm, height: b.h * mm, child: widget))`.
  **The zone always has its full height, even when blocks are hidden**, so the body never jumps.
- `pw.Widget? block(DocBlock b, int page, int pages)`:
  - `field` → `text = ctx.field(b.field, page: page, pages: pages)`; empty → null; else `textBox(b, text, multiline: docFieldDef(b.field)?.multiline ?? false)`.
  - `text` → `ctx.fill(b.text, …)`; empty after trim → null; else `textBox(b, text, multiline: true)`.
  - `image` → `bytes = ctx.images.forBlock(b)`; null → null; else
    `pw.Opacity(opacity: b.opacity, child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain, alignment: align(b)))`.
  - `line` → `pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Container(width: b.w * mm, height: max(b.strokePt, 0.3), color: color(b.color)))`.
  - `box` → `pw.Container(decoration: pw.BoxDecoration(color: b.fill == 'none' ? null : color(b.fill), border: b.strokePt > 0 ? pw.Border.all(color: color(b.color), width: b.strokePt) : null, borderRadius: b.radiusMm > 0 ? pw.BorderRadius.circular(b.radiusMm * mm) : null))`.
  - `qr` → `data = b.qr == 'upi' ? ctx.upiUri() : ctx.fill(b.qr)`; null/empty → null; else
    `pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: data, drawText: false, color: color(b.color))`.
  - `doctorList` → `ctx.doctors` empty → null; else a `pw.Row` of up to 4 `pw.Expanded` columns (aligned by `b.align`):
    name (bold, `b.fontPt`), qualification (`b.fontPt - 1`, muted), `Reg. No. …` (`b.fontPt - 1.5`, muted). Empty lines skipped.
- `pw.Widget textBox(DocBlock b, String text, {required bool multiline})`:
  ```dart
  final st = style(b.fontPt, bold: b.bold, color: b.color);
  final lineMm = b.fontPt * 0.3528 * 1.3;
  final maxLines = (b.h / lineMm).floor();
  if (!multiline || maxLines <= 1) {
    return pw.Align(
      alignment: align(b),
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: align(b),
        child: pw.Text(text.replaceAll('\n', ', '), style: st, maxLines: 1),
      ),
    );
  }
  return pw.Align(
    alignment: align(b),
    child: pw.Text(text, style: st, textAlign: textAlign(b), maxLines: maxLines, overflow: pw.TextOverflow.clip),
  );
  ```
  `align(b)` → `topLeft/topCenter/topRight`; `textAlign(b)` → `left/center/right`.
- `_background(pw.Context c)`: `bytes = ctx.images.background`, `bg = t.background`; null, or `forPrint && !bg.printOnPaper`
  → `pw.SizedBox()`; else `pw.FullPage(ignoreMargins: true, child: pw.Opacity(opacity: bg.opacity, child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill)))`.
- `_watermark(pw.Context c)`: word = `ctx.sample ? 'SAMPLE'` : cancelled invoice ? `'CANCELLED'` : none.
  `pw.FullPage(ignoreMargins: true, child: pw.Center(child: pw.Transform.rotate(angle: 0.6, child: pw.Text(word, style: pw.TextStyle(font: fonts.bold, fontSize: 78, color: const PdfColor(0.85, 0.1, 0.1, 0.16))))))`
  (grey `PdfColor(0.4, 0.4, 0.4, 0.14)` for SAMPLE).
- Catch `pw.TooManyPagesException` in `render` and rethrow as `StateError('This document is too long to print (over 60 pages).')`.

**`doc_body.dart`** — `class DocBody { DocBody(this.r); final DocRenderer r; List<pw.Widget> build() }`:
`build()` walks `r.t.bodyFor(r.ctx.kind)`; for each **visible** section calls its builder and adds the returned
widgets (empty list = nothing). Move the look from the old `lib/core/pdf/templates/medical_document_pdf_builder.dart`
and `letterhead_pdf_template.dart` (patient summary box, section title with accent bar, tables) into these
builders, but: every font size × `r.t.style.fontScale`, every colour from `r.t.style`, Geist via `r.style(...)`.

Helpers to write first:
```dart
double pt(double v) => v * r.t.style.fontScale;

List<pw.Widget> heading(String title) => [ /* accent bar 3×12 pt + title 10.5 pt bold, top 12, bottom 6 */ ];

/// Splits long text so MultiPage can break it across pages.
List<pw.Widget> paragraphs(String text, pw.TextStyle st) {
  final out = <pw.Widget>[];
  for (final para in pdfSafe(text).split('\n')) {
    var rest = para;
    while (rest.length > 1200) {
      var cut = rest.lastIndexOf(' ', 1200);
      if (cut < 600) cut = 1200;
      out.add(pw.Text(rest.substring(0, cut), style: st));
      rest = rest.substring(cut).trimLeft();
    }
    out.add(rest.isEmpty ? pw.SizedBox(height: 4) : pw.Text(rest, style: st));
  }
  return out;
}

/// heading + paragraphs, or nothing when [text] is blank.
List<pw.Widget> textSection(String title, String? text) => …;
```

Sections (data classes are in T13):
- `meta`: a row — left `ctx.field('doc.title')` (13 pt bold accent); right column `No. …` / `Date: …` (9 pt). Then 8 pt gap.
- `patient`: the soft rounded box with accent bar from `letterhead_pdf_template.dart` (`patientSummary`), using
  `patient.fullName` (or `Patient`), age/sex, phone. **No patient id.**
- `items` (invoice): `pw.TableHelper.fromTextArray` placed **directly** in the list (not inside a Container).
  Columns: `#`, `Description` (name; `note` on a second line), `Qty`, `Rate`, then `Tax %` and `Tax` **only if any
  item has tax**, `Amount`. Money via `formatPaise(toPaise(...))`. Header row: accent fill, white bold text.
  `headerCount: 1`. Numbers right-aligned. Rows with empty description skipped.
- `totals`: right-aligned box 75 mm wide: Subtotal; tax lines when tax > 0 — if `clinic.gstEnabled`:
  `CGST` and `SGST` each half of the tax (put the odd paisa on CGST), else one `Tax` line; `Discount` (− …) when > 0;
  `Round off` when ≠ 0; `Total` (bold, accent). All maths in paise from `PdfMoneyTotals` (`toPaise`).
- `words`: only when `r.t.options.amountInWords`: `Amount in words: ${rupeesInWords(totalPaise)}` (8.5 pt muted).
- `payment`: `Received ${formatPaise(paid)} by ${mode}` (when paid > 0; drop "by …" if mode empty);
  `Balance due ${formatPaise(balance)}` bold when > 0; else `Paid in full`.
- `upi`: only when `r.t.options.upiQr` and `ctx.upiUri() != null`: row of a 26 mm QR + "Scan to pay ₹… with any UPI app"
  and the UPI id.
- `notes`: `textSection('Notes', data.notes)`. `terms` (invoice only): `textSection('Terms', clinic.termsText)`.
- Prescription: `vitals`, `complaints` ("Complaints"), `diagnosis`, `investigations`, `advice`, `followUp`
  ("Follow-up") via `textSection`; `rx`: heading "Rx" + table `#`, `Medicine`, `Dose`, `When`, `Duration`,
  `Instructions`; medicine names `toUpperCase()` when `options.medicinesInCapitals`.
- Referral: `recipient` → heading "To" + recipient; `reason` ("Reason for referral"); `findings`
  ("Clinical findings", or "Treatment summary" with `reply` text when `isReply`); `question` ("Requested");
  `teeth` ("Teeth"). Report: `sections` → for each non-empty section: heading(title) + paragraphs.
  Certificate: `certificate` → paragraphs of `body` at `pt(11)` with `lineSpacing: 3`.
- `signature` (exact behaviour):
  ```dart
  List<pw.Widget> signature() {
    final ctx = r.ctx;
    final d = ctx.doctor;
    final mode = ctx.kind == DocKind.invoice
        ? r.t.options.invoiceSignature
        : InvoiceSignature.doctor;
    if (mode == InvoiceSignature.none) return const [];
    Uint8List? image;
    Uint8List? stamp;
    var line1 = '';
    var line2 = '';
    switch (mode) {
      case InvoiceSignature.clinicStamp:
        image = ctx.images.clinicStamp;
        line1 = 'Authorised signatory';
        line2 = ctx.clinic.name;
      case InvoiceSignature.line:
        line1 = 'Authorised signatory';
      case InvoiceSignature.doctor:
      case InvoiceSignature.none:
        image = ctx.images.signature; // null unless allowed (context builder)
        stamp = ctx.images.stamp;
        line1 = d?.name ?? '';
        line2 = d == null ? '' : [d.qualification, d.regNo.isEmpty ? '' : 'Reg. No. ${d.regNo}']
            .where((s) => s.trim().isNotEmpty).join(' · ');
        if (line1.isEmpty) line1 = 'Authorised signatory';
    }
    // right-aligned 64 mm column: 18 mm tall row [stamp?, signature image?]
    // (both BoxFit.contain, aligned bottom-right), a 0.6 pt border-colour line,
    // line1 (9.5 pt bold), line2 (7.5 pt muted, centred). 14 pt space above.
    …
  }
  ```

**`receipt_layout.dart`** (80 mm roll, invoices only): `class ReceiptLayout { ReceiptLayout(this.r); pw.Page page() }`
returning `pw.Page(pageFormat: r.t.paper.toPdf(), theme: r.fonts.theme(), build: (_) => pw.Column(...))` with,
centred, 8 pt unless noted: logo (max 18 mm tall, if any), clinic name 11 pt bold, address, phone, GSTIN (when GST on),
a dashed divider (`'-' * 42`), `Bill No` / `Date` row, patient name, one row per item (name, then
`qty × rate` left and amount right), divider, Subtotal / tax / discount / round off / **Total** (10 pt bold),
Received / Balance, payment mode, UPI QR 30 mm when there is a balance, footer text, "Thank you".
Non-invoice data → throw `StateError('Receipt paper is for bills only')` (the preview never offers it for other kinds).

## T13. Wire the old models and service to the new engine

1. `lib/core/pdf/models/pdf_document_models.dart`:
   - `PdfMedicalDocumentType` gains `referral` and `certificate` (titles "Referral letter", "Medical certificate";
     file prefixes `crudoc-referral`, `crudoc-certificate`) and `DocKind get kind` (1-to-1 by name).
   - Base class `PdfMedicalDocumentData`: `letterheadConfig` becomes optional, default `DoctorLetterheadConfig.empty`
     (add `static const empty = DoctorLetterheadConfig(clinicName: '', doctorName: '', …all ''…)` to
     `DoctorLetterheadConfig` in `lib/core/utils/doctor_profile_helper.dart`). New optional fields:
     `String? issuingDoctorUid`, `String? signedByUid`, `String? templateId`. New getter `DocKind get kind => type.kind;`
     and method `String titleFor(bool gst) => type.title.toUpperCase();`.
   - `PdfInvoiceLineItem`: add `double taxPercent = 0`, `String note = ''`.
   - `PdfMoneyTotals`: add `double roundOff = 0` (optional).
   - `PdfInvoiceDocumentData`: add `bool cancelled = false`; override `titleFor(gst) => gst ? 'TAX INVOICE' : 'INVOICE'`.
   - `PdfMedicalReportDocumentData`: override `titleFor` → `reportTitle` upper-cased, or `MEDICAL REPORT` when blank.
   - New `PdfReferralDocumentData` (type referral): `required String recipient`, `String reason = ''`,
     `String findings = ''`, `String question = ''`, `String teeth = ''`, `String urgency = ''`,
     `bool isReply = false`, `String reply = ''`; `titleFor` → `isReply ? 'REFERRAL REPLY' : 'REFERRAL LETTER'`.
   - New `PdfCertificateDocumentData` (type certificate): `required String title`, `required String body`;
     `titleFor` → `title.toUpperCase()`.
   - Subclasses pass the new optional fields through with `super.` parameters.
2. `lib/core/utils/doctor_profile_helper.dart` → `DoctorLetterheadConfig.fromProfileData`: replace **every made-up
   fallback** (`'CruDoc Multi-Speciality Clinic'`, `'MBBS, MD (Medicine)'`, `'MMC-2024/98765'`,
   `'Plot 42, Sunrise Healthcare Complex, Mumbai - 400001'`, `'+91 91520 35527'`, `'care@crudoc.com'`,
   `'Excellence in Healthcare & Patient Wellbeing'`, `'This digital document is generated by CruDoc Practice Management System.'`)
   with `''` (keep the `user?.phoneNumber` / `user?.email` fallbacks — those are real).
3. `lib/core/pdf/services/medical_pdf_service.dart` → replace its body with:
   ```dart
   class RenderedDoc {
     const RenderedDoc({required this.bytes, required this.template, required this.warnings});
     final Uint8List bytes;
     final DocTemplate template;
     final List<DocWarning> warnings;
   }

   class MedicalPdfService {
     const MedicalPdfService();

     Future<RenderedDoc> render(
       PdfMedicalDocumentData data, {
       DocTemplate? template,
       bool forPrint = false,
       bool sample = false,
     }) async {
       final t = template ??
           await DocRepository.instance.resolveTemplate(
             data.kind,
             issuingDoctorUid: data.issuingDoctorUid,
             explicitId: data.templateId,
           );
       final ctx = await buildDocContext(data: data, template: t, sample: sample);
       final bytes = await DocRenderer.render(t, ctx, forPrint: forPrint);
       return RenderedDoc(bytes: bytes, template: t, warnings: ctx.warnings);
     }

     /// Kept for older callers.
     Future<Uint8List> generate(PdfMedicalDocumentData data) async =>
         (await render(data)).bytes;
   }
   ```
   Then fix `medical_pdf_preview_screen.dart` so it still compiles (`const MedicalPdfService()`); Phase 2 rewrites it.
4. `lib/core/pdf/templates/pdf_template_theme.dart`: add `referral` and `certificate` cases to `forDocument` (reuse the
   report colours). Keep this file (the radiology report uses it).
5. `lib/core/pdf/services/generated_document_sync.dart`: `referral` and `certificate` → `UploadKind.prescriptionPdf`;
   `report` stays `null`.
6. Delete `lib/core/pdf/templates/letterhead_pdf_template.dart` and
   `lib/core/pdf/templates/medical_document_pdf_builder.dart` once `doc_body.dart` covers them and nothing imports them.
   Delete `lib/core/pdf/services/pdf_asset_loader.dart` if nothing imports it any more.
7. Fix every other compile error `flutter analyze` shows from the enum change (exhaustive `switch`es).

## T14. Sample PDFs + unit tests (the Phase 1 proof)

1. Create `lib/core/pdf/render/doc_samples.dart`: `PdfMedicalDocumentData docSampleData(DocKind kind)` with obviously
   sample values ("Sample Patient", "34 Y / Female", "INV-26-27/0001", 3 bill lines, 3 medicines, …) and
   `DocContext docSampleContext(PdfMedicalDocumentData data, {DocClinicInfo? clinic, DocDoctorInfo? doctor, DocImages images = const DocImages()})`
   with `sample: true`. (Used later by template previews in the app.)
2. Create `test/core/pdf/pdf_text_test.dart`:
   - `rupeesInWords(125050)` == `'Rupees One Thousand Two Hundred Fifty and Fifty Paise Only'`
   - `rupeesInWords(12345678900)` == `'Rupees Twelve Crore Thirty Four Lakh Fifty Six Thousand Seven Hundred Eighty Nine Only'`
   - `rupeesInWords(0)` == `'Rupees Zero Only'`; `rupeesInWords(10000000)` == `'Rupees One Crore Only'`
   - `financialYear(DateTime(2026, 3, 31))` == `'25-26'`; `financialYear(DateTime(2026, 4, 1))` == `'26-27'`
   - `formatPaise(12500000)` == `'₹1,25,000'`; `formatPaise(125050)` == `'₹1,250.50'`
   - `DocTemplate.fromMap(t.id, t.toMap())` round-trips every builtin (compare `toMap()` JSON).
   - `bodyFor` drops unknown section ids and appends missing ones.
3. Create `test/core/pdf/doc_samples_test.dart` (`TestWidgetsFlutterBinding.ensureInitialized()`; no Firebase): for every
   builtin template × every kind it applies to, render `docSampleContext(docSampleData(kind))` with
   `DocRenderer.render`, check the bytes start with `%PDF`, and write them to
   `build/doc_samples/<templateId>_<kind>.pdf`. Also write these edge cases (Classic template):
   `edge_60_items.pdf` (60 bill lines + 3,000-character notes → must be 2+ pages),
   `edge_empty_clinic.pdf` (all clinic/doctor values empty → no crash, header blocks simply absent),
   `edge_cancelled.pdf` (cancelled invoice → CANCELLED watermark), `edge_gst.pdf` (gstEnabled, items with 5% and 18% tax),
   `edge_long_names.pdf` (80-character clinic name and 4-line address), `edge_upi.pdf` (upiId set, balance due → QR shown),
   `edge_print_variant.pdf` (a template with a background image and `printOnPaper: false`, rendered `forPrint: true` →
   no background).

### Phase 1 Checks (run once, at the end)

```
flutter analyze
flutter test test/core/pdf/pdf_text_test.dart
flutter test test/core/pdf/doc_samples_test.dart
```
Then the rules tests (T8). Fix what fails. Then list the files in `build/doc_samples/`.

**GATE 1 — STOP.** Report as described in "Reporting". Claude reviews the PDFs and the rules before Phase 2.

---

# PHASE 2 — Bill flow, preview, every document kind, Settings (T15–T22)

*(Do not start until DO NOW says so.)*

## T15. Invoices keep their lines

1. Create `lib/features/revenue/data/models/invoice_bill.dart`:
   - `InvoiceBillItem { String name; int qty = 1; int ratePaise; double taxPct = 0; String kind = 'treatment' /* treatment | medicine | other */; String note = ''; }`
     with `amountPaise = qty * ratePaise`, `taxPaise = (amountPaise * taxPct / 100).round()`, `toMap`/`fromMap`
     (keys `name, qty, rate, tax, kind, note`).
   - `InvoiceBill { List<InvoiceBillItem> items; int discountPaise = 0; bool roundOff = true; int paidPaise = 0; String paymentMode = ''; String templateId = ''; String signedByUid = ''; }`
     with `String toJson()` (`{"v":1, …}`) and `static InvoiceBill fromJson(String s)` (empty/invalid → `const InvoiceBill()`).
   - `InvoiceTotals.of(InvoiceBill b)` — exactly:
     ```dart
     final subtotal = b.items.fold<int>(0, (s, i) => s + i.amountPaise);
     final tax = b.items.fold<int>(0, (s, i) => s + i.taxPaise);
     final gross = subtotal + tax;
     final discount = b.discountPaise.clamp(0, gross).toInt();
     final net = gross - discount;
     final roundOff = b.roundOff ? (net / 100).round() * 100 - net : 0;
     final grand = net + roundOff;
     final paid = b.paidPaise.clamp(0, grand).toInt();
     // fields: subtotal, tax, discount, roundOff, grand, paid, balance = grand - paid
     ```
2. `lib/features/revenue/data/models/invoice_model.dart`: add `String invoiceNumber = ''`, `String billJson = ''`
   (constructor, copyWith, toMap, fromMap), getters `InvoiceBill get bill => InvoiceBill.fromJson(billJson)`,
   `bool get isCancelled => status.toLowerCase() == 'cancelled'`.
3. `lib/features/revenue/data/services/invoice_local_service.dart`: add both columns to `CREATE TABLE`
   (`invoiceNumber TEXT NOT NULL DEFAULT ''`, `billJson TEXT NOT NULL DEFAULT ''`) and, right after it, add them to
   older tables:
   ```dart
   final cols = {
     for (final r in await db.rawQuery('PRAGMA table_info(invoices)')) r['name'],
   };
   if (!cols.contains('invoiceNumber')) {
     await db.execute("ALTER TABLE invoices ADD COLUMN invoiceNumber TEXT NOT NULL DEFAULT ''");
   }
   if (!cols.contains('billJson')) {
     await db.execute("ALTER TABLE invoices ADD COLUMN billJson TEXT NOT NULL DEFAULT ''");
   }
   ```
4. `lib/features/revenue/repo/invoice_repo.dart`:
   - `_encryptMap`/`_decryptMap`: also encrypt/decrypt `billJson` with `FieldCipher` (like `service`). `invoiceNumber`
     stays plain.
   - New `Future<InvoiceModel> createBilledInvoice({required String patientName, String? patientId, required InvoiceBill bill, required DateTime date, DateTime? dueDate, String notes = '', String? attendingDoctorUid, String? invoiceNumber})`:
     number = given (trimmed, non-empty) or `await DocNumbering.next(DocKind.invoice, date)`; if a number was given,
     refuse a duplicate (`invoices` where `doctorId == tenant` and `invoiceNumber == n`, limit 1 → throw
     `StateError('Invoice number $n is already used')`); `amount` = `totals.grand / 100`; `status` = balance 0 →
     `'Paid'`, else due date before today → `'Overdue'`, else `'Pending'`; `service` = the same summary text the dialog
     builds today ("Treatments: … | Medicines: …"); `bill` stored with `signedByUid = docSignerFor(attendingDoctorUid) ?? ''`
     and `templateId` = the resolved default template id for invoices. Same attending/creator logic as `createInvoice`.
     Writes Firestore (encrypted) + local, returns the model.
   - `updateBilledInvoice(InvoiceModel inv, {…same inputs…})` — same id and number (number may change, same duplicate check),
     recomputes amount/status, `updatedAt` now. Refuse if `inv.isCancelled`.
   - `cancelInvoice(String id)` → `status: 'Cancelled'`, `updatedAt`. (`deleteInvoice` stays for old callers; the bill
     screens stop offering it.)
   - `setInvoiceTemplate(InvoiceModel inv, String templateId)` → rewrites `billJson` with the new `templateId`.
   - Keep `createInvoice` working as before (old callers).
5. Create `lib/features/revenue/data/invoice_pdf_mapper.dart`:
   `PdfInvoiceDocumentData invoicePdfData(InvoiceModel inv, {Patient? patient})`. When `inv.bill.items` is empty (old
   invoices) use one line `InvoiceBillItem(name: inv.service, ratePaise: toPaise(inv.amount))`, `roundOff: false`,
   `paidPaise` = amount when `inv.isPaid` else 0. Totals from `InvoiceTotals.of`. Patient snapshot: name from invoice;
   phone/email/age-sex from `patient` when given (`'${patient.age} Y / ${patient.gender}'`, gender omitted when blank).
   `documentNumber` = `inv.invoiceNumber` or `inv.id`; `issuingDoctorUid` = attending uid or null; `signedByUid`,
   `templateId` from the bill (empty → null); `cancelled: inv.isCancelled`.
6. Revenue totals must skip cancelled invoices: search `lib/features/revenue`, `lib/features/dashboard`,
   `lib/features/mobile` for places that sum or count `InvoiceModel`s (`.amount`, `isPaid`, `isPending`, `isOverdue`)
   and skip `isCancelled` ones. Add a grey "Cancelled" style wherever an invoice status pill is drawn.

## T16. The bill form (Vyapar-simple)

File: `lib/features/revenue/presentation/desktop_create_invoice_dialog.dart` (used on phone and PC).

1. `_TreatmentItem` and `_MedicineItem` get `int qty` (default 1) and `double taxPct` (default 0). Each item row
   shows a small Qty field (width 56, digits only, 1–999) before the price; a `Tax %` field only when the clinic has
   GST on (load `DocRepository.instance.clinicSettingsOnce()` in `initState` into `_docSettings`; until it loads, GST
   is off). Voice/scan prefill keeps working (qty 1).
2. Build an `InvoiceBill` from the form (`_bill` getter) and take **all** totals from `InvoiceTotals.of(_bill)`
   (replace `_treatmentSubtotal`, `_medicineSubtotal`, `_totalPayable` maths). Show: Subtotal, Tax (when > 0),
   Discount, Round off (when ≠ 0), **Total**.
3. Payment: replace nothing — add, under the status field, **"Amount received"** (money field) and **payment mode**
   chips `Cash · UPI · Card · Net banking · Other`. Status Paid → received = total; editing received sets status
   (received == total → Paid, else Pending). Voice setting the status keeps working.
4. **Doctor** picker (only when `clinicDoctorsProvider` has 2+ doctors; read it with a `Consumer` around the field):
   default = new optional dialog param `attendingDoctorUid`, else `defaultIssuingDoctorUid()`, else none ("Clinic").
   When the chosen doctor's `DoctorDocProfile.consultFeePaise > 0` and the bill has no lines yet, add
   "Consultation — <doctor name>" at that fee.
5. **Number**: show "Number: assigned when saved" with a small "Set number" link that turns into a text field
   (optional manual number, prefix-like `INV-26-27/0042`).
6. Submit label **"Save & preview"**. Save calls `createBilledInvoice` (or `updateBilledInvoice` in edit mode, see 7).
   Errors (duplicate number, network) show in the form's `notice`. On success pop with the invoice **and** the
   selected patient.
7. New optional param `InvoiceModel? initialInvoice` (edit mode): prefill everything from `initialInvoice.bill`
   (old invoices: one treatment line from `service`/`amount`), title "Edit invoice", submit "Save & preview".
8. `showDesktopCreateInvoiceDialog(...)` gets `String? attendingDoctorUid`, `InvoiceModel? initialInvoice`,
   `bool openPreview = true`. After the dialog returns a saved invoice and `openPreview` is true and
   `context.mounted`: `await MedicalPdfPreviewScreen.open(context, documentData: invoicePdfData(invoice, patient: patient), invoice: invoice)`.
   Return the invoice as before. When `onSave` is passed (old path), behave exactly as today (no preview).

## T17. The preview screen

Rewrite `lib/core/pdf/presentation/medical_pdf_preview_screen.dart` (keep the class name and `open(...)`).
`open(context, {required documentData, InvoiceModel? invoice, VoidCallback? onEdit})`; phone → full-screen route,
desktop (width ≥ `CruBreakpoint.compact`) → a large dialog (90% of the window, max 1200 × 900).

State: `templates` (from `docTemplatesProvider` + `visibleTemplates(..., kind: data.kind)`; receipt-roll templates
only for invoices), `selected` template (initially `DocRepository.resolveTemplate(...)`), `Future<RenderedDoc> _digital`
(re-created when `selected` changes), `bool _uploadedForSelected`.

Layout:
- **Desktop**: left = `PdfPreview(key: ValueKey(selected.id), build: (_) async => (await _digital).bytes, useActions: false, canChangeOrientation: false, canChangePageFormat: false, canDebug: false, pdfFileName: data.fileName, maxPageWidth: 720)`
  (the key makes it re-render when the template changes; same on phone);
  right panel 300 wide (`CruCard` look): template list (radio rows with name + "Ready-made / Clinic / Mine" label),
  a switch "Use for all future <kind label>s" (doctor → my default; user with `settings` and not a doctor → clinic
  default; hidden for others), warnings (amber rows, each with a **Fix** button when `fix != none` → closes the
  preview and opens Settings › Clinic & documents on the right tab — use the same navigation the account menu uses to
  open Settings; search for `settingsSectionProvider.notifier).state =`), then actions:
  **Print** (the one filled button), Share PDF, Save PDF, WhatsApp, Edit (when `onEdit` or `invoice` given),
  "Customize this template" (Phase 3; hide until then).
- **Phone**: the preview fills the screen; bottom bar: template chip (opens a bottom sheet with the list + switch),
  Print (filled), Share, ⋯ (Save PDF, WhatsApp, Edit). Warnings as an amber strip above the preview.

Actions:
- **Print**: `Printing.layoutPdf(name: data.fileName, format: selected.paper.toPdf(), onLayout: (_) async => (await service.render(data, template: selected, forPrint: true)).bytes)`.
- **Share PDF**: `Printing.sharePdf(bytes: digital, filename: data.fileName)`.
- **Save PDF** (desktop/web): `FilePicker.platform.saveFile(dialogTitle: 'Save PDF', fileName: data.fileName, type: FileType.custom, allowedExtensions: ['pdf'], bytes: digital)`;
  if a path comes back and that file is missing or empty, write the bytes yourself. Toast "Saved".
- **WhatsApp** (disabled when the patient has no phone): phone → `SharePlus.instance.share(ShareParams(files: [XFile.fromData(digital, mimeType: 'application/pdf', name: data.fileName)], text: summary))`;
  desktop → save to `getDownloadsDirectory()` (or temp) then `launchUrl('https://wa.me/91<10 digits>?text=<summary>')`
  and toast "PDF saved to Downloads — attach it in WhatsApp". Summary text like today's `_shareBillWhatsApp`
  (clinic, document, number, date, doctor, total/paid/balance for bills) — no emoji.
- **Edit**: invoice → close, `showDesktopCreateInvoiceDialog(context, initialInvoice: invoice)` (it re-opens the preview).
- After Print/Share/Save/WhatsApp finishes, if `!_uploadedForSelected`:
  `unawaited(GeneratedDocumentSync.enqueue(data: data, bytes: digital))`, set the flag (reset when the template changes).
  If an `invoice` was given and the template differs from the bill's `templateId`: `setInvoiceTemplate(...)`.
- Render errors (e.g. too long) → the error view already in the file (keep its look, use `context.cru` colours).

## T18. Invoice list and details

`lib/features/revenue/presentation/desktop_invoices_screen.dart` (`_InvoiceDetails`) and
`lib/features/mobile/mobile_invoices.dart` (invoice details/actions):
- **View PDF** (opens the preview with `invoicePdfData`; load the patient by id when there is one).
- **Edit** (hidden for cancelled).
- **Cancel invoice** (confirm dialog "Cancel invoice INV-…? It stays in your records with its number, marked
  cancelled, and leaves your revenue." → `cancelInvoice`). Remove "Delete" from these screens if present.
- Show `invoiceNumber` (fallback id) in rows and details.

## T19. Every other document goes through the same engine

1. `lib/features/appointments/presentation/session_details_sheet.dart`: **Generate Bill** →
   `showDesktopCreateInvoiceDialog(context, initialPatient: _patient, attendingDoctorUid: <the visit's attending doctor uid if the Visit model has it>)`.
   **Generate Rx** → keep `PrescriptionGenerationSheet`, but build its `letterheadConfig` from the real profile
   (`DoctorLetterheadConfig.fromProfileData(<doctorProfileProvider value>, <current user>)`), never `(null, null)`.
2. `lib/features/scribe/presentation/prescription_generation_sheet.dart`: when building
   `PdfPrescriptionDocumentData`, set `issuingDoctorUid` (visit's doctor, else `defaultIssuingDoctorUid()`),
   `signedByUid: docSignerFor(issuingDoctorUid)`, and `documentNumber: await DocNumbering.next(DocKind.prescription, date)`
   when the number field is empty/auto.
3. `lib/features/reports/presentation/medical_report_generation_sheet.dart`: same three fields (`DocKind.report`).
4. `lib/features/dental/referrals/referral_pdf.dart`: `buildLetter(...)` now builds a `PdfReferralDocumentData`
   (recipient = `contactName · contactSpecialty`, reason, findings, question, teeth via `toothLabel`, urgency label,
   isReply/reply, patient snapshot, number `DocNumbering.next(DocKind.referral, now)`, issuing/signer as above) and
   returns `(await const MedicalPdfService().render(data)).bytes`. `printOrPreview` opens
   `MedicalPdfPreviewScreen.open(context, documentData: data)` instead of `Printing.layoutPdf`. Keep method signatures.
5. `lib/features/dental/specialties/prostho/lab_rx_pdf.dart`: `buildRx(...)` builds a
   `PdfMedicalReportDocumentData(reportTitle: 'Laboratory prescription', sections: [...])` from the lab case
   (work type, teeth, shade, material, instructions, due date — whatever fields `LabCase` has) and renders it the same way.
6. **Medical certificate** — create `lib/features/reports/presentation/certificate_dialog.dart`:
   `showCertificateDialog(BuildContext context, {required Patient patient})`, a `CruFormDialog`: Type (Sick leave /
   Fitness to resume work / Custom), From and To dates (sick leave), Diagnosis (optional), Remarks. The body text is
   composed from the type, e.g. sick leave: "This is to certify that {name}, {age} years, was examined by me on {date}
   and is advised rest from {from} to {to} ({n} days){ for diagnosis}. {remarks}" — editable in a multi-line field
   before preview. Submit "Preview" → number `DocNumbering.next(DocKind.certificate, now)`, issuing = signed-in doctor,
   signer = `docSignerFor(...)`, open the preview.
7. Patient details "⋯" menu — `lib/features/patients/presentation/widgets/details/details_top_bar.dart` gets optional
   callbacks `onNewBill`, `onPrescription`, `onReport`, `onCertificate` with menu items **New bill**, **Prescription**,
   **Medical report**, **Medical certificate** (above "Delete patient"); wire them where the top bar is built
   (`patient_details.dart`) — bill → `showDesktopCreateInvoiceDialog(initialPatient: …)`; Rx/report → the existing sheets
   with the real letterhead config; certificate → `showCertificateDialog`. Show clinical items only to users with
   `clinical.edit`, the bill only with `billing`.

## T20. One signature pad for the app

Move `SignatureController` and `SignaturePad` (bottom of `lib/features/dental/records/consent_dialog.dart`) unchanged
into `lib/shared/widgets/signature_pad.dart`; import it in `consent_dialog.dart`. No behaviour change.

## T21. Settings › "Clinic & documents"

Replace the `_ClinicSection` in `lib/features/settings/presentation/desktop_settings_screen.dart` with a new
`DocumentsSettingsSection` in `lib/features/settings/presentation/documents/documents_settings_section.dart`
(split into `clinic_details_tab.dart`, `my_details_tab.dart`, `templates_tab.dart` in the same folder).
- `SettingsSection.clinic` label → `'Clinic & documents'`. Visible to: owner, doctors, anyone with `settings`.
- A 3-way segmented control at the top: **Clinic** · **My details** (doctors only) · **Templates**.
  A Fix button from the preview opens the right tab (`documentsTabProvider`, a `StateProvider<int>`).

**Clinic tab** (editable with `settings`; others see it read-only with "Only clinic admins can change these"):
`CruFormSection`s — *Clinic*: name, tagline, address (3 lines), phone, email, website, timings (2 lines),
clinic registration no.; *Logo & stamp*: logo (preview 64 px, Upload / Replace / Remove), clinic stamp (same);
*Bills*: "Charge GST on bills" switch + GSTIN (validate 15 chars `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`, warn
don't block), UPI ID (`name@bank` pattern) + "Name shown when paying", Round off to the nearest rupee (switch),
Bill terms (3 lines); *Numbering*: prefix per kind (validate `DocNumbering.isValidPrefix`), preview "Next: INV-26-27/…";
*Footer*: footer note; *Templates*: "Everyone uses clinic templates" (lockTemplates).
Prefill: from `clinicDocSettingsProvider`; any empty field from the owner's old letterhead fields on the profile (the
same keys `_ClinicSectionState._load` reads today). Save → `saveClinicSettings`; for the owner also call the existing
`DoctorProfileHelper.updateLetterheadBranding(...)` and `_syncClinicName(...)` logic (keep older screens like the
radiology report in step). Uploads: pick with `ImagePicker` (phone: gallery/camera; `imageQuality: 95`) or
`FilePicker` (desktop/web: png/jpg/jpeg/webp, `withData: true`) → `prepareBrandingImage` → `uploadClinicBranding(kind: logo|clinicStamp, contentType: 'image/png')`
→ `BrandingImageStore.remember(sha, png)` → save path + sha in settings. Offline → toast "Connect to the internet to
upload". Show errors from `prepareBrandingImage` as toasts.

**My details tab** (doctors only; writes only my own `doc_doctors/{me}`):
Name on documents (prefill "Dr. <name>"), qualifications, specialty, registration no., council (dropdown: NMC + every
state medical/dental council of India + "Other…" free text), phone, email (optional), consultation fee (₹);
*Signature*: preview on a white tile; **Draw** (dialog with `SignaturePad`, Clear / Use) — the pad's PNG goes through
`prepareBrandingImage(maxSide: 1000)` without cleaning; **Upload photo** (cleanBackground: true; show the cleaned
result and a "Keep the background" switch to redo without cleaning); **Remove**; *Stamp*: upload/remove.
Uploads → `MedicalStorageService.uploadDoctorFile(relativePath: 'signature' | 'stamp')`. Save also updates my
`clinics/{c}/members/{me}` `qualification` and `registrationNo` (the rules allow those self-edits) so team lists match;
for the owner, also `updateLetterheadBranding` with the same qualification/registration.
Footnote under the signature: "Only you can change your signature. It is printed only on documents you create."

**Templates tab**:
- *Defaults*: one row per kind — "Bills", "Prescriptions", "Referral letters", "Reports", "Certificates" — with a
  dropdown of `visibleTemplates(kind)`. Doctors set their own default; users with `settings` also see "Clinic default".
- *Gallery*: grid of cards (3 columns desktop, 2 phone). Card = thumbnail (page 1 of the sample invoice — or the first
  kind it applies to — rendered with `docSampleContext` + the clinic's real details, rasterised with
  `Printing.raster(bytes, pages: [0], dpi: 40)` → `toPng()`, cached in memory by `id:updatedAt`), name, a label
  (Ready-made / Clinic / Mine), and actions: **Preview** (opens the preview with sample data, SAMPLE watermark),
  ⋯ menu (Rename, Duplicate, Delete — not for ready-made; delete asks to confirm and says which defaults it clears).
  Phase 3 adds Customize/Edit.
- "New template" button (Phase 3; hide for now).

## T22. Clean-up

- `lib/features/profile/presentation/profile_screen.dart`: remove the `LetterheadBrandingCard(...)` usage (Settings has it now).
- Delete `lib/features/profile/presentation/widgets/letterhead_branding_card.dart` and
  `lib/features/revenue/presentation/bill_generation_sheet.dart` when nothing references them (`grep` first).
- No other deletions.

### Phase 2 Checks

```
flutter analyze
flutter test test/core/pdf/pdf_text_test.dart
flutter test test/core/pdf/doc_samples_test.dart
```
Add to `pdf_text_test.dart`: `InvoiceTotals.of` cases — 2 × ₹333.33 at 18% tax, ₹1,000 discount on a ₹500 bill
(capped), round off of ₹1,234.50 → ₹1,235, received more than total (capped).

**GATE 2 — STOP.** Report, plus this list for the user to try on the phone and PC:
new bill as doctor → preview → switch template → Print / Share; bill as receptionist for Dr B (Dr B's name, no
signature unless Dr B made it); Rx from a visit; referral letter; certificate; cancel a bill (watermark, revenue drops);
offline bill (number with the device code); upload logo + draw signature.

---

# PHASE 3 — Layout editor ("PUBG controls" for the letterhead), letterhead paper, Indian scripts (T23–T28)

*(Do not start until DO NOW says so.)* Folder: `lib/core/pdf/presentation/editor/`.

## T23. Editor controller

Create `template_editor_controller.dart`:

```dart
enum DocHandle { tl, tr, bl, br }

class TemplateEditorController extends ChangeNotifier {
  TemplateEditorController(DocTemplate initial)
      : _t = initial,
        _savedJson = jsonEncode(initial.toMap()),
        loadedUpdatedAt = initial.updatedAt;

  DocTemplate _t;
  String _savedJson;
  final int loadedUpdatedAt;
  DocTemplate get template => _t;
  bool get dirty => jsonEncode(_t.toMap()) != _savedJson;
  void markSaved(DocTemplate saved) { _t = saved; _savedJson = jsonEncode(saved.toMap()); notifyListeners(); }

  String? selectedId;
  DocBlock? get selected =>
      _t.blocks.where((b) => b.id == selectedId).firstOrNull;
  void select(String? id) { selectedId = id; notifyListeners(); }

  bool snap = true;
  DocKind previewKind = DocKind.invoice;

  /// Guide lines to draw while dragging (mm inside [guideZone]).
  List<double> guideX = const [];
  List<double> guideY = const [];
  DocZone? guideZone;

  final _undo = <DocTemplate>[];
  final _redo = <DocTemplate>[];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Call once before a change (first move of a drag, a property edit).
  void checkpoint() {
    _undo.add(_t);
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() { if (_undo.isEmpty) return; _redo.add(_t); _t = _undo.removeLast(); notifyListeners(); }
  void redo() { if (_redo.isEmpty) return; _undo.add(_t); _t = _redo.removeLast(); notifyListeners(); }

  /// Any whole-template edit (paper, style, options, body order).
  void update(DocTemplate Function(DocTemplate t) change) { checkpoint(); _t = change(_t); notifyListeners(); }

  /// Any single-block property edit.
  void updateBlock(String id, DocBlock Function(DocBlock b) change) {
    checkpoint();
    _replace(change(_t.blocks.firstWhere((b) => b.id == id)));
  }

  void _replace(DocBlock b) {
    _t = _t.copyWith(blocks: [for (final x in _t.blocks) x.id == b.id ? b : x]);
    notifyListeners();
  }

  static double r1(double v) => (v * 10).roundToDouble() / 10;
  static double _c(double v, double lo, double hi) =>
      v < lo ? lo : (v > math.max(lo, hi) ? math.max(lo, hi) : v);

  /// Drag: [orig] is the block as it was when the drag started.
  void moveTo(DocBlock orig, double dxMm, double dyMm) {
    final zw = _t.paper.contentWidthMm;
    final zh = _t.zoneHeight(orig.zone);
    var x = orig.x + dxMm;
    var y = orig.y + dyMm;
    final gx = <double>[];
    final gy = <double>[];
    if (snap) {
      final sx = _snap(x, orig.w, _targets(orig, zw, horizontal: true));
      x = sx.$1;
      if (sx.$2 != null) gx.add(sx.$2!);
      final sy = _snap(y, orig.h, _targets(orig, zh, horizontal: false));
      y = sy.$1;
      if (sy.$2 != null) gy.add(sy.$2!);
    }
    guideX = gx;
    guideY = gy;
    guideZone = orig.zone;
    _replace(orig.copyWith(
      x: r1(_c(x, 0, zw - orig.w)),
      y: r1(_c(y, 0, zh - orig.h)),
    ));
  }

  List<double> _targets(DocBlock self, double size, {required bool horizontal}) => [
    0, size / 2, size,
    for (final b in _t.blocks)
      if (b.id != self.id && b.zone == self.zone && !b.hidden)
        ...(horizontal ? [b.x, b.x + b.w / 2, b.x + b.w] : [b.y, b.y + b.h / 2, b.y + b.h]),
  ];

  /// Snaps the block's start, centre or end to the nearest target within
  /// 1.5 mm (returns the guide), else to a 0.5 mm grid.
  (double, double?) _snap(double start, double size, List<double> targets) {
    double? guide;
    var best = 1.5;
    var snapped = start;
    for (final t in targets) {
      for (final off in [0.0, size / 2, size]) {
        final d = (start + off - t).abs();
        if (d < best) {
          best = d;
          guide = t;
          snapped = t - off;
        }
      }
    }
    if (guide != null) return (snapped, guide);
    return ((start * 2).roundToDouble() / 2, null);
  }

  /// Corner drag. Images keep their shape (aspect ratio).
  void resize(DocBlock o, DocHandle h, double dx, double dy) {
    final zw = _t.paper.contentWidthMm;
    final zh = _t.zoneHeight(o.zone);
    const minW = 4.0;
    final minH = o.type == DocBlockType.line ? 0.5 : 3.0;
    var left = o.x, top = o.y, right = o.x + o.w, bottom = o.y + o.h;
    final leftSide = h == DocHandle.tl || h == DocHandle.bl;
    final topSide = h == DocHandle.tl || h == DocHandle.tr;
    if (leftSide) { left = _c(left + dx, 0, right - minW); } else { right = _c(right + dx, left + minW, zw); }
    if (topSide) { top = _c(top + dy, 0, bottom - minH); } else { bottom = _c(bottom + dy, top + minH, zh); }
    var w = right - left;
    var hh = bottom - top;
    if (o.type == DocBlockType.image && o.w > 0 && o.h > 0) {
      final ratio = o.h / o.w;
      hh = w * ratio;
      final room = topSide ? bottom : zh - top;
      if (hh > room) { hh = room; w = hh / ratio; }
      if (leftSide) left = right - w;
      if (topSide) top = bottom - hh;
    }
    _replace(o.copyWith(x: r1(left), y: r1(top), w: r1(w), h: r1(hh)));
  }

  void endDrag() { guideX = const []; guideY = const []; guideZone = null; notifyListeners(); }

  /// Header/footer height. The body keeps at least 40 mm. Blocks that no
  /// longer fit are pulled up / shrunk (not when the zone is closed to 0).
  void setZoneHeight(DocZone z, double mm) {
    final other = z == DocZone.header ? _t.footerMm : _t.headerMm;
    final v = r1(_c(mm, 0, _t.paper.contentHeightMm - other - 40));
    final zw = _t.paper.contentWidthMm;
    DocBlock fit(DocBlock b) {
      if (b.zone != z || v == 0) return b;
      final h = math.min(b.h, v);
      final w = math.min(b.w, zw);
      return b.copyWith(w: w, h: h, x: _c(b.x, 0, zw - w), y: _c(b.y, 0, v - h));
    }
    final blocks = [for (final b in _t.blocks) fit(b)];
    _t = z == DocZone.header
        ? _t.copyWith(headerMm: v, blocks: blocks)
        : _t.copyWith(footerMm: v, blocks: blocks);
    notifyListeners();
  }

  /// New paper size: everything scales with the content width.
  void setPaper(DocPaper p) {
    checkpoint();
    final f = p.contentWidthMm / _t.paper.contentWidthMm;
    DocBlock s(DocBlock b) => b.copyWith(
      x: r1(b.x * f), y: r1(b.y * f), w: r1(b.w * f), h: r1(b.h * f),
      fontPt: _c(b.fontPt * f, 5, 40),
    );
    _t = _t.copyWith(
      paper: p,
      headerMm: r1(_t.headerMm * f),
      footerMm: r1(_t.footerMm * f),
      blocks: [for (final b in _t.blocks) s(b)],
    );
    setZoneHeight(DocZone.header, _t.headerMm);
    setZoneHeight(DocZone.footer, _t.footerMm);
  }

  /// Arrow keys / nudge pad. No snapping, or a block sitting on a guide
  /// would snap straight back and never move.
  void nudge(double dxMm, double dyMm) {
    final b = selected;
    if (b == null || b.locked) return;
    checkpoint();
    final wasSnapping = snap;
    snap = false;
    moveTo(b, dxMm, dyMm);
    snap = wasSnapping;
    endDrag();
  }

  /// Adds [b] centred in the header (footer if the header is closed).
  /// Returns false when both zones are closed.
  bool add(DocBlock b) { … checkpoint(); place it; select it; max 80 blocks … }

  void duplicateSelected() { … new id, +3 mm offset, clamped … }

  /// Ready-made blocks are hidden; custom text/images/lines/boxes/QR are removed.
  void deleteSelected() { … }
}
```
New block ids: `'b${DateTime.now().microsecondsSinceEpoch}'`.

## T24. Canvas

Create `editor_canvas.dart` and `editor_block_view.dart`.

- `EditorCanvas({required controller, required double pxPerMm, required DocContext previewCtx, required ValueChanged<bool> onDragLock})`.
  Draws **page 1** at `paper.widthMm × paper.heightMm` (×`pxPerMm`), always **white paper on the Day palette**
  (like the existing letterhead preview in Settings), with: the background image (if any, at its opacity);
  faint dashed margin lines; header and footer zones tinted with `c.accentTint` at low opacity and labelled
  "Header" / "Footer" in a corner; the body area showing its visible sections as grey placeholder rows
  (`DocSection.labels`, in order) for `controller.previewKind`; blocks; guide lines (1 px, accent) while dragging;
  a **zone edge handle** (12 px tall full-width strip with a grip icon) at the header's bottom edge and the
  footer's top edge.
- Block pixel rect: `left = (margins.left + b.x) * s`, `top = (zoneTop + b.y) * s`, `w = b.w * s`, `h = b.h * s`,
  where `zoneTop = margins.top` for the header and `paper.heightMm - margins.bottom - footerMm` for the footer.
  When the clinic has no logo, draw it as the PDF does (skip `onlyWithLogo`, add `noLogoDx/Dy`), but drag and save
  the stored `x/y` (the with-logo position). Show a small note "No logo yet — showing the layout without it".
- **Pointer handling with a `Listener`** around the paper (not `GestureDetector` — no gesture-arena fights with
  scrolling):
  - `onPointerDown`: hit-test in this order: the selected block's 4 corner handles (24 × 24 px squares centred on the
    corners), the zone edge handles, then blocks from top-most (last in list) to bottom-most, skipping hidden ones.
    Hit a block → `select(id)`; if not locked, remember `_drag = (block, handle or null, e.localPosition)` and call
    `onDragLock(true)` (the parent switches its scroll physics to `NeverScrollableScrollPhysics`). Hit nothing →
    `select(null)`.
  - `onPointerMove`: if `_drag != null`: `d = (e.localPosition - start) / pxPerMm`; on the **first** move call
    `controller.checkpoint()`; then `resize(...)` / `moveTo(...)` / `setZoneHeight(..., startHeight ± d.dy)`.
  - `onPointerUp` / `onPointerCancel`: `_drag = null`, `controller.endDrag()`, `onDragLock(false)`.
  - A press-and-release without movement only selects (no undo entry).
- Selected block: 1.5 px accent outline, 4 white corner squares (10 px drawn, 24 px hit area) unless locked
  (show a small lock icon instead). Hidden blocks are not drawn on the canvas (they are listed in the panel).
- `EditorBlockView` (Flutter look-alike of the PDF block, same font Geist; size `fontPt * 0.3528 * pxPerMm`):
  field/text → value from `previewCtx.field(...)` / `fill(...)`; when empty, the field's label in brackets, muted
  ("[Clinic name]") — **only on the canvas**; one-line fields in `FittedBox(fit: BoxFit.scaleDown)`, multi-line
  clipped with `maxLines` like the PDF. Image → bytes from `previewCtx.images.forBlock(b)` (`Image.memory`, `BoxFit.contain`,
  opacity) or a dashed box with the role name ("Logo", "Signature"…). Line/box → `DecoratedBox`. QR → `Icons.qr_code_2`
  centred in a hairline box. doctorList → up to 4 columns with real doctor names (or "[Doctors]").

## T25. Panels

Create `editor_panels.dart` with three panels (used as side panels on desktop, bottom sheets on phone):

1. **Elements**: list of every block (icon by type + label: the field label, the text, the image role…), eye toggle
   (hidden), lock toggle, tap = select. "+ Add" menu grouped: *Clinic* (each clinic field), *Doctor* (each doctor field),
   *Document*, *Patient*, *Images* (Logo, Signature, Stamp, Clinic stamp, Upload picture…), *Shapes* (Line, Box),
   *QR* (UPI pay, Link…), *Text* (free text with `{{placeholders}}` — show a chip list to insert them), *All doctors*.
   Default sizes: field 60×5 (9 pt), text 80×10, logo 22×22, signature 40×16, stamp 24×24, line 186×1 (or content
   width), box 40×20, QR 24×24, doctors list = content width × 18.
2. **Properties** (selected block): content (field dropdown / text field / image replace / QR content), font size
   stepper 6–28 pt, bold, align L/C/R, colour swatches (Text, Muted, Accent, White, + custom hex), fill (box), line
   thickness, corner radius, opacity (images), Show on (All pages / First page / Last page / Not on first page),
   position X/Y/W/H in mm as number fields, **nudge pad** (↑ ↓ ← → buttons, 0.5 mm per tap, long-press repeats) —
   like PUBG's fine-tune —, Lock, Hide/Delete, Duplicate. Every edit goes through `controller.updateBlock`.
3. **Page**: name; applies to (kind chips; none selected = all); paper (A4 / A5 / Letter / Custom w×h) and margins;
   header height, footer height (mm fields, same as dragging the edges); accent colour (8 swatches + hex); text size
   (85–120 % slider = `fontScale`); options (bill signature: Doctor / Clinic stamp / Blank line / None; medicine names in
   capitals; amount in words; UPI QR). Header/footer height fields call `controller.checkpoint()` before
   `setZoneHeight` (so they can be undone); everything else goes through `controller.update(...)` /
   `controller.setPaper(...)`. **Body** for the kind chosen in a kind selector (`previewKind`):
   `ReorderableListView` of sections with drag handles and eye toggles; **Background** (T27).

## T26. Editor screen and entry points

Create `template_editor_screen.dart`: `TemplateEditorScreen.open(context, {required DocTemplate template})`.
- Opening a **ready-made** template → it is first copied: name "<name> (my copy)", `scope` = doctor (or clinic when the
  user has `settings` and chooses "For the whole clinic" in a small first dialog), `ownerUid` = me, `presetId` kept,
  `id` = '' (new).
- **Desktop**: top bar (back, name, Undo, Redo, zoom −/fit/+, "Preview PDF", **Save** filled); left Elements (260),
  centre canvas in a two-axis scroll view (physics switched off while dragging), right Properties (300) / Page tab when
  nothing is selected. Keyboard: arrows nudge 0.5 mm (Shift = 5 mm), Delete/Backspace = delete/hide, Ctrl+Z / Ctrl+Y /
  Ctrl+Shift+Z, Ctrl+D duplicate, Esc deselect, Ctrl+S save.
- **Phone**: top bar (back, Undo, Redo, Save); canvas at 200 % zoom by default in a two-axis scroll view; bottom
  toolbar (Add · Elements · Page · Preview); selecting a block opens a short Properties sheet (nudge pad, size −/+,
  font −/+, align, colour, Show on, lock, hide) that does not cover the selected block (scroll it into view above the sheet).
- Zoom: fit-to-width by default on desktop; 50–300 %; Ctrl + mouse wheel zooms on desktop.
- **Preview PDF**: renders the current (unsaved) template with `docSampleContext(docSampleData(previewKind), clinic: real clinic info, doctor: my info, images: real images)`
  → shows `PdfPreview` in a dialog (SAMPLE watermark).
- **Save**: `DocRepository.saveTemplate(t, loadedUpdatedAt: …)`; on `DocTemplateConflict` ask "Someone changed this
  template since you opened it." → *Overwrite* (`force: true`) / *Reload* (reopen with the stored one). Then
  `controller.markSaved(saved)` and toast "Template saved".
- Leaving with unsaved changes → "Discard changes?" dialog (`PopScope`).
- A template that is `tooNew` opens read-only with the message "Update CruDoc to edit this template".
- Entry points: Templates tab card → **Customize** (ready-made) / **Edit** (own, or clinic when `settings`);
  "New template" button (pick a ready-made start + name + Mine/Clinic) → editor; preview screen →
  "Customize this template" (show it now).
- Who may edit: clinic templates → `settings`; my templates → me. Others see Preview only.

## T27. My letterhead paper (background) and custom pictures

In the Page panel, **Background**: "Use my printed letterhead" → pick an image (png/jpg/webp) **or a PDF** (first page
via `Printing.raster(pdfBytes, pages: [0], dpi: 150)` → `toPng()`), `prepareBrandingImage(maxSide: 2480)`, upload
(clinic template → `uploadClinicTemplateImage`; my template → `uploadDoctorFile(relativePath: 'templates/<templateId>/<sha8>')`;
a template that has no id yet is saved first), set `DocBackground(path, sha, printOnPaper: false, opacity: 1)`.
Controls: "Print the background too" switch (`printOnPaper`), opacity slider (30–100 %), Remove.
Help text: "Use a straight scan or the file from your printer. Photos should be cropped to the page edges first."
When a background is set, offer **"Clear the header and footer"** (hides all blocks) — the usual pre-printed setup.
Custom pictures ("Upload picture…" in Add) use the same upload path, `imageRole: custom`, `imagePath`/`imageSha` set.

## T28. Indian scripts (Devanagari, Gujarati, Tamil…)

The PDF library cannot shape these scripts. Render such strings as images:
1. In `doc_context_builder.dart`, collect every string that will be printed and `needsScriptFallback` (patient name,
   clinic name/address/tagline, doctor name, recipient, and body texts — notes, advice, complaints, diagnosis, report
   sections, certificate body: split those by paragraph). For each: render with Flutter —
   `TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: 10 * 3, color: Colors.black)), textDirection: TextDirection.ltr)`
   laid out with `maxWidth` = (content width in pt × 3) for paragraphs, unbounded for short fields; paint into a
   `ui.PictureRecorder` canvas; `picture.toImage(w, h)` → PNG bytes; store in `scriptImages[s]` together with the
   painted size (make `scriptImages` a map to a small class `{Uint8List png; double widthPt; double heightPt}` at 3×).
   The system font draws the script (Android/iOS/Windows all have Indic fonts).
2. In the renderer, wherever text is drawn (`textBox`, `paragraphs`, table cells for names/medicines), if
   `ctx.scriptImages[text]` exists, draw `pw.Image(MemoryImage(png), width: widthPt × (fontPt/10), height: heightPt × (fontPt/10))`
   instead of `pw.Text` (scale by the wanted font size; fit inside the block box for header blocks).
3. Remove the "may not print correctly" warning from T11 step 5.
4. Add `edge_devanagari.pdf` to `doc_samples_test.dart` **only if** the test environment can render text (if
   `TextPainter` gives blank images in tests, skip that sample and note it — the user checks on the phone).

### Phase 3 Checks

```
flutter analyze
flutter test test/core/pdf/pdf_text_test.dart
flutter test test/core/pdf/doc_samples_test.dart
```
Add `test/core/pdf/template_editor_controller_test.dart`: move snaps to the zone centre within 1.5 mm; move clamps
inside the zone; resize keeps an image's aspect ratio; resize never goes below 4 × 3 mm; header height can't leave
the body under 40 mm; A4 → A5 scales blocks by 132/186; undo/redo restore exact JSON; a press without move adds no
undo entry (test through the controller API: `checkpoint` only on first move).

**GATE 3 — STOP (final).** Report, plus the user's checklist: customize Classic on the PC (drag logo, resize, add a
text with `{{doctor.regNo}}`, change accent, reorder body), save, print; the same on the phone with the nudge pad;
pre-printed paper template with a scanned letterhead (shared PDF shows it, printed page doesn't); a Marathi patient
name on a prescription.

---

## Not in this job (later)

- The radiology report keeps its own layout (`lib/features/radiology/presentation/reports/report_pdf.dart`).
- Different header heights on page 1 and later pages.
- IGST (patients from other states) and GST e-invoicing.
- Sending the PDF through the WhatsApp Business API (server); today it's the share sheet / wa.me.
- Sharing templates between clinics.
