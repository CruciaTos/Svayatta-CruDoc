# Inventory: phone, tablet and desktop coverage

## Summary
1. Layout is chosen once by width: `lib/features/shell/presentation/responsive_shell.dart:23` `kDesktopBreakpoint = 900`; `:116` `maxWidth >= 900` gives `DesktopShell` (846 lines), otherwise `MobileShell` (`lib/features/mobile/mobile_shell.dart`, 298 lines). No platform check decides layout.
2. Tablets have no layout of their own: landscape tablets (900+ dp) get the desktop sidebar shell, portrait tablets (768 to 899 dp) get the stretched phone shell. Only CBCT uses a tablet test (`lib/features/radiology/cbct/cbct_device.dart:18`, `shortestSide >= 600`).
3. Phone has 5 tabs (Home, Schedule, Patients, Tasks, More) plus a few sub-screens (invoices, revenue, campaigns, todos, notifications, wave, island). Dental charting, radiology viewer/CBCT, full inventory, queue, scribe, reports, homeopathy, therapy and settings have no phone screen (see matrix).
4. Responsiveness risks: 60 fixed-size literals of 400+ px in dialogs/containers (e.g. 920, 980, 960 px wide dialogs in dental), 15 files with hover (`onHover`/`MouseRegion`) and no touch alternative, 3 files handling keyboard insets, and `resizeToAvoidBottomInset: false` on the phone shell (`mobile_shell.dart:188`).
5. Desktop niceties exist but are thin: 14 files with `Shortcuts`/`CallbackShortcuts`, 7 files with secondary-tap/context-menu, 40 files with focus handling, 16 `Tooltip`s, 0 `DataTable`s (tables are custom widgets, 24 horizontal scroll views).

## Layout decision map
| Mechanism | Where | Notes |
|---|---|---|
| Width switch | `shell/presentation/responsive_shell.dart:23,116` | Single breakpoint 900 dp |
| Desktop shell | `shell/presentation/desktop_shell.dart` (846 lines) | Sidebar, tabs (`shell/components/desktop_page_tabs.dart`), `Shortcuts` at `:449` |
| Phone shell | `mobile/mobile_shell.dart` (298 lines), `mobile/mobile_nav_bar.dart` | Routes tabs at `:147-151`; `resizeToAvoidBottomInset: false` at `:188` |
| Disabled-module view | `shell/components/mobile_feature_disabled_view.dart`, used at `mobile_shell.dart:133` and `desktop_shell.dart:582` | Same fallback on both shells |
| Tutorial split | `responsive_shell.dart:118-125` | Separate tour per layout |
| Voice overlay | `voice/presentation/voice_overlay.dart:286` | Own `< 900` check |
| Platform checks | 37 files reference `defaultTargetPlatform`/`Platform.is*` (e.g. `core/utils/device_info_helper.dart`, `features/files/lan/device_identity.dart`) | Used for OS features, not layout |
| Folder naming | `*/presentation/desktop/` (dental, 14 files), `desktop_*.dart` (about 30 files), `mobile/mobile_*.dart` (17 files), `*mobile_post_campaign_sheet.dart` | Desktop and phone variants are separate files, not one responsive widget |

## Per-feature matrix
Counts from file names and folders. "Phone" = screen under `features/mobile` or a phone-specific widget. Mobile-reference counts are a crude grep for the word "mobile" in a feature folder.

