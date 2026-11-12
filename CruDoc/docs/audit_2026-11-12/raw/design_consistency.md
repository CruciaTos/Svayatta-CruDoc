# Design-system consistency audit (inventory)

Scope: CruDoc/lib (features, core, shared) and crudoc_shared/lib/widgets/cru + theme. Read-only. Counts from grep over `lib/features` unless stated. Regex counts are matches, not unique lines.

## Summary
1. Design system exists and is good: 10 Cru widget files (~3,800 lines), theme tokens (`cru_tokens.dart`, `cru_colors.dart`, `cru_type.dart`, `cru_theme.dart`), and a CruIcon set used 1,066 times. Adoption is uneven.
2. Raw Material is still common: 737 matches of ChoiceChip, SnackBar, ScaffoldMessenger, IconButton, DropdownButton, showModalBottomSheet, TextField, AlertDialog, FilterChip, DropdownMenu, PopupMenuButton and similar. Dental (153), appointments (84) and files (78) lead.
3. Colour is the biggest leak: 273 `Color(0x…)` literals across 28 files, plus 307 `Colors.*` (mostly white, transparent, black). `mobile/` has 182 colour hits, and `mobile_kit.dart` and `mobile_backdrop.dart` hold most of them.
4. Type is mostly tokenised except dental, mobile and campaigns: 123 raw `TextStyle(`, 115 literal `fontSize:` values across 20+ sizes (13, 14, 16 and 9.5, 13.5, 15.5 …), concentrated in dental (73), mobile (42), campaigns (28), radiology (24), update (20).
5. Copy is English-only with no i18n (no .arb, no l10n, no AppLocalizations). Verb variants are inconsistent: Done 40 vs Save 16; Delete 30 vs Remove 24; Close 43 vs Cancel 46 vs Back 32; "Try again" 11 vs Retry 3. Ten or more private widgets are duplicated across features (`_Row` 7, `_StatusPill` 4, `_SectionLabel` 4, `_LoadError` 4, `_Bars` 4, `_NoMatches` 3, `_Chip` 3, `_OptionRow` 3, `_FileRow` 3).

## Shared design system (what exists)
- Widgets (crudoc_shared/lib/widgets/cru): `cru_button.dart` (CruButton, CruCapsuleButton, CruSquareButton, CruButtonKind, CruCapsuleKind); `cru_card.dart` (CruCard, CruInkCard); `cru_form.dart` 1,419 lines (CruTextField, CruDropdownField, CruPickerField, CruTagField, CruDateTile, CruFormDialog, CruFormSection, CruFieldRow, CruFieldFrame, CruFieldError, CruFormNotice, CruSwitchRow); `cru_segmented_control.dart` (CruSegmentedControl); `cru_switch.dart` (CruSwitch); `cru_indicators.dart` (CruChip, CruPill, CruInfoPill, CruStatusDot, CruProgressBar, CruProgressRing, CruDoneBadge, CruMonogram); `cru_extras.dart` (CruLink, CruSeparator, CruKeycap, CruIconTile, CruIconButton); `cru_pressable.dart` (CruPressable, CruTouchTarget); `cru_icons.dart` (CruIcon, CruIconData, CruIconScale). Export barrel: `cru.dart`.
- Theme: `cru_colors.dart` (CruColors: ink50–ink900, white; 503 lines), `app_colors.dart` (AppColors), `cru_tokens.dart` (CruRadius: card 24, control 12, switcher 14, iconTile 10, keycap 6, bar 6, full 999…; CruSpace: s2…s32; CruLayout: sidebar 260, control 40, actionButton 44, chip 30, segmentHeight 36…), `cru_type.dart` (CruType: largeTitle, title, title2, headline, body, row, callout, subhead, caption, micro, groupLabel, metric, amount, input, note, lead, chip, step, dateDay/dateMonth, monogram(size); helpers tabular, w500/600/700, tint), `cru_input_border.dart`, `cru_theme.dart` (ThemeData incl. SnackBar theme; no Cru snackbar helper).
- Core copies: CruDoc/lib/core/theme holds only re-export stubs (1 line each).
- Gaps in the system: no Cru snackbar/toast helper; no Cru chip-group/filter-chip widget (CruChip is a pill); no Cru list-tile/row widget; no Cru popup/menu; no Cru date/time picker wrapper beyond CruDateTile; no spacing token for 6/10/12 used inconsistently; no text style for 13/15 sizes; no i18n layer.

