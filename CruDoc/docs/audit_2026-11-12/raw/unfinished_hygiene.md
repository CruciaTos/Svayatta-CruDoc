# Inventory: unfinished work, dead ends, hygiene (2026-11-12)

## Summary
1. lib/ has 717 Dart files. Exactly 1 TODO (encryption_key_manager.dart:123). Bare print( = 0. debugPrint( = 262 calls.
2. Dead or no-op controls: about 9 real ones (campaigns x2, radiology worklist, prostho lab filter, inventory "Add Item", mobile_more 5 tips, plus IgnorePointer menu anchors). Raw grep hits for onPressed/onTap no-ops: 22.
3. Files over 1500 lines: 20 (largest voice_controller.dart 3120, viewer_screen.dart 3054).
4. Feature folders with no test file referencing them (heuristic): auth, profile, reports, tasks, therapy, todos, update.
5. Repo hygiene: 723 tracked files under tool/voice_server/.venv.old-empty (Python venv binaries), 2 tracked zips of about 1.2 MB and 1.5 MB, a tracked 1.1 MB .mp4, duplicate docs in docs/ and handoff/, and about 27 Antigravity briefs in handoff/.

Counting method: Grep/Bash over lib/, test/, integration_test/. The test column counts test files that contain the string features/<name>/, which is an import heuristic, not coverage.

## Per-feature table
| feature | lib files | test refs | placeholder / dead / flag hits | note |
|---|---|---|---|---|
| appointments | 56 | 20 | 3 no-op taps (agenda_view:147, day_grid:364, week_grid:276,305) | visits_repo:165 "for now" comment |
| auth | 2 | 0 | none | no tests |
| campaigns | 12 | 1 | 2 dead controls (desktop:288, 451); WhatsApp "not available yet" (service:56-58, modal:1067, mobile_sheet:678) | WhatsApp campaigns not shipped |
| dashboard | 19 | 23 | 0 | well covered |
| dental | 78 | 12 | prostho scan_viewer_placeholder.dart (233 lines, used by lab_case_dialog:622); dead filter lab_cases_screen:210 | largest feature by files |
| files | 51 | 7 | 8 keyword hits in files_repository.dart; file_viewer 4 | LAN sharing |
| homeopathy | 17 | 5 | GEMINI key via env (voice_scribe_service:25) | |
| inventory | 37 | 11 | "Add Item" no-op (list_screen:618 "Mock action"); onPressed null (inventory_actions:91,116); desktop_inventory_list_screen 1733 lines | _PlaceholderScreen = real empty states, OK |
| messaging | 15 | 8 | 0 | |
| mobile | 19 | 4 | 5 no-op onTap in mobile_more.dart:611-639 | gesture tips sheet |
| onboarding | 4 | 2 | 0 | |
| patients | 41 | 23 | 1 keyword (desktop_add_edit_patient_dialog) | |
| profile | 1 | 0 | none | no tests |
| queue | 6 | 12 | kDebugMode console gate (queue_local_service:426) | desktop_queue_screen 2009 lines |
| radiology | 74 | 16 | dead filter worklist_screen:342; RAD_PROGRESSIVE dart-define flag (rad_progressive_flag.dart:10); viewer_pane 15 keyword hits | viewer_screen 3054 lines, ceph_screen 1503 lines |
| reports | 2 | 0 | none | no tests |
| revenue | 29 | 11 | 4 keyword hits in collections_by_day_card (stub bars, legit) | |
| scan | 16 | 2 | 0 | low test coverage |
| scribe | 17 | 8 | 0 | |
| settings | 15 | 5 | 1 keyword | desktop_settings_screen 1575 lines |
| shell | 8 | 9 | 1 keyword (cru_sidebar) | |
| subscription | 9 | 3 | mock checkout branch in prod UI (payment_checkout_sheet:101,371,468,561; plan_payment.dart:43,62; doctor_subscription_service:200) | P1 risk |
| support | 4 | 3 | 0 | |
| tasks | 1 | 0 | none | single file, no tests |
| team | 17 | 6 | 0 | clinic_team_api 2 debugPrint |
| therapy | 7 | 0 | "not available on this device" text (muscle_chart_view:125) | no tests |
| todos | 9 | 0 | 2 keyword hits (todo_dialog) | no tests |
| tutorial | 8 | 3 | 0 | |
| update | 6 | 0 | Android install bridge not implemented (android_update_installer:112); kDebugMode gate (update_launcher:38) | no tests |
| voice | 13 | 5 | voice_controller 3120 lines; voice_command 2181 lines | |
| core/ + shared/ | n/a | n/a | onPressed scan: none in core widgets; visit_location_map 5 keyword hits | core services: encryption_key_manager TODO |

## Detailed findings
| feature | file:line | what | suggested change | priority | effort |
|---|---|---|---|---|---|
| subscription | lib/features/subscription/presentation/payment_checkout_sheet.dart:101,371,468,561 | Mock checkout path (checkout.mock) runs in shipping UI | Confirm mock is server-only test mode; hide mock UI behind kDebugMode or remove before store release | P1 | M |
| inventory | lib/features/inventory/presentation/desktop_inventory_list_screen.dart:618 | "Add Item" TextButton with onPressed: () {} and comment "Mock action" | Wire to add-to-vendor flow or hide the button | P1 | M |
| update | lib/core/update/platform/android_update_installer.dart:108-114 | Native MethodChannel crudoc/update_installer not implemented, throws UpdateInstallException | Implement MainActivity.kt handler or disable in-app Android update | P1 | M |
| campaigns | lib/features/campaigns/presentation/desktop_campaigns_screen.dart:288 | Filter CruButton with onPressed () {} inside IgnorePointer (popup anchor) | Use real popup anchor with the filter selection | P2 | S |
| campaigns | lib/features/campaigns/presentation/desktop_campaigns_screen.dart:451 | "More" CruIconButton onPressed: null inside IgnorePointer | Replace with working menu or remove | P2 | S |
| campaigns | lib/features/campaigns/data/services/campaign_dispatch_service.dart:56-58 | WhatsApp campaigns "not available yet" user message | Decide ship date or hide WhatsApp channel option until ready | P2 | S |
| campaigns | lib/features/campaigns/presentation/post_campaign_modal.dart:1067 | "Use Email for now." helper text | Copy review with WhatsApp plan | P3 | S |
| campaigns | lib/features/campaigns/presentation/mobile_post_campaign_sheet.dart:678 | Same "Use Email for now" on mobile | Same as above | P3 | S |
| mobile | lib/features/mobile/mobile_more.dart:611,618,625,632,639 | Five tip rows with onTap: () {} in gesture tips sheet | Make rows demos or non-tappable (no ripple) | P2 | S |
| radiology | lib/features/radiology/presentation/worklist_screen.dart:342 | Type filter CruButton onPressed () {} inside IgnorePointer | Real filter popup anchor, same pattern as campaigns | P2 | S |
| dental | lib/features/dental/specialties/prostho/lab_cases_screen.dart:210 | Stage filter CruButton onPressed () {} inside IgnorePointer | Real filter popup anchor | P2 | S |
| inventory | lib/features/inventory/presentation/widgets/inventory_actions.dart:91,116 | CruSquareButton onPressed null inside ListTile with onTap elsewhere | Remove duplicate null button or wire icon tap | P3 | S |
| appointments | lib/features/appointments/presentation/widgets/week/week_grid.dart:305 | DayBlock onTap: () {} and onDoubleTap: () {} | Check whether parent handles tap; if not, open visit | P2 | S |
| appointments | lib/features/appointments/presentation/widgets/agenda/appointments_agenda_view.dart:147 | AgendaRow onTap: () {} | Open visit detail on tap | P2 | S |
| appointments | lib/features/appointments/presentation/widgets/day/day_grid.dart:364 | onTap: () {} | Verify if intentional; else open detail | P3 | S |
| dental | lib/features/dental/specialties/prostho/scan_viewer_placeholder.dart:1-233 | Screen named Placeholder used from lab case dialog (line 178 "Honest placeholder note") | Build real scan viewer or rename and show real empty state | P2 | M |
| radiology | lib/features/radiology/data/rad_progressive_flag.dart:10 | Progressive DICOM loading gated by bool.fromEnvironment('RAD_PROGRESSIVE') | Document build flag; decide default on | P2 | S |
| main | lib/main.dart:57-65 | _useFirebaseEmulators and emulator host from dart-define | Keep; ensure release builds never set it | P3 | S |
| auth | lib/core/services/demo_session_service.dart:14 | loginEnabled from bool.fromEnvironment | Confirm off in release builds | P2 | S |
| core | lib/core/services/encryption_key_manager.dart:123 | Only TODO in lib: TODO(security-upgrade) pepper-based threat model | Track in security plan (SEC-* tasks) | P2 | M |
| core | lib/core/services/*, lib/features/** | 262 debugPrint calls across about 95 files, zero bare print | Route through one logger with levels; strip verbose logs in release | P3 | M |
| queue | lib/features/queue/data/services/queue_local_service.dart:426 | kDebugMode-only block | Keep; check it has no PII | P3 | S |
| update | lib/features/update/controllers/update_controller.dart:197 | kDebugMode block | Keep | P3 | S |
| core | lib/core/services/callable_client.dart:39-42 | Emulator flag and host | Keep | P3 | S |
| voice | lib/features/voice/voice_controller.dart | 3120 lines | Split: session, commands, UI state | P2 | L |
| radiology | lib/features/radiology/viewer/viewer_screen.dart | 3054 lines | Split: toolbar, panes, measurements | P2 | L |
| homeopathy | lib/features/homeopathy/presentation/homeopathy_case_taking_sheet.dart | 2906 lines | Split per section | P2 | L |
| dental | lib/features/dental/presentation/desktop/chart/tooth_art.dart | 2827 lines | Split by tooth group and painter | P2 | L |
| dental | lib/features/dental/presentation/desktop/tooth_detail_view.dart | 2318 lines | Split tabs into files | P2 | L |
| voice | lib/features/voice/domain/voice_command.dart | 2181 lines | Split command families | P2 | M |
| queue | lib/features/queue/presentation/desktop_queue_screen.dart | 2009 lines | Split panels | P2 | M |
| core | lib/core/services/local_database_service.dart | 2004 lines | Split by table DAO | P2 | L |
| mobile | lib/features/mobile/mobile_kit.dart | 1832 lines | Split widgets | P2 | M |
| revenue | lib/features/revenue/presentation/desktop_create_invoice_dialog.dart | 1756 lines | Split steps | P2 | M |
| mobile | lib/features/mobile/mobile_schedule.dart | 1747 lines | Split | P2 | M |
| inventory | lib/features/inventory/presentation/desktop_inventory_list_screen.dart | 1733 lines | Split list, empty states, details | P2 | M |
| radiology | lib/features/radiology/presentation/reports/report_editor_screen.dart | 1730 lines | Split | P2 | M |
| dental | lib/features/dental/records/perio_chart_screen.dart | 1713 lines | Split | P2 | M |
| campaigns | lib/features/campaigns/presentation/post_campaign_modal.dart | 1678 lines | Split | P2 | M |
| homeopathy | lib/features/homeopathy/data/models/homeopathy_case_sheet.dart | 1676 lines | Split model | P2 | M |
| homeopathy | lib/features/homeopathy/presentation/widgets/homeopathy_extended_form_sections.dart | 1666 lines | Split | P2 | M |
| core | lib/core/services/firestore_sync_service.dart | 1659 lines | Split by collection | P2 | L |
| settings | lib/features/settings/presentation/desktop_settings_screen.dart | 1575 lines | Split sections | P2 | M |
| radiology | lib/features/radiology/viewer_plus/ceph/ceph_screen.dart | 1503 lines | Split | P3 | M |
| tests | test/, integration_test/ | No test refs for auth, profile, reports, tasks, therapy, todos, update | Add smoke tests for each | P2 | M |
| tests | test/ | scan (2 refs), campaigns (1), homeopathy (5), onboarding (2), support (3) | Add tests for money and send paths first | P2 | M |
| repo | tool/voice_server/.venv.old-empty/ | 723 tracked venv files (Scripts/*.exe, Lib/site-packages) | git rm --cached and ignore .venv* | P2 | S |
| repo | crudoc-clinic-handoff.zip, crudoc-patients-handoff.zip | Tracked zips 1.19 MB and 1.55 MB at root | Delete or move outside repo | P3 | S |
| repo | WhatsApp Audio 2026-10-12 at 02.39.38.mp4 | Tracked 1.1 MB video at root | Move out of repo | P3 | S |
| repo | build_log.txt (89 KB), app.html (157 KB), flutter_01.png (0 bytes) | Tracked logs and stray files at root | Remove from git | P3 | S |
| repo | functions/upload-test-001.txt | Tracked test debris in functions | Remove | P3 | S |
| repo | assets/fonts/Inter.zip | Tracked zip of font | Keep only extracted font | P3 | S |
| repo | doctor-data-isolation-and-encryption.patch, invoice-to-inventory.patch | Tracked patch files at root | Delete (work is merged) | P3 | S |
| repo | 0001-Improve-desktop-shell-UX.patch, desktop-shell-parity-and-fixes.patch, desktop_patient_details.patch, inventory-desktop-details.patch, inventory-vendor-tab-details.patch, firestore-debug.log, flutter_01..04.log, hs_err_pid12148.log, hs_err_pid19700.log | Untracked (gitignored) patches, logs and crash dumps at root | Delete locally | P3 | S |
| repo | migrate_admin_clinical_access.js, seed_emulator_clinic.js, seed_emulator_referrals.js, set_admin_claims.js, setup_super_admin_complete.js | Tracked one-off scripts at root | Move to tool/ or scripts/ | P3 | S |
| repo | crudoc-ai-voice-scribe-feature-plan.md, crudoc-dentist-specialization-phase-plan.md, crudoc-dentist-data-contract.md, STORAGE_RETENTION.md, WHATSAPP_INTEGRATION_GUIDE.md | Plan and guide docs at root, not in docs/ | Move to docs/ | P3 | S |
| docs | docs/security_plan.md + .pdf; docs/ai_receptionist_plan.md + .pdf; docs/whatsapp-meta-status.md + .docx; docs/whatsapp_shared_number.md and handoff/whatsapp_shared_number.md | Duplicate docs in two formats or two locations | Keep one source per doc | P3 | S |
| docs | docs/ai_receptionist_own_server_plan.md | Marked superseded | Archive | P3 | S |
| handoff | handoff/CRUDOC_DENTAL_HANDOFF.docx and .md | Same doc in two formats | Keep .md | P3 | S |
| handoff | handoff/antigravity_*.md (27 briefs) | Old briefs with GATE lines, many done per notes | Archive done briefs into handoff/archive/ | P3 | S |
| repo | tests/ and test/ | Two test roots (tests/ holds rules tests only) | Document or merge | P3 | S |
| repo | functions/, functions-admin/, voice-receptionist/, imaging-service/, cbct_viewer/, dental3d/ | Side projects, node_modules and __pycache__ present (ignored) | Keep; ensure no node_modules tracked (0 tracked, OK) | P3 | S |

## Document status (one line each: what it is; open items per the text)
handoff/CRUDOC_DENTAL_HANDOFF.md: dental specialties implementation handoff; open items listed as checklist.
handoff/CRUDOC_DENTAL_HANDOFF.docx: binary copy of the above; duplicate.
handoff/CRUDOC_DENTAL_HANDOFF_PART2.md: "what's left, in order" for dental; pending local sync columns and syncStatus work.
handoff/antigravity_3d_viewer_v2.md: brief for 3D viewer v2; GATE stops, tasks A3-A7, B1-B4 to run.
handoff/antigravity_apple_store.md: iOS and Mac App Store readiness brief; GATE lines; Mac build and console steps are the user's.
handoff/antigravity_cbct_motion.md: CBCT smooth transitions brief; no status markers.
handoff/antigravity_cbct_support.md: CBCT round 2 review fixes; says no GATE lines.
handoff/antigravity_chart_sessions.md: charting visits as sessions brief; pending sync status items.
handoff/antigravity_clinic_team.md: dental features and clinic team login; GATE 5 stop; reviews at GATE points.
handoff/antigravity_colleague_drop_send.md: drag file to colleague; Tasks 1-9 then GATE stop; not deployed.
handoff/antigravity_connect_restored_features.md: reconnect restored features; UI token rules; no gate noted.
handoff/antigravity_crudoc_id.md: find user by CruDoc ID; Tasks 1-9, GATE stop, deploy not done.
handoff/antigravity_dental3d.md: Dental 3D pass 2; GATE A and later gates waiting for owner phone and PC checks.
handoff/antigravity_dental3d_swap.md: swap to new 3D model; starts after Phase D GATE D; Part A and B gates.
handoff/antigravity_dicom_progressive.md: progressive radiology loading; status 'pending' design gates.
handoff/antigravity_documents_pdf.md: documents and PDF templates; Phase 1 passed GATE 1; later phases open.
handoff/antigravity_notifications_activity.md: notifications as activity; GATE never deploy; server changes await user deploy.
handoff/antigravity_perio_full_screen.md: perio full screen brief; no open marker.
handoff/antigravity_phone_fixes_oct26.md: phone fixes from 26 Oct notes; one pending mention.
handoff/antigravity_scan_followups.md: scan follow-ups; GATE stop, do not commit.
handoff/antigravity_storage_limit.md: storage limit and breakdown; pending_uploads rules; gates.
handoff/antigravity_superadmin_tasks.md: Super Admin Trial users tab; no open marker.
handoff/antigravity_tasks.md: Tasks brief for Gemini Flash; one pending mention.
handoff/antigravity_tasks_screen.md: rebuild phone Tasks screen; 14 open markers.
handoff/antigravity_tasks_screen_v2.md: Tasks screen v2; 7 open markers.
handoff/antigravity_up_next_visit.md: green Home visit card; one open marker.
handoff/antigravity_workflow_gaps.md: daily workflow gaps; two GATE lines; phases 5 and 6 excluded.
handoff/cbct_ai_design.md: AI assistance design for 3D viewer; design only, AI later.
handoff/cbct_pending_tasks.md: CBCT viewer status and what is left (2026-11-10); open list.
handoff/cbct_protocol.md: CBCT viewer protocol and contract; reference, no open items marked.
handoff/cbct_roadmap.md: CBCT roadmap, "not built yet".
handoff/claude_3d_viewer_handoff.md: handoff for next session on 3D viewer v2; GATE stops; points to cbct_pending_tasks.
handoff/clinic_tenant_usages.md: tenant usage analysis (T8) with GATE 3 review; follow-up T9.
handoff/superadmin_support_tickets_tasks.md: Super Admin bug reports tab tasks; no open marker.
handoff/whatsapp_shared_number.md: shared WhatsApp number reminders; 5 open markers.
docs/ai_receptionist_final_plan.md: final AI receptionist plan; P1 pilot and Gate 1 pending.
docs/ai_receptionist_own_server_plan.md: superseded own-server plan; pilot and gates listed, marked superseded.
docs/ai_receptionist_plan.md: original AI receptionist plan; pending_test states; 26 open markers.
docs/ai_receptionist_plan.pdf: PDF copy of the plan.
docs/apple_store_readiness_audit.md: Apple readiness audit; Google Maps key placeholder (AppDelegate) is Fail.
docs/cbct_3d_viewer_guide.md: CBCT viewer user guide; no open items.
docs/clinic_lan_file_sharing_plan.md: clinic file sharing plan; 28 open markers.
docs/crudoc-tutorial-feature-plan.md: first-run tutorial build spec; 5 open markers.
docs/find_a_person_fix_plan.md: find-a-person fix plan; 11 open markers.
docs/security_plan.md: security implementation plan; SEC-* tasks, some gated (SEC-20, SEC-40).
docs/security_plan.pdf: PDF copy of the security plan.
docs/ui-audit-2026-10-23.md: UI audit with checkboxes; mixed done and open.
docs/whatsapp-meta-status.md: WhatsApp Meta setup checklist; business verification unchecked (Pending/Not started).
docs/whatsapp_shared_number.md: shared-number WhatsApp plan; 5 open markers.
docs/CruDoc_Platform_Guide_Plain_English.docx, docs/whatsapp-changelog.docx, docs/whatsapp-meta-status.docx: Word copies; not checked for content.

## Side projects (top level)
functions: Firebase Cloud Functions (TypeScript) for the main app backend; tracked test debris upload-test-001.txt.
functions-admin: Cloud Functions for the Super Admin app.
voice-receptionist: Python AI voice receptionist server with Docker, tests and local voice test guide.
imaging-service: Python DICOM convert and backfill service with Dockerfile and spike folder.
cbct_viewer: Vite web CBCT 3D viewer; built output ships in app assets; 63 tracked files.
dental3d: Vite web 3D tooth viewer plus Blender scripts; 54 tracked files; tmp/ ignored.
installer: Inno Setup script CruDoc.iss for the Windows installer.
tool: developer scripts (CBCT build, voice fixtures, muscle pipeline, PaddleOCR test, sensor bridge, teeth, release secrets setup) and voice_server, which tracks a 723-file venv.