| Feature | Dart files | Desktop-named files | Mobile-referencing files | Desktop | Phone | Tablet |
|---|---|---|---|---|---|---|
| appointments | 56 | 2 (`desktop_schedule_visit_dialog`, `desktop_session_details_dialog`) | 4 | Yes (week/day/month + side sheet) | Yes via Schedule tab | Via shell |
| auth | 2 | 0 | 2 (`phone_auth_sheet.dart`) | Yes | Yes | Via shell |
| campaigns | 12 | 1 (`desktop_campaigns_screen`) | 2 (`mobile_post_campaign_sheet`, `mobile/mobile_campaigns`) | Yes | Yes (sheet) | Via shell |
| dashboard | 19 | 0 | 2 | Yes | Home tab (`mobile/mobile_home`) | Via shell |
| dental | 78 | 1 (`presentation/desktop/` folder, 14 files) | 1 | Yes (chart, perio, ortho, forms) | No | Landscape only |
| files | 51 | 0 | 3 | Yes (`files_panel`, `files_screen`) | No dedicated screen; reached via patient | No |
| homeopathy | 17 | 0 | 3 | Yes | No | No |
| inventory | 37 | 3 (`desktop_inventory_list_screen`, two dialogs) | 3 | Yes | Not found | No |
| messaging | 15 | 0 | 3 | Yes (data layer) | Not found | No |
| onboarding | 4 | 0 | 0 | Shared flow | Shared flow | Shared |
| patients | 41 | 1 (`desktop_add_edit_patient_dialog`) | 4 | Yes | Yes (`mobile/mobile_patients`) | Via shell |
| profile | 1 | 0 | 0 | Data only | Not found | No |
| queue | 6 | 1 (`desktop_queue_screen`) | 0 | Yes | Not found (module key only, `mobile_shell.dart:102`) | No |
| radiology | 74 | 0 | 1 | Yes (viewer, DICOM, CBCT) | Viewer phone bar only (`viewer/viewer_phone_bar.dart`); CBCT gated to shortestSide >= 600 | Partial (CBCT only) |
| reports | 2 | 0 | 0 | Yes | Not found | No |
| revenue | 29 | 3 (`desktop_invoices_screen`, `desktop_create_invoice_dialog`, `desktop_add_transaction_dialog`) | 3 | Yes | Yes (`mobile_revenue`, `mobile_invoices`) | Via shell |
| scan | 16 | 0 | 5 | Yes (`document_camera_page`) | Camera on phone | No |
| scribe | 17 | 1 (`desktop_scribe_screen`) | 3 | Yes | Not found | No |
| settings | 15 | 1 (`desktop_settings_screen`) | 3 | Yes | Via More tab | No |
| subscription | 9 | 0 | 2 | Yes | Limited | No |
| support | 4 | 0 | 0 | Yes | Not found | No |
| tasks | 1 | 0 | 1 | Data only | Yes (`mobile/mobile_tasks`) | Via shell |
| team | 17 | 0 | 2 (`contact_invite_picker`) | Yes | Invite picker only | No |
| therapy | 7 | 0 | 0 | Yes (muscle chart) | Not found | No |
| todos | 9 | 0 | 2 | Yes | Yes (`mobile/mobile_todos`) | Via shell |
| tutorial | 8 | 0 | 7 | Separate tours | Separate tours | Per layout |
| update | 6 | 0 | 0 | Desktop installer | Not applicable | No |
| voice | 13 | 0 | 6 | Yes (overlay) | Yes (overlay, bottom sheet) | Via shell |

Phone-only screens (no desktop counterpart): `mobile/mobile_home.dart`, `mobile_wave.dart`, `mobile_island.dart`, `mobile_more.dart`, `mobile_notifications.dart`, `mobile_kit.dart`, `mobile_backdrop.dart`, `mobile_nav_bar.dart`, `activity/`, `tasks/`.

Desktop-only screens (no phone counterpart): dental `presentation/desktop/*` (chart, tooth detail, perio, ortho, forms, anaesthesia), `desktop_queue_screen.dart`, `desktop_scribe_screen.dart`, `desktop_settings_screen.dart` (phone reaches settings via More), `desktop_inventory_list_screen.dart`, `desktop_campaigns_screen.dart` (phone has only a sheet).

## Tablets
- Breakpoint 900 dp means: iPad portrait (768 or 820 dp) gets the phone shell with a 5-tab nav bar stretched across the screen; iPad landscape (1024+) gets the desktop sidebar.
- No tablet-specific two-pane, master-detail or grid layout was found in the feature folders.
- Only tablet-specific gate: `radiology/cbct/cbct_device.dart:18` (`shortestSide >= 600`).

## Detailed findings
Priority: P1 hurts users daily, P2 visible polish, P3 nice to have. Effort: S under 2 hours, M under 1 day, L more.

