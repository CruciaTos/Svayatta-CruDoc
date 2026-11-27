import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../data/abdm_api.dart';

/// Displays and prints the clinic's ABHA Scan and Share counter QR.
class CounterQrScreen extends StatefulWidget {
  const CounterQrScreen({super.key});

  @override
  State<CounterQrScreen> createState() => _CounterQrScreenState();
}

class _CounterQrScreenState extends State<CounterQrScreen> {
  final _counterCtrl = TextEditingController(text: 'OPD1');

  bool _loading = true;
  String? _hipId;
  String? _qrBaseUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFacility();
  }

  @override
  void dispose() {
    _counterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFacility() async {
    try {
      final res = await AbdmApi.instance.facility();
      if (!mounted) return;
      setState(() {
        _hipId = res.hipId;
        _qrBaseUrl = res.qrBaseUrl;
        _loading = false;
      });
    } on AbdmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  static final _counterPattern = RegExp(r'^[A-Za-z0-9]{1,20}$');

  String get _counter => _counterCtrl.text.trim();
  bool get _counterValid => _counterPattern.hasMatch(_counter);

  String? get _qrData {
    final hipId = _hipId;
    final base = _qrBaseUrl;
    if (hipId == null || hipId.isEmpty || base == null || base.isEmpty) {
      return null;
    }
    if (!_counterValid) return null;
    return Uri.parse(base)
        .replace(queryParameters: {'hip-id': hipId, 'counter-id': _counter})
        .toString();
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final data = _qrData ?? '';
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: data,
                width: 220,
                height: 220,
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                _counter,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> _print() async {
    if (_qrData == null) return;
    await Printing.layoutPdf(onLayout: _buildPdf);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final qrData = _qrData;

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        title: Text(
          'ABHA counter QR',
          style: CruType.title2.tint(c.label),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(CruSpace.s24),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? CruCard(
                    child: Text(
                      _error!,
                      style: CruType.text.tint(c.redText),
                    ),
                  )
                : (_hipId == null || _hipId!.isEmpty)
                ? CruCard(
                    child: Text(
                      'Ask CruDoc support to add your facility ID.',
                      style: CruType.text.tint(c.label),
                    ),
                  )
                : CruCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CruTextField(
                          label: 'Counter',
                          controller: _counterCtrl,
                          hint: 'OPD1',
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9]'),
                            ),
                            LengthLimitingTextInputFormatter(20),
                          ],
                          validator: (v) {
                            final s = (v ?? '').trim();
                            return _counterPattern.hasMatch(s)
                                ? null
                                : '1 to 20 letters or digits';
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: CruSpace.s16),
                        if (qrData != null)
                          SizedBox(
                            height: 260,
                            child: PdfPreview(
                              key: ValueKey(qrData),
                              build: _buildPdf,
                              useActions: false,
                              canChangeOrientation: false,
                              canChangePageFormat: false,
                              canDebug: false,
                            ),
                          ),
                        const SizedBox(height: CruSpace.s16),
                        CruButton(
                          label: 'Print',
                          expand: true,
                          onPressed: qrData != null ? _print : null,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
