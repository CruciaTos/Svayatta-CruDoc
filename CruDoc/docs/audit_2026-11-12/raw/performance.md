# Performance and optimisation inventory (static reading, 2026-11-12)

Method: Grep counts over lib/ and assets/. Counts are heuristic (grep-based); "verify" means open the file before fixing. Read-only, nothing changed.

1. Assets are the biggest app-size problem: assets/ is 284 MB, of which images 232 MB (810 files, 388 in bonebox_teeth at about 0.8-1 MB each), fonts 40 MB (Inter.zip 20 MB is shipped inside assets), muscle_viewer 6.3 MB, dental3d 2.6 MB, cbct_viewer 3.9 MB.
2. 55 Firestore `.snapshots()` listeners in lib (main.dart:270, clinic_session.dart 5, team_providers 4, doc_repository 3, device_session_service 3, referral_network 3). Many are long-lived; confirm each is cancelled on dispose or sign-out.
3. Heavy work is mostly isolated (Isolate.run/compute in about 25 places: rad_import, rad_pixels, viewer_export, file_previews, scan_worker, subtraction). The sync-IO gaps are the exceptions (see table).
4. Sync file IO on the UI path: about 60 `existsSync/readAsBytesSync/lengthSync/readAsStringSync` calls. The worst are radiology byte reads on the UI isolate (rad_view_pixels.dart:67, radiology_providers.dart:411, viewer_export.dart:161/170, cbct_pack.dart:335/464, thumbnail_strip.dart:21).
5. Images with no cacheWidth/cacheHeight: about 55 Image.file / Image.memory / Image.network calls. Thumbnail grids (files/file_thumb.dart:79/99, ortho_slider.dart 6 sites, physio_photos_card.dart:141, scan_flow.dart:211/266) decode full size.
6. Lists built with children from dynamic data (not builders): about 52 non-builder ListView/GridView, plus `children: [for ...]` in dashboard side_cards.dart:233, subscription_billing_page.dart:213/360, mobile_notifications.dart:212, rvg_capture_dialog.dart:434.
7. Ref.watch density (top-level watches in build): dental 133, radiology 93, appointments 93, mobile 87, patients 74, files 67. Whole-screen rebuilds are likely in the large screens listed below. Use select() or split providers.
8. Very large files (over 1000 lines): 35 files. Largest: voice_controller.dart 3120, viewer_screen.dart 3054 (54 setState calls), homeopathy_case_taking_sheet.dart 2906, tooth_art.dart 2827, tooth_detail_view.dart 2318, desktop_queue_screen.dart 2009.
9. Build methods: about 342 files contain `Widget build(`. Build methods over 300 lines were not counted exactly; the top offenders are the files above.
10. Timers: 23 Timer.periodic sites. Most are cancelled (verify): appt_drag.dart:172 runs a 16 ms timer; rvg_sensor_service.dart:272 polls at 300 ms; scribe_session_controller.dart:220 ticks at 250 ms; patient_voice_fill_bar.dart:61 at 200 ms; homeopathy voice modals at 100 ms amplitude timers; colleague_share_fan / colleague_strip auto-refresh.
11. Controllers with no dispose() in the same file (heuristic, verify each): appointments/appointment_actions.dart, dental/specialties/forms/forms_screen.dart, dental/specialties/ortho/ortho_photos.dart, files/presentation/nearby_sharing_settings.dart, homeopathy/presentation/homeopathy_patient_details_screen.dart, radiology/presentation/rad_import_flow.dart, therapy/presentation/physio_photos_dialog.dart.
12. Controller count: 560 TextEditingController creations (forms are the biggest source; each needs dispose), 34 FocusNode, 33 AnimationController, 8 ScrollController, 5 PageController.
13. Database N+1 and unbounded reads: 35 `.get()` calls in data/services/clinic with no visible limit; only 11 `.limit(` in lib. Sync loops at firestore_sync_service.dart:382 and files_repository.dart:1336 do one delete per row (batch them).
14. Startup (main.dart): before runApp it awaits Firebase.initializeApp and useAuthEmulator/useStorageEmulator (lines 74-96). Then runApp at line 136. Inside the auth flow, it awaits the encryption key, local DB ensure, InitialFirestoreMigrationService, FirestoreSyncService.start (lines 197-202) before the user reaches the first screen. The LAN and radiology catch-up work is already unawaited (206, 210), which is good.
15. Fonts: pubspec declares Geist (4 weights) and Inter as bundled fonts; Inter variable TTFs are 0.9 MB each and Inter.zip (20 MB) sits in the assets tree. Commented-out Schyler and Trajan Pro entries are dead config. Remove the zip from assets.
16. Unused-looking assets: assets/voice is empty (0 bytes). bonebox_teeth holds per-tooth turn PNGs (45-degree steps) that could be WebP (the dental folder already uses WebP) and that duplicate the library models; a conversion alone would cut roughly 80 percent.
17. Dental folder: 42,687 lines of Dart, the largest single area, and the most ref.watch calls (133).