| feature | file:line | what | suggested change | priority | effort |
|---|---|---|---|---|---|
| shell | `shell/presentation/responsive_shell.dart:23,116` | One 900 dp breakpoint; portrait tablets (768 to 899 dp) get the phone shell | Add a tablet tier (600 to 899) with a rail or two-pane layout; test on 768 and 820 dp | P1 | M |
| mobile | `mobile/mobile_shell.dart:188` | `resizeToAvoidBottomInset: false` on the whole phone scaffold; any input behind the keyboard is not moved | Remove the flag or wrap each sheet with `viewInsets` padding; check every text field on phone | P1 | M |
| patients | `patients/presentation/patient_form.dart:744,921` | Only two screens handle `viewInsets`; other forms on phone (e.g. `phone_auth_sheet.dart:231`) rely on sheet padding | Standard keyboard-safe scroll wrapper for all forms | P1 | S |
| dental | `dental/specialties/ortho/ortho_slider.dart:175` | Fixed `width: 960` dialog content | Use `LayoutBuilder` and fill available width below 900 dp; or a phone-specific screen | P1 | M |
| dental | `dental/specialties/ortho/ortho_slider.dart:329,371,587` | Fixed heights 440, 480, 700 px | Replace with `Expanded` or a fraction of constraints | P1 | S |
| dental | `dental/specialties/ortho/ortho_photos.dart:400` | Fixed `width: 960` | As above | P1 | S |
| dental | `dental/specialties/forms/form_builder.dart:250` | Fixed `width: 980` builder dialog | Full-screen route below 900 dp | P2 | M |
| dental | `dental/specialties/forms/form_fill.dart:174,505,539` | Fixed widths 660, 720, 480 | `ConstrainedBox(maxWidth)` plus `width: double.infinity` in a `Dialog` with insets | P1 | S |
| dental | `dental/specialties/anaesthesia/drug_log.dart:285` | Fixed `width: 920` | Constrain to viewport; scroll horizontally for table | P1 | S |
| dental | `dental/records/perio_staging.dart:496` | `maxWidth: 980` perio staging | Keep as full screen on phone; check tooth grid touch size | P2 | M |
| dental | `dental/presentation/desktop/tooth_detail_view.dart:1403-1407` | `MouseRegion.onHover` drives tooth detail; no tap/long-press equivalent | Add `onTap`/long-press path for touch | P1 | S |
| dental | `dental/specialties/prostho/lab_case_dialog.dart:270,678` | Fixed widths 600, 560 | Constrain to viewport | P2 | S |
| dental | `dental/referrals/referral_dialogs.dart:383,803,927,1133,1184` | Five fixed-width dialogs (480 to 580 px) | Constrain or make bottom sheets on phone | P2 | S |
| dental | `dental/referrals/referral_share_flows.dart:364,717,866,905,1109` | Five fixed-width dialogs (460 to 600 px) | As above | P2 | S |
| dental | `dental/records/srp_dialog.dart:93`, `charting_screen.dart:417`, `dental_ui.dart:838`, `forms_screen.dart:187` | `maxWidth` 420 to 680 | Fine on tablet; check phone | P3 | S |
| core/pdf | `core/pdf/presentation/editor/template_editor_screen.dart:537-538` | Fixed 800 x 700 editor | Desktop-only editor: state it is desktop-only and hide the phone entry point | P2 | S |
| core | `core/people/person_picker.dart:126` | Fixed `width: 520` | Constrain to viewport | P2 | S |
| appointments | `appointments/presentation/patient_picker_dialog.dart:91` | `maxWidth 540, maxHeight 620` | Fine; confirm keyboard inset on phone | P3 | S |
| campaigns | `campaigns/presentation/post_campaign_modal.dart:43,1177,1337` | Modal 880 x 720; inner 580 and 420 | Phone uses `mobile_post_campaign_sheet`; confirm the sheet is the only path on phone | P2 | S |
| campaigns | `campaigns/presentation/campaign_analytics_dialog.dart:35` | 880 x 720 dialog | Phone has no analytics view | P2 | M |
| inventory | `inventory/presentation/desktop_add_edit_medicine_dialog.dart` (2 matches) | Desktop dialog; phone has no medicine add/edit | Add phone form or bottom sheet | P1 | M |
| revenue | `revenue/presentation/desktop_create_invoice_dialog.dart`, `desktop_add_transaction_dialog.dart` | Desktop dialogs; phone has `mobile_invoices.dart` only | Confirm phone create-invoice coverage | P2 | M |
| queue | `queue/presentation/desktop_queue_screen.dart` | Queue exists only on desktop; phone module key only | Decide: phone queue screen for waiting list (high use at reception) | P1 | M |
| scribe | `scribe/presentation/desktop_scribe_screen.dart` | Scribe desktop only | Phone capture-only mode (audio record + upload) | P2 | M |
| radiology | `radiology/cbct/cbct_device.dart:18` | CBCT gated to `shortestSide >= 600`; phone cannot run CBCT | Keep the gate, but show a clear "use tablet or PC" message | P2 | S |
| radiology | `radiology/viewer/viewer_screen.dart:1` | Desktop viewer; phone has `viewer_phone_bar.dart` only | Test phone viewer on real DICOM set; tablet layout | P1 | M |
| shell | `shell/presentation/desktop_shell.dart:582` | Disabled-module fallback on desktop | Consistent with phone; no action | P3 | S |
| voice | `voice/presentation/voice_overlay.dart:286` | Own `< 900` check, separate from the shell breakpoint | Use a shared breakpoint constant | P3 | S |
| shell | `shell/presentation/desktop_shell.dart:449` | `Shortcuts` used on desktop only; no shortcut help screen found | Add `?` overlay listing shortcuts | P3 | S |
| patients | `patients/presentation/patients_screen.dart:339` | Desktop `Shortcuts` on patients list | Keep; mirror on phone search | P3 | S |
| all | 15 files with `onHover`/`MouseRegion` (e.g. `dental/presentation/desktop/tooth_detail_view.dart:1403`) | Hover-only affordances | Add tap or long-press equivalents on each | P1 | M |
| all | 7 files with secondary tap or context menu | Right-click only actions | Add long-press menu on phone | P2 | S |
| all | 85 matches of compact `IconButton` / `VisualDensity.compact` / `padding: EdgeInsets.zero` / `iconSize` 10-19 | Touch targets under 40 px likely | Global `IconButton` theme with minimum 40 px on phone | P1 | M |
| all | 16 `Tooltip(` usages | Tooltip-only labels are invisible on touch | Replace with visible labels on phone | P2 | S |
| all | 24 horizontal scroll views | Tables use custom widgets, not `DataTable`; check each for scroll affordance | Add fade or scrollbar and a minimum column width | P2 | M |
| all | 3 SafeArea uses in `features/mobile` | Notch and home-indicator overlap risk on phone | Wrap every phone route in `SafeArea` (check `mobile_island.dart`, `mobile_wave.dart`) | P1 | S |
| all | 40 files with `FocusNode`/`Focus(` but 151 keyboard listener matches | Focus rings not verified; keyboard coverage uneven | Visible focus ring in `cru` widgets; test Tab order on desktop | P2 | M |
| settings | `settings/presentation/desktop_settings_screen.dart` | Desktop settings; phone reaches via More | Verify all settings reachable on phone; document missing ones | P2 | M |
| mobile | `mobile/mobile_more.dart` | More tab is the only route to many screens (settings, team, files, scribe) | Consider grouping More into sections | P2 | S |
| mobile | `mobile/mobile_home.dart:210,212` | Skeleton `_Bone` sizes fixed (190x22, 240x14) | Fine; check at 320 dp width | P3 | S |
| mobile | `mobile/mobile_patients.dart:640`, `mobile_revenue.dart:200,332`, `mobile_schedule.dart:422`, `mobile_tasks.dart:1073` | Loading placeholders with fixed heights 160 to 200 | Use shimmer sized to content | P3 | S |
| mobile | `mobile/mobile_revenue.dart:310` | `kMobileRevenueCardHeight = 236` fixed card height | Text scale 1.3 can clip; use min height | P2 | S |
| dental | `dental/presentation/desktop/chart/tooth_art.dart`, `tooth_render.dart` | Canvas drawing sized from shortest side; no fixed sizes | Check on 320 dp and tablet | P3 | M |
| files | `files/presentation/widgets/files_panel.dart` | Files panel built for desktop; no phone screen | Phone file browser | P2 | L |
| team | `team/presentation/contact_invite_picker.dart` | Invite picker only on phone | Full team management on phone | P3 | M |
| homeopathy, therapy, reports | `homeopathy/`, `therapy/muscle_chart/muscle_chart_view.dart:1`, `reports/presentation/` | No phone screens; muscle chart is touch-heavy | Decide phone scope per specialty; muscle chart on tablet first | P2 | L |
| update | `update/presentation/update_launcher.dart:1` | Desktop-only installer | Mark as not applicable to phone | P3 | S |