## Per-feature table
Columns: raw = raw Material widget matches; col = strict colour literals (`Color(0x` + `Colors.`, excluding `CruColors.`); TS = `TextStyle(` + `fontSize:` literals; Icons = `Icons.` (Material) matches; CruIcon = `CruIcon(s)` uses; Cru = Cru widget uses; sp = literal spacing (SizedBox/EdgeInsets numeric); rad = literal radius.

| feature | files | raw | col | TS | Icons | CruIcon | Cru | sp | rad |
|---|---|---|---|---|---|---|---|---|---|
| appointments | 56 | 84 | 17 | 0 | 24 | 81 | 132 | 301 | 27 |
| auth | 2 | 1 | 1 | 0 | 0 | 3 | 12 | 26 | 2 |
| campaigns | 12 | 69 | 59 | 28 | 44 | 13 | 11 | 211 | 74 |
| dashboard | 19 | 10 | 31 | 5 | 0 | 58 | 37 | 134 | 0 |
| dental | 78 | 153 | 81 | 73 | 15 | 223 | 551 | 840 | 59 |
| files | 51 | 78 | 18 | 4 | 13 | 60 | 85 | 254 | 19 |
| homeopathy | 17 | 40 | 2 | 0 | 0 | 33 | 55 | 299 | 18 |
| inventory | 37 | 35 | 2 | 5 | 10 | 39 | 82 | 246 | 30 |
| mobile | 19 | 18 | 182 | 42 | 3 | 217 | 35 | 313 | 9 |
| messaging | 15 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| onboarding | 4 | 5 | 42 | 0 | 0 | 12 | 16 | 54 | 8 |
| patients | 41 | 33 | 5 | 1 | 0 | 80 | 127 | 285 | 16 |
| profile | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| queue | 6 | 9 | 2 | 1 | 0 | 42 | 26 | 81 | 2 |
| radiology | 74 | 65 | 39 | 24 | 5 | 118 | 322 | 532 | 22 |
| reports | 2 | 2 | 0 | 0 | 18 | 2 | 11 | 38 | 15 |
| revenue | 29 | 17 | 0 | 3 | 0 | 35 | 85 | 129 | 1 |
| scan | 16 | 13 | 27 | 12 | 2 | 20 | 4 | 73 | 6 |
| scribe | 17 | 22 | 0 | 1 | 5 | 37 | 52 | 148 | 7 |
| settings | 15 | 11 | 1 | 2 | 0 | 50 | 139 | 185 | 6 |
| shell | 8 | 1 | 18 | 0 | 37 | 32 | 19 | 50 | 0 |
| subscription | 9 | 24 | 4 | 0 | 0 | 47 | 16 | 93 | 13 |
| support | 4 | 3 | 0 | 0 | 0 | 0 | 3 | 2 | 0 |
| tasks | 1 | 0 | 0 | 0 | 0 | 0 | 10 | 14 | 0 |
| team | 17 | 4 | 0 | 0 | 0 | 7 | 72 | 109 | 1 |
| therapy | 7 | 17 | 27 | 0 | 7 | 11 | 18 | 57 | 20 |
| todos | 9 | 5 | 0 | 0 | 0 | 8 | 21 | 11 | 0 |
| tutorial | 8 | 3 | 1 | 0 | 0 | 3 | 4 | 13 | 1 |
| update | 6 | 8 | 4 | 20 | 5 | 0 | 0 | 29 | 7 |
| voice | 13 | 7 | 4 | 1 | 6 | 0 | 12 | 28 | 7 |