## Per-feature table (counts from grep; "-" = none found)

| Feature | ref.watch | snapshots() | >1000-line files | Sync IO hits | Image w/o cache | Timers | Undisposed controller files |
|---|---|---|---|---|---|---|---|
| appointments | 93 | 2 | 0 | 0 | 0 | 1 | 1 |
| auth | - | - | 0 | 0 | 0 | 0 | 0 |
| campaigns | 3 | 3 | 1 | 0 | 0 | 0 | 0 |
| dashboard | 34 | 0 | 0 | 0 | 0 | 0 | 0 |
| dental (incl. dental3d) | 133 | 3 | 3 | 16 | 9 | 1 | 2 |
| files | 67 | 4 | 1 | 2 | 3 | 2 | 1 |
| homeopathy | 7 | 0 | 3 | 0 | 0 | 3 | 1 |
| inventory | 31 | 2 | 1 | 2 | 1 | 1 | 0 |
| messaging | 8 | 3 | 0 | 0 | 0 | 0 | 0 |
| mobile | 87 | 0 | 3 | 0 | 0 | 0 | 0 |
| onboarding | 3 | 1 | 0 | 0 | 1 | 0 | 0 |
| patients | 74 | 1 | 0 | 0 | 0 | 0 | 0 |
| profile | - | - | 0 | 0 | 0 | 0 | 0 |
| queue | 34 | 0 | 1 | 0 | 0 | 1 | 0 |
| radiology | 93 | 0 | 6 | 22 | 7 | 1 | 1 |
| reports | - | - | 0 | 0 | 0 | 0 | 0 |
| revenue | 23 | 4 | 1 | 2 | 0 | 0 | 0 |
| scan | - | 0 | 0 | 0 | 3 | 0 | 0 |
| scribe | 5 | 0 | 0 | 0 | 1 | 2 | 0 |
| settings | 33 | 0 | 1 | 0 | 2 | 0 | 0 |
| shell | 19 | 0 | 0 | 0 | 0 | 0 | 0 |
| subscription | - | 6 | 0 | 0 | 0 | 0 | 0 |
| support | 3 | 2 | 0 | 0 | 0 | 0 | 0 |
| tasks | 9 | 0 | 1 | 0 | 0 | 0 | 0 |
| team | 36 | 5 | 0 | 0 | 0 | 0 | 0 |
| tutorial | 6 | 0 | 0 | 0 | 0 | 0 | 0 |
| update | 5 | 0 | 0 | 0 | 0 | 1 | 0 |
| voice | 1 | 0 | 1 | 2 | 0 | 0 | 0 |
| therapy | 4 | 0 | 0 | 6 | 5 | 0 | 1 |
| todos | 11 | 2 | 0 | 0 | 0 | 0 | 0 |
| lib/core (shared) | - | 7 | 1 | 4 | 3 | 2 | 0 |

Note: "-" in the watch column means zero ref.watch calls found. Features with zero hits (auth, profile, reports, scan) were checked; scan has image-without-cache hits and no timers.

## Detailed findings