## 10 screens most likely to break on a phone
1. Dental ortho slider: `dental/specialties/ortho/ortho_slider.dart:175,329,371,587` (960 px wide, 440 to 700 px heights).
2. Dental ortho photos: `dental/specialties/ortho/ortho_photos.dart:296,400` (800 x 700, 960 px).
3. Dental form builder: `dental/specialties/forms/form_builder.dart:250` (980 px).
4. Dental form fill: `dental/specialties/forms/form_fill.dart:174,505,539` (660, 720, 480 px).
5. Anaesthesia drug log: `dental/specialties/anaesthesia/drug_log.dart:285` (920 px).
6. Perio staging: `dental/records/perio_staging.dart:496` (980 px max) plus `tooth_detail_view.dart:1403` hover.
7. Template editor: `core/pdf/presentation/editor/template_editor_screen.dart:537` (800 x 700).
8. Campaign analytics: `campaigns/presentation/campaign_analytics_dialog.dart:35` (880 x 720).
9. Referral dialogs: `dental/referrals/referral_dialogs.dart:383,927,1184` (560 to 580 px).
10. Medicine add/edit: `inventory/presentation/desktop_add_edit_medicine_dialog.dart` (desktop dialog reached from desktop inventory).

## 10 important screens missing on phone or tablet
1. Dental chart (`dental/presentation/desktop/charting_page.dart`, `tooth_detail_view.dart`): core for dental clinics; needs tablet first.
2. Radiology viewer and CBCT (`radiology/viewer/viewer_screen.dart`, `radiology/cbct/`): phone has only a bar; CBCT blocked below 600 dp.
3. Queue (`queue/presentation/desktop_queue_screen.dart`): reception needs this on a tablet at the desk.
4. Inventory list and add/edit (`inventory/presentation/desktop_inventory_list_screen.dart`): no phone equivalent.
5. Scribe (`scribe/presentation/desktop_scribe_screen.dart`): no phone capture mode.
6. Files manager (`files/presentation/files_screen.dart`, `widgets/files_panel.dart`): no phone browser.
7. Settings (`settings/presentation/desktop_settings_screen.dart`): reachable only through More; check coverage.
8. Homeopathy (`homeopathy/presentation/`) and therapy muscle chart (`therapy/muscle_chart/muscle_chart_view.dart`): no phone screens.
9. Reports (`reports/presentation/`): no phone screen.
10. Team management and roles (`team/presentation/`): only the invite picker on phone.

## Counts
- Dart files in `lib`: 717 (about 272,600 lines).
- Layout breakpoints: 1 (`kDesktopBreakpoint`), plus 2 ad hoc checks (`cbct_device.dart:18`, `voice_overlay.dart:286`).
- Fixed size literals of 400 px or more in `width`/`height`/`maxWidth`: 60.
- Files with hover handling: 15. Files with keyboard shortcuts: 14. Files with secondary tap/context menu: 7.
- Files with keyboard-inset handling: 3. Phone shell with resize disabled: 1.
- Compact or small-icon matches (touch-target risk): 85.
- Tooltips: 16. DataTables: 0. Horizontal scroll views: 24.
