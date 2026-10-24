import 'dart:async';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/data/doc_settings_models.dart';
import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context_builder.dart';
import 'package:doctor_management_app/core/pdf/render/pdf_text.dart';
import 'package:doctor_management_app/core/pdf/services/generated_document_sync.dart';
import 'package:doctor_management_app/core/pdf/services/medical_pdf_service.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_screen.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_presets.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class MedicalPdfPreviewScreen extends ConsumerStatefulWidget {
  const MedicalPdfPreviewScreen({
    super.key,
    required this.documentData,
    this.invoice,
    this.onEdit,
    this.pdfService = const MedicalPdfService(),
  });

  final PdfMedicalDocumentData documentData;
  final InvoiceModel? invoice;
  final VoidCallback? onEdit;
  final MedicalPdfService pdfService;

  static Future<void> open(
    BuildContext context, {
    required PdfMedicalDocumentData documentData,
    InvoiceModel? invoice,
    VoidCallback? onEdit,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= CruBreakpoint.compact;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(CruSpace.s24),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 900),
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width * 0.9,
              height: MediaQuery.sizeOf(context).height * 0.9,
              child: MedicalPdfPreviewScreen(
                documentData: documentData,
                invoice: invoice,
                onEdit: onEdit,
              ),
            ),
          ),
        ),
      );
    }

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MedicalPdfPreviewScreen(
          documentData: documentData,
          invoice: invoice,
          onEdit: onEdit,
        ),
      ),
    );
  }

  @override
  ConsumerState<MedicalPdfPreviewScreen> createState() =>
      _MedicalPdfPreviewScreenState();
}