Notes on the table: "reports" has only 2 files but 18 Material Icons. Strict colour/TS for update is 4/20. Campaigns' Cru use is low (11) against 69 raw. Tasks/profile/messaging have almost no UI-level design; check whether they are thin screens or just not built yet.

Totals across features: raw 737 (incl. non-matches from core/shared 56); colour 307 Material + 273 hex in 28 files; TS 123 `TextStyle(` and 115 literal `fontSize:`; Material Icons 194 vs 1,066 CruIcon; Cru widget uses 1,957; literal spacing 4,555 (189 values that are odd and not multiples of 2 or 4; 109 distinct values).

## Literal-value distributions
- Spacing values most used: 12 (108), 0 (104), 8 (82), 6 (68), 10 (68), 16 (67), 4 (62), 1 (59), 2 (54), 14 (46), 1.5 (38), 24 (35), 20 (34). Odd values such as 1.5, 3, 5, 7, 9, 13, 15, 22, 26, 28, 44, 90, 120, 160, 200 do not match the CruSpace scale (s2, s4, s6, s8, s10, s12, s14, s16, s18, s20, s22, s24, s32). Only 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 32 exist as tokens.
- Radius values: 12 (14), 4 (12), 8 (9), 2 (9), 6 (8), 16 (6), 24 (5), 18 (5), 28 (4), 20 (4), 999 (3), 10 (3), 15 (2). CruRadius has no 4, 8, 16, 18, 28 or 20 tokens.
- Font sizes: 16 (13), 14 (13), 11 (10), 13 (9), 12 (9), 18 (8), 10 (7), 15 (6), 8 (5), 28 (5), 9 (4), 13.5 (3), 9.5 (2), 8.5 (2), 26, 24, 22, 15.5, 10.5, 7.5 (1–2 each). Of these, the 8–10 range is probably too small for accessibility.
- Material Colors used: white 145, transparent 70, black 58, grey 4, red 4, redAccent 4, green 4, white24 3. Hex colours repeated: 0xFF64748B (7), 0xFF94A3B8 (6), 0xFF2563EB (6), 0xFFFFFFFF (5), 0xFFF1F5F9 (5), 0xFF1E3A8A (5), 0xFF0F172A (5), 0xFF000000 (5). Most of these have a CruColors equivalent (ink500, ink400 …); check each.

## Detailed findings
Priority: P1 hurts users daily, P2 visible polish, P3 nice to have. Effort: S under 2 h, M under 1 day, L more.