| feature | file:line | what | suggested change | priority | effort |
|---|---|---|---|---|---|
| assets | assets/fonts/Inter.zip | 20 MB zip bundled in the app | Delete from assets, keep only used TTF/WOFF2 | P1 | S |
| assets | assets/images/bonebox_teeth (388 PNG, 227 MB) | Per-tooth turn PNGs at about 0.85 MB each | Convert to WebP (dental folder already does), or lazy-download from a CDN on first use | P1 | M |
| assets | assets/fonts/Inter/*.ttf | Two Inter variable fonts 0.9 MB each plus the zip | Keep one variable font, remove the duplicate family | P2 | S |
| assets | assets/muscle_viewer/body.glb 5.4 MB, assets/cbct_viewer/a/main.js 3.5 MB | Large 3D and web bundles loaded for every install | Load lazily from a deferred asset or CDN, draco-compress the GLB | P2 | M |
| assets | assets/dental3d/assets/index-CAT_DbMX.js 0.98 MB, assets/dental3d/models/subject.glb 0.88 MB | Viewer bundle and model | Minify/tree-shake, lazy-load on first open | P2 | S |
| main | lib/main.dart:74-96 | Firebase init and emulator wiring before runApp | Keep, but check emulator branches are dead in release (kDebugMode guard) | P3 | S |
| main | lib/main.dart:197-202 | Encryption key, local DB ensure, migration and Firestore sync awaited before first usable screen | Show shell first and run sync behind a loading strip | P1 | M |
| main | lib/main.dart:270 | Snapshot listener inside startup flow | Confirm cancel on sign-out | P2 | S |
| core/clinic | lib/core/clinic/clinic_session.dart:308,341,444 | 3 snapshots in session class (session-long) | Cancel on sign-out; use .snapshots(includeMetadataChanges:false) | P2 | S |
| core/services | lib/core/services/firestore_sync_service.dart:403,458 | Sync listeners | Confirm cancel in stop(); add limit or where filters on collection listeners | P1 | S |
| core/services | lib/core/services/firestore_sync_service.dart:382 | db.delete one row per loop iteration | Wrap in a single transaction or batch | P2 | S |
| files | lib/features/files/data/files_repository.dart:1336 | await forget(table,id) per row in loop | Batch the deletes | P2 | S |
| files | lib/features/files/data/files_repository.dart:668 | snapshots on files, no limit visible | Add a where or limit, paginate in the UI | P1 | M |
| files | lib/features/files/presentation/widgets/colleague_strip.dart:79 | Timer.periodic refresh that calls the network | Pause when app is backgrounded or the strip is off-screen | P2 | S |
| files | lib/features/files/presentation/widgets/file_thumb.dart:79,99 | Image.memory and Image.file with no cacheWidth | Pass cacheWidth/cacheHeight equal to thumb size | P1 | S |
| files | lib/features/files/data/file_previews.dart:57-86 | Preview decode in isolates | Good; cache results in memory LRU keyed by path+mtime | P3 | S |
| files | lib/features/files/presentation/nearby_sharing_settings.dart | Controller without dispose (heuristic) | Verify and add dispose | P2 | S |
| dental | lib/features/dental/presentation/desktop/chart/tooth_art.dart (2827 lines) | Huge single file, painter likely repaints wholesale | Split; use RepaintBoundary; shouldRepaint checks | P1 | M |
| dental | lib/features/dental/presentation/desktop/tooth_detail_view.dart:1005,1024,1865 | Children built with spread lists of facts and tiles | Acceptable for small fixed sets; keep | P3 | S |
| dental | lib/features/dental/records/perio_chart_screen.dart:1692-1693 | Keypad rows rebuilt via digit() | Fine; make const where possible | P3 | S |
| dental | lib/features/dental/records/perio_staging.dart:447 | _recompute on every onChanged, 4 sites | Debounce or compute only on submit | P3 | S |
| dental | lib/features/dental/specialties/ortho/ortho_slider.dart:385,421,472,481,659,692 | 6 Image.file with no cache size | Add cacheWidth; decode once to ui.Image if reused | P1 | S |
| dental | lib/features/dental/specialties/ortho/ortho_photos.dart:340,595 | Full-size Image.file in dialog and card | Add cacheWidth or use a thumbnail file | P2 | S |
| dental | lib/features/dental/specialties/ortho/ortho_photos.dart | Controller without dispose (heuristic) | Verify and add dispose | P2 | S |
| dental | lib/features/dental/specialties/prostho/lab_case_export.dart:271 | readAsBytesSync on UI path for export | Use readAsBytes and await or Isolate | P2 | S |
| dental | lib/features/dental/specialties/prostho/scan_viewer_placeholder.dart:27-74 | existsSync/lengthSync inside build path | Move to async, cache the result | P2 | S |
| dental | lib/features/dental/referrals/referral_network.dart:292,305 | existsSync and lengthSync before share | Use async stat | P3 | S |
| dental | lib/features/dental/specialties/forms/forms_screen.dart | Controller without dispose (heuristic) | Verify and add dispose | P2 | S |
| radiology | lib/features/radiology/viewer/viewer_screen.dart (3054 lines, 54 setState) | Single screen with many setState calls rebuilds whole viewer | Move viewport state into a ChangeNotifier or Riverpod notifier and use ValueListenableBuilder | P1 | L |
| radiology | lib/features/radiology/viewer/viewport.dart (1295 lines) | Rebuilds on every pan/zoom | Keep paint in CustomPainter with RepaintBoundary | P1 | M |
| radiology | lib/features/radiology/imaging/rad_view_pixels.dart:67 | readAsBytesSync on UI isolate before decode | Use readAsBytes async | P1 | S |
| radiology | lib/features/radiology/data/radiology_providers.dart:411 | readAsBytesSync inside provider | Async read | P1 | S |
| radiology | lib/features/radiology/viewer/thumbnail_strip.dart:21 | readAsBytesSync for thumbnails | Async read; cache thumbs | P1 | S |
| radiology | lib/features/radiology/viewer/viewer_export.dart:161,170 | Full DICOM read sync before anonymise | Async read in isolate | P2 | S |
| radiology | lib/features/radiology/cbct/cbct_pack.dart:326,335,464 | writeAsBytesSync and readAsBytesSync of slices | Use async IO inside the isolate job | P2 | S |
| radiology | lib/features/radiology/cbct/cbct_poster_layer.dart:68-69, cbct_viewer_screen.dart:253-254 | jsonDecode of meta on UI thread | Parse in compute or cache | P3 | S |
| radiology | lib/features/radiology/imaging/rad_import.dart:154,160,201 | Zip decode of whole file on main path (inside Isolate later) | Confirm isolate; stream large zips | P2 | M |
| radiology | lib/features/radiology/services/rvg_sensor_service.dart:272 | Poll every 300 ms with async work | Use event stream from sensor or back off | P2 | M |
| radiology | lib/features/radiology/viewer/side_panel.dart:789 | Image.file full size | Add cacheWidth | P2 | S |
| radiology | lib/features/radiology/presentation/reports/study_context_panel.dart:329 | Image.file with no cache | Add cacheWidth | P3 | S |
| radiology | lib/features/radiology/viewer_plus/ceph/ceph_screen.dart (1503 lines) | Large screen | Split; check setState counts | P2 | M |
| radiology | lib/features/radiology/presentation/rad_import_flow.dart | Controller without dispose (heuristic) | Verify and add dispose | P2 | S |
| radiology | lib/features/radiology/presentation/rvg_capture_dialog.dart:161,499 | writeAsBytesSync on save, Image.memory full size | Async write, cacheWidth | P2 | S |
| appointments | lib/features/appointments/presentation/widgets/shell/appt_drag.dart:172 | 16 ms Timer.periodic during drag | Use Ticker or GestureDrag updates, not Timer | P2 | S |
| appointments | lib/features/appointments/presentation/appointment_actions.dart | Controller without dispose (heuristic) | Verify and add dispose | P2 | S |
| appointments | lib/features/appointments/data/repo/visits_repo.dart:103,107 | Two snapshots, unbounded by date | Filter to visible date range | P1 | S |
| patients | 74 ref.watch sites in patients feature | Whole patient screens rebuild on any change | Use select() on the patient record, split tabs into widgets | P1 | M |
| patients | lib/features/patients/data/repo/patient_repository.dart:290 | Listener over all patients | Add limit/pagination and search filter in query | P1 | M |
| patients | lib/features/patients/presentation/patient_form.dart:517 | options.map inside build | Pre-compute outside build | P3 | S |
| queue | lib/features/queue/presentation/desktop_queue_screen.dart (2009 lines) | Large screen plus 30 s Timer | Split widgets; use one ValueNotifier for clock | P2 | M |
| queue | lib/features/queue/presentation/desktop_queue_screen.dart:121 | Timer.periodic 30 s | Fine; keep, confirm cancel | P3 | S |
| dashboard | lib/features/dashboard/presentation/widgets/side_cards.dart:233 | Bars built from data list with spread | Fine for 7-30 days | P3 | S |
| dashboard | 34 ref.watch sites | Dashboard reads many providers at top | Use select() per card | P2 | M |
| mobile | 87 ref.watch sites | Mobile screens watch whole providers at top | Use select() | P1 | M |
| mobile | lib/features/mobile/mobile_kit.dart (1832), mobile_schedule.dart (1747), mobile_tasks.dart (1499) | Large files | Split by widget | P2 | M |
| mobile | lib/features/mobile/mobile_notifications.dart:212 | Rows spread in a Column | Use ListView.builder if it can exceed a screen | P2 | S |
| homeopathy | lib/features/homeopathy/presentation/homeopathy_case_taking_sheet.dart (2906) | Largest homeopathy file | Split into steps, lazy build per step | P1 | M |
| homeopathy | lib/features/homeopathy/presentation/widgets/homeopathy_voice_dictation_sheet.dart:108,119 and homeopathy_voice_scribe_modal.dart:104,115 | 1 s and 100 ms timers, duplicated | Share one amplitude service; stop on dispose | P2 | S |
| homeopathy | lib/features/homeopathy/presentation/homeopathy_patient_details_screen.dart | Controller without dispose (heuristic) | Verify and add dispose | P2 | S |
| homeopathy | lib/features/homeopathy/data/repo/homeopathy_repository.dart:187 | Stream yields getCaseSheetForPatient per update | Ok; add cache | P3 | S |
| therapy | lib/features/therapy/presentation/physio_photos_dialog.dart:251,610 and widgets/physio_photos_card.dart:141 | Image.file full size and file exists checks in build | Use cacheWidth and cached thumb | P1 | S |
| therapy | lib/features/therapy/presentation/physio_comparison_dialog.dart:407,446,501,512 | 4 full-size Image.file in comparison | Add cacheWidth; use InteractiveViewer with downscaled image | P2 | S |
| therapy | lib/features/therapy/presentation/physio_photos_dialog.dart | Controller without dispose (heuristic) | Verify and add dispose | P2 | S |
| therapy | lib/features/therapy/domain/physio_photos_models.dart:111,120 | existsSync in model code | Async | P3 | S |
| scan | lib/features/scan/presentation/scan_flow.dart:211,266,336 | Image.memory full JPEG list | Use thumb list and gaplessPlayback; cacheWidth | P1 | S |
| scan | lib/features/scan/presentation/document_camera_page.dart:818 | Live preview Image.memory each frame | Use Texture or RepaintBoundary | P2 | M |
| scan | lib/features/scan/data/scan_capture.dart:84 | readAsBytes then compute shrink | Good; keep | P3 | S |
| scribe | lib/features/scribe/presentation/scribe_session_controller.dart:220,381 | 250 ms ticker and processing ticker | Use one ticker; stop when session idle | P2 | S |
| scribe | lib/features/scribe/presentation/widgets/session_scan_card.dart:85 | Image.memory thumb with no cache size | Add cacheWidth | P3 | S |
| settings | lib/features/settings/presentation/documents/documents_kit.dart:335,574 and my_details_tab.dart:332 | Image.memory full size for logo and preview | Add cacheWidth | P3 | S |
| settings | lib/features/settings/presentation/desktop_settings_screen.dart (1575 lines) | Large screen | Split per section | P2 | M |
| inventory | lib/features/inventory/presentation/desktop_inventory_list_screen.dart (1733) | List screen, check if ListView.builder and filters run in build | Move filter/sort to provider | P1 | M |
| inventory | lib/features/inventory/presentation/desktop_add_edit_medicine_dialog.dart:1166-1167 | Image.network and Image.file with no cache | Add cacheWidth | P3 | S |
| inventory | lib/features/inventory/data/repo/inventory_repository.dart:81,370 | Two snapshots, no limit | Paginate | P2 | S |
| revenue | lib/features/revenue/presentation/desktop_create_invoice_dialog.dart (1756, 27 setState) | Heavy dialog with setState | Move to Notifier | P2 | M |
| revenue | lib/features/revenue/repo/revenue_repo.dart:171,195; invoice_repo.dart:103 | Snapshots, likely unbounded by date | Add date range | P1 | S |
| revenue | lib/features/revenue/data/services/paddle_ocr_service.dart:117,122 | existsSync before python OCR | Check once, cache | P3 | S |
| team | lib/features/team/data/team_providers.dart:18,34,57,81 | 4 snapshots per team screen | Limit and cache members list | P2 | S |
| team | lib/features/team/presentation/team_analytics_view.dart:96 | TeamStats.compute in build | Compute in provider | P2 | S |
| team | lib/features/team/presentation/activity_log_view.dart:60 | Activity log snapshot unbounded | Add limit(50) and load more | P1 | S |
| messaging | lib/features/messaging/data/repo/whatsapp_repository.dart:118,141,157 | 3 snapshots, message history | Limit to last N messages, paginate | P1 | M |
| campaigns | lib/features/campaigns/presentation/post_campaign_modal.dart (1678), mobile_post_campaign_sheet.dart (1376) | Large files, duplicate implementations | Merge into one responsive widget | P2 | M |
| campaigns | lib/features/campaigns/data/repo/campaign_repository.dart:101,115 | Snapshots | Limit | P2 | S |
| subscription | lib/features/subscription/data/doctor_subscription_service.dart:103,219,239 | 3 snapshots on user doc | Keep one stream, cancel on logout | P2 | S |
| support | lib/features/support/data/resolved_tickets.dart:62; support_ticket_watcher.dart:146 | Snapshots for ticket watching | Limit to open tickets | P3 | S |
| todos | lib/features/todos/data/todo_repository.dart:86,87 | Two unbounded snapshots (createdBy, assignedTo) merged | Add limit; merge streams once | P2 | S |
| tasks | lib/features/tasks (1499 mobile_tasks.dart) | Large file | Split | P2 | M |
| voice | lib/features/voice/voice_controller.dart (3120 lines) | Largest Dart file in app | Split into intent, audio, UI controllers | P1 | L |
| voice | lib/features/voice/services/speech_engine.dart:322,372,377,1003 | existsSync on path resolution, isolate spawn | Cache resolved paths | P3 | S |
| shell | lib/features/shell (19 ref.watch in shell) | Shell rebuilds on any provider | Use select() for nav state | P2 | S |
| onboarding | lib/features/onboarding/data/loyalty_card.dart:68; loyalty_card_view.dart:408 | Snapshot and Image.network without cache | Add cacheWidth and cache | P3 | S |
| update | lib/features/update/presentation/update_launcher.dart:46 | Timer.periodic recheck | Confirm cancel on dispose | P3 | S |
| lib/core | lib/core/services/device_session_service.dart:317,372,433,469 | 3 snapshots plus 5-min heartbeat timer | Confirm cancel on sign-out | P2 | S |
| lib/core | lib/core/services/local_storage_manager.dart:233 | Hourly timer | Fine | P3 | S |
| lib/core | lib/core/services/medical_storage_service.dart:717 | compute jpeg | Good | P3 | S |
| lib/core | lib/core/pdf/data/doc_repository.dart:357,382,403 | 3 snapshots, PDF docs | Limit and paginate | P2 | S |
| lib/core | lib/core/utils/doctor_profile_helper.dart:27 | await for on user doc inside helper | Check cancel on return | P2 | S |
| lib/core | lib/core/utils/doctor_feature_guard.dart:67 | docSub listen | Verify cancel | P2 | S |
| lib/core | lib/core/pdf/presentation/editor/editor_canvas.dart:375,391 | Image.memory background per frame | Cache decoded image | P2 | S |
| lib/core | lib/core/pdf/data/branding_image_store.dart:70 | compute | Good | P3 | S |
| settings | lib/features/settings/data/call_forwarding_platform.dart:64 | snapshots | Limit | P3 | S |
| files | lib/features/files/lan/device_registry_service.dart:141 | snapshot | Confirm cancel | P3 | S |
| files | lib/features/files/data/file_offers_repository.dart:126,159 | 2 snapshots | Limit | P2 | S |
| files | lib/features/files/data/files_cloud_sync.dart:73 | snapshot in sync loop | Batch | P2 | S |

## The 15 changes most likely to make the app feel faster

1. Remove Inter.zip (20 MB) and the duplicate font files from assets. Startup and install size drop with no code risk. (P1, S)
2. Convert assets/images/bonebox_teeth from PNG to WebP or lazy-load it; 227 MB shrinks by roughly 80 percent. (P1, M)
3. Give every thumbnail and grid image cacheWidth/cacheHeight: file_thumb.dart, ortho_slider.dart (6 sites), physio_photos_card.dart, scan_flow.dart, side_panel.dart. Decode cost falls sharply. (P1, S)
4. Replace readAsBytesSync on the UI path in the radiology viewer (rad_view_pixels.dart:67, radiology_providers.dart:411, thumbnail_strip.dart:21, viewer_export.dart:161/170) with async reads or isolates. (P1, S)
5. Split viewer_screen.dart (3054 lines, 54 setState) state into a notifier and rebuild only the viewport and panels that change. (P1, L)
6. Paginate or limit the unbounded snapshot listeners: visits_repo.dart:103/107, patient_repository.dart:290, whatsapp_repository.dart, activity_log_view.dart:60, revenue_repo.dart, files_repository.dart:668. (P1, M)
7. Use select() on the big providers in patients, mobile, appointments and dental (about 390 ref.watch calls in these four features) so one field change stops rebuilding whole screens. (P1, M)
8. Make the main.dart startup show the shell before the encryption, migration and sync awaits finish (main.dart:197-202). (P1, M)
9. Move the 2 files at 1000+ lines with the heaviest setState use (viewer_screen.dart, desktop_create_invoice_dialog.dart) to notifiers and split. (P2, M)
10. Replace high-frequency Timer.periodic loops (appt_drag 16 ms, scribe ticker 250 ms, voice 100 ms amplitude timers) with a Ticker or one shared service, and pause them when hidden. (P2, S)
11. Batch the per-row database deletes and awaited loops (firestore_sync_service.dart:382, files_repository.dart:1336) into single transactions. (P2, S)
12. Add dispose for controllers in the 7 files flagged (appointment_actions, forms_screen, ortho_photos, nearby_sharing_settings, homeopathy_patient_details_screen, rad_import_flow, physio_photos_dialog) and audit the 560 TextEditingController sites in forms. (P2, S)
13. Cancel session-long snapshot listeners on sign-out (clinic_session.dart, device_session_service.dart, doctor_subscription_service.dart, main.dart:270). Prevents memory growth and duplicate updates. (P2, S)
14. Cache decoded images and PDF/DICOM previews in an LRU keyed by path and modification time (file_previews.dart, thumbnail_strip.dart, physio/ortho thumbs). Reopening screens becomes instant. (P2, M)
15. Move team_analytics_view.dart:96 (TeamStats.compute in build) and similar computations into providers so they run once per data change, not per frame. (P2, S)