class _MedicalPdfPreviewScreenState
    extends ConsumerState<MedicalPdfPreviewScreen> {
  DocTemplate? _selectedTemplate;
  Future<RenderedDoc>? _digitalFuture;
  DocContext? _lastContext;
  bool _uploadedForSelected = false;

  @override
  void initState() {
    super.initState();
    _initTemplate();
  }

  Future<void> _initTemplate() async {
    final t = await DocRepository.instance.resolveTemplate(
      widget.documentData.kind,
      issuingDoctorUid: widget.documentData.issuingDoctorUid,
      explicitId: widget.documentData.templateId,
    );
    if (!mounted) return;
    _selectTemplate(t);
  }

  void _selectTemplate(DocTemplate t) {
    setState(() {
      _selectedTemplate = t;
      _uploadedForSelected = false;
      _digitalFuture = _render(t);
    });
  }

  Future<void> _customizeTemplate(DocTemplate selected) async {
    final saved = await TemplateEditorScreen.open(context, template: selected);
    if (saved == true && mounted) {
      ref.invalidate(docTemplatesProvider);
      final list = await DocRepository.instance.templatesOnce();
      final match = list
          .where((t) => t.id == selected.id || t.name.startsWith(selected.name))
          .lastOrNull;
      if (match != null && mounted) {
        _selectTemplate(match);
      } else {
        setState(() {
          _digitalFuture = _render(selected);
        });
      }
    }
  }

  Future<RenderedDoc> _render(DocTemplate t) async {
    final ctx = await buildDocContext(
      data: widget.documentData,
      template: t,
      sample: false,
    );
    _lastContext = ctx;
    return widget.pdfService.render(
      widget.documentData,
      template: t,
      forPrint: false,
    );
  }

  Future<void> _recordAction(RenderedDoc rendered) async {
    if (!_uploadedForSelected) {
      unawaited(
        GeneratedDocumentSync.enqueue(
          data: widget.documentData,
          bytes: rendered.bytes,
        ),
      );
      _uploadedForSelected = true;
    }

    final inv = widget.invoice;
    final t = _selectedTemplate;
    if (inv != null && t != null && inv.bill.templateId != t.id) {
      await InvoiceRepository().setInvoiceTemplate(inv, t.id);
    }
  }

  Future<void> _print(RenderedDoc rendered) async {
    final t = _selectedTemplate ?? rendered.template;
    await Printing.layoutPdf(
      name: widget.documentData.fileName,
      format: t.paper.toPdf(),
      onLayout: (_) async => (await widget.pdfService.render(
        widget.documentData,
        template: t,
        forPrint: true,
      )).bytes,
    );
    await _recordAction(rendered);
  }

  Future<void> _share(RenderedDoc rendered) async {
    await Printing.sharePdf(
      bytes: rendered.bytes,
      filename: widget.documentData.fileName,
    );
    await _recordAction(rendered);
  }

  Future<void> _save(RenderedDoc rendered) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save PDF',
      fileName: widget.documentData.fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: rendered.bytes,
    );

    if (path != null && !kIsWeb) {
      final f = io.File(path);
      if (!f.existsSync() || f.lengthSync() == 0) {
        await f.writeAsBytes(rendered.bytes);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    }
    await _recordAction(rendered);
  }

  Future<void> _whatsApp(RenderedDoc rendered) async {
    final phone =
        widget.documentData.patient.phone?.replaceAll(RegExp(r'\D'), '') ?? '';
    final digits = phone.length > 10
        ? phone.substring(phone.length - 10)
        : phone;
    final summary = _buildWhatsAppSummary(rendered);

    if (!kIsWeb && (io.Platform.isAndroid || io.Platform.isIOS)) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              rendered.bytes,
              mimeType: 'application/pdf',
              name: widget.documentData.fileName,
            ),
          ],
          text: summary,
        ),
      );
    } else {
      if (kIsWeb) {
        // No folders on the web: the browser downloads the PDF instead.
        await Printing.sharePdf(
          bytes: rendered.bytes,
          filename: widget.documentData.fileName,
        );
      } else {
        final dir =
            await getDownloadsDirectory() ?? await getTemporaryDirectory();
        final localFile = io.File(
          '${dir.path}/${widget.documentData.fileName}',
        );
        await localFile.writeAsBytes(rendered.bytes);
      }

      final waUri = Uri.parse(
        'https://wa.me/91$digits?text=${Uri.encodeComponent(summary)}',
      );
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF saved to Downloads — attach it in WhatsApp'),
          ),
        );
      }
    }
    await _recordAction(rendered);
  }

  String _buildWhatsAppSummary(RenderedDoc rendered) {
    final ctx = _lastContext;
    final clinic = ctx?.clinic.name ?? '';
    final title = widget.documentData.type.title;
    final num = widget.documentData.documentNumber;
    final date = formatDocDate(widget.documentData.documentDate);
    final docName = ctx?.doctor?.name ?? '';
    final pName = widget.documentData.patient.fullName;

    final b = StringBuffer();
    if (clinic.isNotEmpty) b.writeln('*$clinic*');
    b.writeln('*$title*');
    b.writeln();
    b.writeln('Patient: $pName');
    if (num.isNotEmpty) b.writeln('No: $num');
    b.writeln('Date: $date');
    if (docName.isNotEmpty) b.writeln('Doctor: $docName');

    final data = widget.documentData;
    if (data is PdfInvoiceDocumentData) {
      b.writeln();
      b.writeln('Total: ${formatPaise(toPaise(data.totals.grandTotal))}');
      b.writeln('Paid: ${formatPaise(toPaise(data.totals.paidAmount))}');
      if (data.totals.balanceDue > 0) {
        b.writeln(
          'Balance due: ${formatPaise(toPaise(data.totals.balanceDue))}',
        );
      }
    }

    if (ctx?.clinic.phone.isNotEmpty == true) {
      b.writeln();
      b.writeln('Contact: ${ctx!.clinic.phone}');
    }
    return b.toString().trim();
  }

  /// Closes the preview and opens the Documents page on the tab that holds
  /// the missing detail.
  void _handleFix(DocFix fix) {
    ref.read(documentsTabProvider.notifier).state = fix == DocFix.myDetails
        ? 1
        : 0;
    final goToTab = ref.read(shellNavigatorProvider);
    final root = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();
    if (goToTab != null) {
      // Desktop shell: switch the sidebar page.
      goToTab(DesktopTab.documents);
    } else {
      // Phone: push the page from More.
      openMobileDestination(root, DesktopTab.documents);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final isDesktop = MediaQuery.sizeOf(context).width >= CruBreakpoint.compact;

    final allTemplates =
        ref.watch(docTemplatesProvider).value ?? builtinTemplates;
    final clinicSettings =
        ref.watch(clinicDocSettingsProvider).value ?? const ClinicDocSettings();

    var visible = DocRepository.instance.visibleTemplates(
      allTemplates,
      clinicSettings,
      kind: widget.documentData.kind,
    );
    if (widget.documentData.kind != DocKind.invoice) {
      visible = visible.where((t) => !t.paper.isRoll).toList();
    }

    final selected = _selectedTemplate ?? visible.first;

    return Scaffold(
      backgroundColor: isDesktop ? Colors.transparent : c.surface,
      body: FutureBuilder<RenderedDoc>(
        future: _digitalFuture,
        builder: (context, snapshot) {
          final rendered = snapshot.data;
          final error = snapshot.error;

          if (isDesktop) {
            return _buildDesktopLayout(
              context,
              visibleTemplates: visible,
              selected: selected,
              rendered: rendered,
              error: error,
            );
          }

          return _buildMobileLayout(
            context,
            visibleTemplates: visible,
            selected: selected,
            rendered: rendered,
            error: error,
          );
        },
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context, {
    required List<DocTemplate> visibleTemplates,
    required DocTemplate selected,
    required RenderedDoc? rendered,
    required Object? error,
  }) {
    final c = context.cru;

    return CruCard(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          // Left: PDF Preview
          Expanded(
            child: Container(
              color: c.inset,
              child: Stack(
                children: [
                  if (error != null)
                    _buildErrorView(error)
                  else if (rendered == null)
                    Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.accentText,
                      ),
                    )
                  else
                    PdfPreview(
                      key: ValueKey(selected.id),
                      build: (_) async => rendered.bytes,
                      useActions: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      pdfFileName: widget.documentData.fileName,
                      maxPageWidth: 720,
                    ),
                  Positioned(
                    top: CruSpace.s12,
                    left: CruSpace.s12,
                    child: CruIconButton(
                      icon: CruIcons.close,
                      semanticLabel: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right: Control Panel (300 px)
          SizedBox(
            width: 320,
            child: Container(
              color: c.surface,
              padding: const EdgeInsets.all(CruSpace.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Document', style: CruType.headline.tint(c.label)),
                  const SizedBox(height: CruSpace.s4),
                  Text(
                    widget.documentData.previewTitle,
                    style: CruType.caption.tint(c.label3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: CruSpace.s16),

                  if (rendered?.warnings.isNotEmpty == true) ...[
                    _buildWarningsList(rendered!.warnings),
                    const SizedBox(height: CruSpace.s12),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Template',
                        style: CruType.groupLabel.tint(c.label3),
                      ),
                      CruButton(
                        label: 'Customize',
                        kind: CruButtonKind.secondary,
                        icon: CruIcons.pen,
                        onPressed: () => _customizeTemplate(selected),
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s8),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final t in visibleTemplates)
                            _buildTemplateRadioRow(t, selected),
                          const SizedBox(height: CruSpace.s12),
                          _buildDefaultSwitch(selected),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: CruSpace.s12),
                  _buildActions(rendered),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context, {
    required List<DocTemplate> visibleTemplates,
    required DocTemplate selected,
    required RenderedDoc? rendered,
    required Object? error,
  }) {
    final c = context.cru;

    return SafeArea(
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s12,
              vertical: CruSpace.s8,
            ),
            child: Row(
              children: [
                CruIconButton(
                  icon: CruIcons.chevronLeft,
                  semanticLabel: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: Text(
                    widget.documentData.previewTitle,
                    style: CruType.headline.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Warnings strip if any
          if (rendered?.warnings.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              child: _buildWarningsList(rendered!.warnings),
            ),

          // PDF Preview Area
          Expanded(
            child: error != null
                ? _buildErrorView(error)
                : rendered == null
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.accentText,
                    ),
                  )
                : PdfPreview(
                    key: ValueKey(selected.id),
                    build: (_) async => rendered.bytes,
                    useActions: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    pdfFileName: widget.documentData.fileName,
                  ),
          ),

          // Bottom Bar
          Container(
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: Row(
              children: [
                CruCapsuleButton(
                  label: selected.name,
                  onPressed: () => _openMobileTemplateSheet(
                    context,
                    visibleTemplates: visibleTemplates,
                    selected: selected,
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: CruButton(
                    label: 'Print',
                    expand: true,
                    onPressed: rendered == null ? null : () => _print(rendered),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                IconButton(
                  icon: Icon(Icons.share_outlined, size: 20, color: c.label),
                  onPressed: rendered == null ? null : () => _share(rendered),
                ),
                CruIconButton(
                  icon: CruIcons.more,
                  semanticLabel: 'More actions',
                  onPressed: rendered == null
                      ? null
                      : () => _openMobileMoreSheet(context, rendered),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateRadioRow(DocTemplate t, DocTemplate selected) {
    final c = context.cru;
    final isSelected = t.id == selected.id;
    final scopeLabel = t.isBuiltin
        ? 'Ready-made'
        : (t.scope == DocScope.clinic ? 'Clinic' : 'Mine');

    return InkWell(
      onTap: () => _selectTemplate(t),
      borderRadius: BorderRadius.circular(CruRadius.control),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s10,
          vertical: CruSpace.s8,
        ),
        margin: const EdgeInsets.only(bottom: CruSpace.s4),
        decoration: ShapeDecoration(
          color: isSelected ? c.accentWash : Colors.transparent,
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: isSelected ? c.accent : c.label2,
            ),
            const SizedBox(width: CruSpace.s8),
            Expanded(
              child: Text(
                t.name,
                style: CruType.text.w500.tint(isSelected ? c.label : c.label2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(scopeLabel, style: CruType.caption.tint(c.label3)),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultSwitch(DocTemplate selected) {
    final c = context.cru;
    final access = ClinicSession.instance.access;
    final isDoctor = access?.kind == MemberKind.doctor;
    final hasSettings = access?.can(ClinicPermission.settings) ?? false;

    if (!isDoctor && !hasSettings) return const SizedBox.shrink();

    final label = isDoctor
        ? 'Use for all future ${widget.documentData.kind.label.toLowerCase()}s'
        : 'Set as clinic default';

    final clinicSettings =
        ref.watch(clinicDocSettingsProvider).value ?? const ClinicDocSettings();
    final profile = ref.watch(myDocProfileProvider).value;

    final currentDefault = isDoctor
        ? (profile?.defaults[widget.documentData.kind.name] ?? '')
        : (clinicSettings.defaults[widget.documentData.kind.name] ?? '');

    final isDefault = currentDefault == selected.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: CruType.caption.tint(c.label2))),
          Switch.adaptive(
            value: isDefault,
            activeTrackColor: c.accent,
            onChanged: (val) async {
              await DocRepository.instance.setDefault(
                widget.documentData.kind,
                val ? selected.id : '',
                forClinic: !isDoctor,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWarningsList(List<DocWarning> warnings) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.all(CruSpace.s8),
      decoration: ShapeDecoration(
        color: c.amberTint,
        shape: cruShape(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s2),
              child: Row(
                children: [
                  CruIcon(CruIcons.warning, size: 14, color: c.amberText),
                  const SizedBox(width: CruSpace.s6),
                  Expanded(
                    child: Text(
                      w.message,
                      style: CruType.caption.tint(c.amberText),
                    ),
                  ),
                  if (w.fix != DocFix.none)
                    CruCapsuleButton(
                      label: 'Fix',
                      height: 24,
                      onPressed: () => _handleFix(w.fix),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(RenderedDoc? rendered) {
    final phone = widget.documentData.patient.phone?.trim() ?? '';
    final canWhatsApp = phone.isNotEmpty;
    final hasEdit = widget.onEdit != null || widget.invoice != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruButton(
          label: 'Print',
          expand: true,
          onPressed: rendered == null ? null : () => _print(rendered),
        ),
        const SizedBox(height: CruSpace.s8),
        CruButton(
          label: 'Share PDF',
          kind: CruButtonKind.inset,
          expand: true,
          onPressed: rendered == null ? null : () => _share(rendered),
        ),
        const SizedBox(height: CruSpace.s8),
        CruButton(
          label: 'Save PDF',
          kind: CruButtonKind.inset,
          icon: CruIcons.download,
          expand: true,
          onPressed: rendered == null ? null : () => _save(rendered),
        ),
        const SizedBox(height: CruSpace.s8),
        CruButton(
          label: 'WhatsApp',
          kind: CruButtonKind.inset,
          icon: CruIcons.whatsapp,
          expand: true,
          onPressed: (rendered != null && canWhatsApp)
              ? () => _whatsApp(rendered)
              : null,
        ),
        if (hasEdit) ...[
          const SizedBox(height: CruSpace.s8),
          CruButton(
            label: 'Edit',
            kind: CruButtonKind.inset,
            icon: CruIcons.pen,
            expand: true,
            onPressed: () {
              Navigator.of(context).pop();
              if (widget.invoice != null) {
                showDesktopCreateInvoiceDialog(
                  context,
                  initialInvoice: widget.invoice,
                );
              } else {
                widget.onEdit?.call();
              }
            },
          ),
        ],
      ],
    );
  }

  void _openMobileTemplateSheet(
    BuildContext context, {
    required List<DocTemplate> visibleTemplates,
    required DocTemplate selected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pick template', style: CruType.headline),
              const SizedBox(height: CruSpace.s12),
              for (final t in visibleTemplates)
                _buildTemplateRadioRow(t, selected),
              const SizedBox(height: CruSpace.s12),
              _buildDefaultSwitch(selected),
              const SizedBox(height: CruSpace.s8),
              CruButton(
                label: 'Customize template',
                kind: CruButtonKind.inset,
                icon: CruIcons.pen,
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  _customizeTemplate(selected);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMobileMoreSheet(BuildContext context, RenderedDoc rendered) {
    final phone = widget.documentData.patient.phone?.trim() ?? '';
    final canWhatsApp = phone.isNotEmpty;
    final selected = _selectedTemplate;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected != null) ...[
                CruButton(
                  label: 'Customize template',
                  kind: CruButtonKind.inset,
                  icon: CruIcons.pen,
                  expand: true,
                  onPressed: () {
                    Navigator.of(context).pop();
                    _customizeTemplate(selected);
                  },
                ),
                const SizedBox(height: CruSpace.s8),
              ],
              CruButton(
                label: 'Save PDF',
                kind: CruButtonKind.inset,
                icon: CruIcons.download,
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  _save(rendered);
                },
              ),
              const SizedBox(height: CruSpace.s8),
              CruButton(
                label: 'WhatsApp',
                kind: CruButtonKind.inset,
                icon: CruIcons.whatsapp,
                expand: true,
                onPressed: canWhatsApp
                    ? () {
                        Navigator.of(context).pop();
                        _whatsApp(rendered);
                      }
                    : null,
              ),
              if (widget.onEdit != null || widget.invoice != null) ...[
                const SizedBox(height: CruSpace.s8),
                CruButton(
                  label: 'Edit',
                  kind: CruButtonKind.inset,
                  icon: CruIcons.pen,
                  expand: true,
                  onPressed: () {
                    Navigator.of(context).pop(); // bottom sheet
                    Navigator.of(context).pop(); // preview
                    if (widget.invoice != null) {
                      showDesktopCreateInvoiceDialog(
                        context,
                        initialInvoice: widget.invoice,
                      );
                    } else {
                      widget.onEdit?.call();
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(Object error) {
    final c = context.cru;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CruSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_rounded, size: 42, color: c.amberText),
            const SizedBox(height: CruSpace.s12),
            Text(
              'Unable to generate PDF preview',
              style: CruType.headline.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: CruType.subhead.tint(c.label2),
            ),
          ],
        ),
      ),
    );
  }
}