| feature | file:line | what | suggested change | priority | effort |
|---|---|---|---|---|---|
| shared | crudoc_shared/lib/theme/cru_theme.dart | No Cru snackbar helper; 141 `SnackBar(` and 123 `ScaffoldMessenger` calls in the app each style their own | Add `CruToast.show(context, message, tone)` in crudoc_shared and route every SnackBar through it | P1 | M |
| shared | crudoc_shared/lib/widgets/cru | No filter-chip / choice-chip widget; 61 ChoiceChip and 22 FilterChip raw uses | Add CruFilterChip / CruChoiceChip built on CruChip tokens | P1 | S |
| shared | crudoc_shared/lib/widgets/cru | No menu/popup; 16 PopupMenuButton and 21 DropdownMenu raw | Add CruMenuButton and CruDropdownMenu (or make CruDropdownField cover DropdownMenu) | P1 | M |
| shared | crudoc_shared/lib/theme/cru_tokens.dart | Radius/spacing scales lack 4, 8, 16, 18, 20, 28 (radius) and 3, 5, 7, 9, 13, 15, 26, 28, 44 (space); app uses them 1,000+ times | Decide the scale (4/8/12/16/24) and add tokens; migrate literals | P2 | L |
| shared | crudoc_shared/lib/theme/cru_type.dart | No text style for 9–10, 13, 15, 28; 115 literal fontSize values | Add CruType.caption2/body2/title3 to cover real usage | P2 | S |
| shared | crudoc_shared/lib/theme/cru_colors.dart | No semantic colour tokens (danger, success, warning, info, accent-tint per feature); features hard-code them | Add semantic tokens and fold the 273 Color(0x) literals onto them | P1 | M |
| shared | (whole repo) | No i18n: no .arb, no l10n, no AppLocalizations; 383 `Text('…')` literals plus 14 `Text("…")` | Set up flutter gen-l10n and move strings; start with buttons and dialogs | P2 | L |
| shared | (whole repo) | Verb set not standardised (see strings table below) | Write a copy guide (Save/Done/Delete/Remove/Close/Cancel/Back) and fix strings in a single pass | P1 | S |
| dental | features/dental/presentation/dental_inventory_screen.dart:34 (raw 34, colour 28, TS 25) | Worst file: raw DropdownButtonFormField at :86 and :99, TextStyle inline, colour literals | Replace with CruDropdownField, CruTextField, CruText tokens, semantic colours | P1 | M |
| dental | features/dental/presentation/desktop/chart/tooth_render.dart:19 | 19 colour literals in tooth rendering | Likely domain-specific; move palette to a named dental token file | P3 | S |
| dental | features/dental/specialties/ortho/ortho_slider.dart:11 (raw), :21 (colour), :5 TS | Custom slider with raw colours and TextStyle | Use CruSlider (add to Cru) and tokens | P2 | M |
| dental | features/dental/specialties/anaesthesia/drug_log.dart | 9 raw Material matches | Replace with CruButton/CruTextField | P2 | S |
| dental | features/dental/specialties/forms/form_builder.dart | 8 raw matches (form builder) | Use CruFormSection/CruFieldRow | P2 | S |
| dental | features/dental/specialties/prostho/lab_case_dialog.dart | 20 raw matches in a dialog | Replace with CruFormDialog | P1 | S |
| dental | features/dental/presentation/desktop/charting_page.dart:304 and charting_screen.dart:839 | Duplicate private `_OptionRow` (also in appointments and dashboard) and `_Chip` | Extract one CruOptionRow | P2 | S |
| dental | features/dental/specialties/perio/perio_today_card.dart:75 | Private `_Row` duplicates the pattern in 6 other files | Extract shared row widget | P3 | S |
| appointments | features/appointments/presentation/session_details_sheet.dart:169 | AlertDialog with raw `const Text('Delete')` at :204 (no Cru button) | Use CruFormDialog or CruDialog with CruButton | P1 | S |
| appointments | features/appointments/presentation/session_details_sheet.dart:601 and :665 | Private `_StatusPill` and `_SectionLabel` duplicate the Cru pill and label | Replace with CruPill and CruSectionLabel | P2 | S |
| appointments | features/appointments/presentation/session_details_sheet.dart:65 | showModalBottomSheet used directly; 28 such calls in app | Add CruSheet wrapper for the shared handle, radius and padding | P1 | M |
| appointments | features/appointments/presentation/desktop_session_details_dialog.dart:150 | Action label 'Remove' while the phone sheet uses 'Delete' for the same cancel action | Pick one verb (see copy guide) | P1 | S |
| appointments | features/appointments/presentation/desktop_session_details_dialog.dart (21 raw) and session_details_sheet.dart (29 raw) | Two near-duplicate session detail surfaces with divergent widgets | Share one body widget; keep sheet vs dialog as a shell | P1 | M |
| appointments | features/appointments/presentation/appointment_actions.dart (17 raw) | Action sheet uses raw ListTile/IconButton | Replace with CruPressable rows | P2 | S |
| appointments | features/appointments/presentation/widgets/day/appointments_day_view.dart:117 | Private `_LoadError` (also in files, inventory, patients) | Extract CruErrorState | P2 | S |
| appointments | features/appointments/presentation/schedule_visit_sheet.dart:169 | AlertDialog raw | Use CruFormDialog | P2 | S |
| campaigns | features/campaigns/presentation/post_campaign_modal.dart:484, :1087, :797 | 27 raw matches: ChoiceChip ×2, DropdownButton at :797, colour literals 26, TS 12 | Replace chips with CruFilterChip, dropdown with CruDropdownField, tokens | P1 | M |
| campaigns | features/campaigns/presentation/mobile_post_campaign_sheet.dart (18 raw, 14 colour) | Second campaign composer for phone; duplicates the desktop modal | Unify into one responsive composer | P1 | L |
| campaigns | features/campaigns/presentation/campaign_analytics_dialog.dart (12 raw, 12 colour) | Raw dialog and chart colours | Use CruFormDialog and semantic chart tokens | P2 | M |
| campaigns | features/campaigns/data/models/campaign_enums.dart (18 colour) | Colours defined in a data model file | Move colours to a presentation palette | P2 | S |
| campaigns | (feature) | 44 Material Icons vs 13 CruIcon uses (77% Material) | Map to CruIcons set; add missing glyphs | P2 | M |
| homeopathy | features/homeopathy/presentation/homeopathy_case_taking_sheet.dart (21 raw; line not pinned) | Raw sheet controls | Use CruSegmentedControl, CruFormSection | P2 | M |
| files | features/files/presentation/files_actions.dart (16 raw) | Action menu raw | Use CruPopupMenu | P2 | S |
| files | features/files/presentation/nearby_sharing_settings.dart (10 raw), incoming_card.dart (10 raw), send_sheet.dart (9 raw) | Raw Switch/Checkbox/SnackBar | CruSwitch / CruCheckbox (add) / CruToast | P2 | S |
| files | features/files/presentation/files_screen.dart:857 and :998; transfers_sheet.dart:447; files_bars.dart:626 | Duplicated `_NoMatches`, `_LoadError`, `_StatusPill`, `_Chip` (also in inventory, patients, mobile, revenue) | Extract CruEmptyState, CruErrorState, CruPill, CruChip | P2 | M |
| files | features/files/presentation/patient_files_card.dart:326 and files_list.dart:524 | Two `_FileRow` widgets with the same job | One CruFileRow | P2 | S |
| files | features/files/presentation/ (18 colour) | Colours hard-coded for file types | Move to a file-type token map | P3 | S |
| inventory | features/inventory/presentation/widgets/inventory_actions.dart (11 raw) | Raw dialog and menu | CruFormDialog, CruPopupMenu | P2 | S |
| inventory | features/inventory/presentation/desktop_inventory_list_screen.dart (9 raw) | Raw DataTable-style list; no Cru table | Add CruTable/CruDataRow to cru | P2 | M |
| inventory | features/inventory/presentation/inventory_screen.dart:645, :723 | Duplicate `_NoMatches` and `_LoadError` | Shared empty/error states | P2 | S |
| inventory | features/inventory/presentation/widgets/inventory_filter_chips.dart:47 | Private `_Chip` duplicating the filter chip | Use CruFilterChip | P2 | S |
| mobile | features/mobile/mobile_kit.dart:51–52 (palette constants) | 38 colour literals; defines its own palette (neon, deep) rather than CruColors; 17 raw TextStyle | Make mobile_kit a thin wrapper of Cru tokens; delete its palette | P1 | M |
| mobile | features/mobile/mobile_backdrop.dart:48 | 37 colour literals (eve/light switch) hard-coded | Use CruColors per brightness | P1 | S |
| mobile | features/mobile/mobile_revenue.dart (28 colour, 3 TS) and mobile_tasks.dart (26 colour) | Per-screen colours | Use tokens | P2 | S |
| mobile | features/mobile/mobile_island.dart:740 and mobile_revenue.dart:561 | Duplicated private `_Bars` chart widget (also voice ×2) | One CruBarChart | P2 | M |
| mobile | features/mobile/mobile_schedule.dart:1199 | `_StatusPill` duplicate | CruPill | P2 | S |
| mobile | features/mobile/mobile_nav_bar.dart (16 colour) and mobile_island.dart (12) | Nav colours hard-coded | Tokens | P1 | S |
| mobile | (feature) | 42 TextStyle and literal fontSize; phone type scale differs from desktop | Add a phone text scale in CruType | P2 | M |
| onboarding | features/onboarding/presentation/loyalty_card_view.dart:601, :610 (42 colour) | Card design colours hard-coded | Keep as brand art; move to a named constant file | P3 | S |
| radiology | features/radiology/viewer/annotation_painter.dart (23 colour) | Painter colours | Viewer palette constant | P3 | S |
| radiology | features/radiology/presentation/reports/report_editor_screen.dart:37 and :9 raw | Private `_Section` class and raw controls | CruFormSection | P2 | M |
| radiology | features/radiology/viewer/side_panel.dart:259 | Duplicate `_SectionLabel` (also in appointments, patients, team) and 8 raw matches | Shared CruSectionLabel | P2 | S |
| radiology | features/radiology/viewer/viewer_phone_bar.dart:171 | Duplicate `_Row` | Shared row | P3 | S |
| radiology | features/radiology/presentation/radiology_cards.dart:167 | Duplicate `_Row` | Shared row | P3 | S |
| radiology | (feature) | 24 TextStyle + fontSize; 65 raw | Migrate | P2 | M |
| patients | features/patients/presentation/patient_form.dart:420 and :452 | Form uses CruTextField at :420 and raw TextFormField at :452; 17 raw matches; private `_SectionLabel` at :391 | Make the whole form use CruTextField/CruFormSection; this is the form the owner called too complex | P1 | M |
| patients | features/patients/presentation/patient_actions.dart:30, :52 | ScaffoldMessenger direct calls | CruToast | P2 | S |
| patients | features/patients/presentation/widgets/details/visit_session_dialog.dart:478, :675 | Duplicate `_Section` and `_FileRow` | Shared | P2 | S |
| patients | features/patients/presentation/widgets/details/medical_history_card.dart:87 | Private `_Row` class | Shared row | P3 | S |
| settings | features/settings/presentation/storage_section.dart:222 | Duplicate `_Row` | Shared row | P3 | S |
| settings | features/settings/presentation/ai_assistance_section.dart, call_forwarding_section.dart | Settings uses raw SwitchListTile | CruSwitchRow | P2 | S |
| revenue | features/revenue/presentation/desktop_invoices_screen.dart:639 | Duplicate `_StatusPill` (also in files, mobile_schedule) and 11 raw matches | CruPill | P2 | S |
| revenue | (feature) | 85 Cru uses but 17 raw and 129 literal spacing | Keep; migrate spacing | P3 | S |
| subscription | features/subscription/presentation/apple_checkout_list.dart (12 raw) | Raw ListTile/buttons on paywall (highest-stakes surface) | CruCard + CruButton; check tone/copy | P1 | M |
| update | features/update/presentation/update_available_dialog.dart (18 colour, 5 TS) | Raw dialog, own colours | CruFormDialog, tokens | P2 | S |
| update | features/update/presentation/update_progress_sheet.dart (4 TS) | Raw TextStyle | CruType | P3 | S |
| update | (feature) | 20 TextStyle/fontSize, 0 Cru uses | Adopt Cru | P2 | M |
| scan | features/scan/presentation/document_camera_page.dart (19 colour) | Camera overlay colours | Overlay token | P3 | S |
| scan | features/scan/data/record_pdf.dart (10 TS) | PDF TextStyle (ok, PDF theme) | Use pdf_template_theme.dart | P3 | S |
| therapy | features/therapy/presentation/physio_comparison_dialog.dart (12 raw, 14 colour) | Raw dialog and colours | CruFormDialog, tokens | P2 | S |
| therapy | (feature) | 27 colour, 7 Material Icons | Tokens and CruIcon | P2 | S |
| shell | features/shell/components/cru_sidebar.dart (17 colour) | Sidebar colours (should be CruColors) | Tokens | P1 | S |
| shell | features/shell/presentation/desktop_shell.dart:223–224 and shell (37 Material Icons) | Nav icons mix Material Icons.* and CruIcons | Use CruIcon for nav set | P1 | S |
| shell | features/shell/components/mobile_feature_disabled_view.dart | Mixed icon sets | CruIcon | P3 | S |
| voice | features/voice/presentation/voice_bubble.dart:236 and voice_overlay.dart:1016 | Duplicate `_Bars` (also mobile ×2) | Shared bar | P3 | S |
| queue | features/queue/ (9 raw, 42 CruIcon) | Mostly on-system | Migrate 9 raw | P3 | S |
| todos | features/todos/ (5 raw) | Mostly on-system | Migrate | P3 | S |
| tutorial | features/tutorial/ (3 raw, 1 colour) | Tutorial overlay | Keep on tokens | P3 | S |
| team | features/team/ (4 raw) | Clean; Cru 72 | None beyond spacing | P3 | S |
| auth | features/auth/ (1 raw, 1 colour) | Clean | None | P3 | S |
| support, tasks, profile, messaging, reports | (see table) | Very few or no widgets; reports has 18 Material icons on 2 files | Check whether screens are built; reports icons to CruIcon | P3 | S |

Copy inventory (string literal counts, all features):

| action | variants and counts |
|---|---|
| Save | 'Save' 16; `submitLabel: 'Save'` in endo_dialog.dart:369; not verified in all forms |
| Done | 'Done' 40 (as a dialog close and as an action) |
| Submit | 0 |
| OK | 1 (Ok 0) |
| Delete | 'Delete' 30 |
| Remove | 'Remove' 24 |
| Cancel | 'Cancel' 46 |
| Close | 'Close' 43 |
| Back | 'Back' 32 |
| Discard | 'Discard' 7 |
| Retry | 'Retry' 3; 'Try again' 11 |
| Undo | 'Undo' 8 |
| Confirm | 1 |
| Continue / Next | 3 / 3 |

Fix: pick Save for forms, Done only for read-only sheets, Delete for destructive, Remove only for detaching a link, Close for read-only dialogs and Cancel for abort, Back only for navigation, Try again for errors. Apply once.

## 10 changes that would make the app look most uniform
1. Add a CruToast helper and route all 264 SnackBar and ScaffoldMessenger calls through it.
2. Add CruFilterChip / CruChoiceChip and replace 83 raw chip uses.
3. Add CruMenuButton and CruDropdownMenu, replacing 16 PopupMenuButton and 21 DropdownMenu uses, plus 35 DropdownButton.
4. Add CruSheet (handle, radius, padding) and route the 28 showModalBottomSheet calls through it; route AlertDialog (13) through CruFormDialog.
5. Replace the 273 Color(0x…) literals with semantic CruColors tokens, starting with mobile_kit.dart, mobile_backdrop.dart, loyalty_card_view.dart and cru_sidebar.dart.
6. Make mobile_kit.dart a thin wrapper over Cru tokens and remove its own palette.
7. Extend CruType with the sizes actually used (9–10, 13, 15, 28) and replace 123 TextStyle( and 115 fontSize literals.
8. Consolidate the spacing and radius scales (fix 189 odd spacing values, 4/8/16/20 radius) into the CruSpace and CruRadius tokens.
9. Extract shared private widgets: _Row (7), _StatusPill (4), _SectionLabel (4), _LoadError (4), _NoMatches (3), _Chip (3), _OptionRow (3), _FileRow (3), _Bars (4) into Cru.
10. Set up gen-l10n and a single copy guide for Save, Done, Delete, Remove, Close, Cancel, Back, Try again; fix the 383 Text literals.

Immediate single-file checks for the owner: patient_form.dart (mixed CruTextField and TextFormField), session_details_sheet.dart (raw AlertDialog with a raw Text('Delete')), apple_checkout_list.dart (raw controls on the paywall), cru_sidebar.dart (17 colour literals in the sidebar).
