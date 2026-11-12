# Motion, transitions and screen states: inventory (2026-11-12)

Scope: CruDoc/lib (app) plus crudoc_shared/lib (design system). Read only. Counts come from grep/bash over the tree; "hits" are matching lines, not verified sites. Line numbers are given where the grep showed them.

1. Raw `Duration(milliseconds: N)` literals in app: 140 across features. 30 distinct values (25, 60, 80, 90, 100, 120, 150, 160, 180, 200, 220, 240, 250, 260, 280, 300, 320, 340, 350, 400, 420, 500, 550, 600, 700, 800, 900, 1000, 1200, 1600). Most used: 400 (9), 90 (8), 600 (8), 200 (8), 800 (7), 700 (7). The shared token file defines only 200, 250, 240, 220 (CruMotion), and CruMotion is referenced by 119 files, so the token exists but is only partly adopted.
2. Animated widgets in app: about 205 hits in feature folders (AnimatedSwitcher, AnimatedContainer, AnimatedSize, AnimatedCrossFade, AnimatedOpacity, TweenAnimationBuilder, AnimationController, Hero, AnimatedList). Heaviest: files 37, radiology 23, appointments 20, patients 17, dental 14, homeopathy 12.
3. Routing: 11 `Navigator.push` calls across 10 files; about 40 MaterialPageRoute/PageRouteBuilder/MorphBox/go/GoRoute hits across 26 files; app_router.dart has 7 GoRoute-style hits. Custom motion is rare: MorphBox/morph_tag (2), schedule_morph, search_lift, swipe_pages. Most navigation uses default platform transitions. Not verified: the exact transition set in app_router.dart.
4. Loading: 64 CircularProgressIndicator/LinearProgressIndicator hits (campaigns 9, radiology 9, dental 8, files 5). Skeleton/shimmer hits about 181 (appointments 34, inventory 29, files 25, patients 23, revenue 23, dashboard 21). Several features show spinners only, and some show nothing (see table).
5. Silent failures: 107 single-line empty catch blocks (`catch (e) {}`), of which files 18, radiology 13, settings 7, messaging 6, scribe 6, dental 4, voice 4. Many more catches only call debugPrint, which the user never sees.
6. Raw exception text shown to users: at least 15 sites print `$e` into SnackBars or say()/toast text (see findings). Full count needs a tighter grep, since a broad `$e` grep gave 173 files of noise.
7. Feedback: 17 HapticFeedback call sites in app, 0 in crudoc_shared. SnackBar/toast/say calls: about 174 hits across 70 files. Feedback style is not consistent: the app uses SnackBar, showIsland, mobileSay, _say, _toast, and say() helpers.
8. Dialogs and sheets: about 51 hits (showModalBottomSheet, showDialog, CruSheet/showCru*) across 43 files. Many dialogs are built ad hoc (desktop_*_dialog.dart in each feature) rather than through one shared helper; CruSheet/showCru* exist in shared widgets but are not used everywhere.
9. Empty states: 38 files reference an empty-state widget. Lists in files, revenue, queue and tasks were not checked one by one, so blank-list cases are only partly confirmed. No `isEmpty ? SizedBox` pattern was found.

## Per-feature table

Columns: dur = raw Duration literals; anim = animated widgets; spin = progress spinners; skel = skeleton/shimmer hits; silent = empty catch lines; haptic = HapticFeedback; push = Navigator/route hits; sheet = dialog/sheet hits; files = .dart file count.

| feature | dur | anim | spin | skel | silent | haptic | push | sheet | files | three best places to add a clean transition or state |
|---|---|---|---|---|---|---|---|---|---|---|
| appointments | 7 | 20 | 2 | 34 | 2 | 1 | 0 | 3 | 56 | day/week view slide between dates; appointment block insert/move animation; skeleton-to-list crossfade |
| auth | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | sign-in step transitions (phone to OTP); error shake or fade on wrong code |
| campaigns | 4 | 1 | 9 | 0 | 1 | 0 | 0 | 1 | 12 | replace 9 spinners with skeleton rows; sheet-to-result morph; analytics number count-up |
| dashboard | 0 | 4 | 0 | 21 | 0 | 0 | 1 | 0 | 19 | stat counters tween; card expand to details; schedule card insert animation |
| dental | 7 | 14 | 8 | 8 | 4 | 0 | 5 | 2 | 78 | tooth chart selection highlight tween; procedure list insert/remove; screen push to charting |
| files | 16 | 37 | 5 | 25 | 18 | 8 | 1 | 3 | 51 | 18 silent catches need user-visible error; transfer progress tween; file card to viewer hero |
| homeopathy | 8 | 12 | 4 | 0 | 1 | 0 | 2 | 3 | 17 | case sheet section expand (AnimatedSize); save confirmation feedback; form step slide |
| inventory | 2 | 13 | 3 | 29 | 0 | 0 | 4 | 1 | 37 | stock bar tween on change; row remove animation; item panel slide-in |
| messaging | 0 | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 15 | 6 silent catches; no loading/empty state found; send-status transition |
| mobile | 11 | 18 | 2 | 0 | 3 | 3 | 0 | 3 | 19 | island/tab content crossfade; nav bar selection tween; swipe between tabs |
| onboarding | 6 | 6 | 0 | 0 | 0 | 0 | 0 | 1 | 4 | step page transition; progress indicator tween; loyalty card reveal |
| patients | 11 | 17 | 1 | 23 | 2 | 0 | 1 | 4 | 41 | preview pane slide (CruMotion.pane); table row remove; visit list expand |
| profile | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | no motion code; 1 file only; add save feedback and section transitions |
| queue | 0 | 7 | 1 | 4 | 1 | 1 | 0 | 0 | 6 | queue card reorder animation; check-in confirmation haptic; counter tween |
| radiology | 30 | 23 | 9 | 6 | 13 | 0 | 5 | 1 | 74 | 13 silent catches; viewer tool switch crossfade; study list skeleton |
| reports | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | no motion; 2 files (report editor lives under radiology); add save state |
| revenue | 0 | 5 | 1 | 23 | 3 | 0 | 2 | 0 | 29 | chart bar grow animation; transaction insert; pending card expand |
| scan | 2 | 6 | 1 | 0 | 2 | 1 | 1 | 1 | 16 | capture flash/feedback; page-to-page transition; scan result card reveal |
| scribe | 5 | 7 | 2 | 0 | 6 | 0 | 1 | 1 | 17 | recording pulse; 6 silent catches; note section expand |
| settings | 0 | 8 | 3 | 0 | 7 | 0 | 2 | 0 | 15 | 7 silent catches; section switch crossfade; toggle feedback |
| shell | 1 | 4 | 2 | 0 | 1 | 0 | 0 | 0 | 8 | sidebar collapse tween; page content crossfade on route; header fade |
| subscription | 0 | 0 | 2 | 0 | 1 | 0 | 4 | 2 | 9 | plan card selection tween; checkout sheet transition; success state |
| support | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 4 | 1 silent catch (watcher); ticket send state |
| tasks | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 1 | list skeleton only; task complete strike-through tween |
| team | 0 | 0 | 3 | 0 | 2 | 0 | 0 | 2 | 17 | invite sheet transition; member list insert; 2 silent catches |
| therapy | 1 | 0 | 4 | 0 | 2 | 0 | 0 | 0 | 7 | muscle chart highlight tween; photo compare slide; 2 silent catches |
| todos | 0 | 1 | 0 | 2 | 1 | 0 | 0 | 0 | 9 | todo check animation; reminder list insert; 1 silent catch |
| tutorial | 2 | 4 | 0 | 0 | 1 | 0 | 0 | 0 | 8 | overlay spotlight tween; card step transition; 1 silent catch |
| update | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 6 | progress sheet tween; error state with retry (raw error text in installer) |
| voice | 22 | 8 | 0 | 3 | 4 | 0 | 0 | 0 | 13 | bubble enter/exit; waveform tween; 22 raw duration literals to tokens |
| core (shared) | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | CruMotion used in 119 files across app+shared; PDF editor touch UI has 6 animated hits |
| shared (crudoc_shared) | 8 | n/a | n/a | n/a | n/a | 0 | n/a | n/a | n/a | CruMotion tokens (fast 200, standard 250, pane 240, strip 220, curve easeOutCubic) |

## Detailed findings

| feature | file:line | what | suggested change | priority | effort |
|---|---|---|---|---|---|
| dashboard | lib/features/dashboard/presentation/dashboard_actions.dart:299 | SnackBar shows raw `'$e'` to user | Map to friendly message plus retry; log the raw error | P1 | S |
| dashboard | lib/features/dashboard/presentation/dashboard_actions.dart:265 | say('Could not start the consultation: $e') | Strip exception text; keep the friendly prefix | P1 | S |
| mobile | lib/features/mobile/mobile_schedule.dart:1067 and :1262 | mobileSay(context, '$e') | Friendly message; keep raw error in debugPrint | P1 | S |
| mobile | lib/features/mobile/mobile_island.dart:151 | _say('$e') | Friendly message | P1 | S |
| mobile | lib/features/mobile/mobile_home.dart:152 and :445 | Raw $e appended to "Could not update/check in" | Friendly text only | P1 | S |
| files | lib/features/files/presentation/transfers_sheet.dart:124 | SnackBar '$failed: $e' | Friendly failure text with retry action | P1 | S |
| files | lib/features/files/presentation/send_sheet.dart:153 | 'Could not send: $e' | Friendly text plus retry | P1 | S |
| files | lib/features/files/presentation/files_actions.dart:53, :139, :307 | Errors only debugPrint, user sees nothing | Show a SnackBar on failure | P1 | S |
| files | lib/features/files/lan/lan_client.dart:291 | throw HttpException with raw $e to UI | Map to user text | P2 | S |
| files | lib/features/files/lan/offline_offer_queue.dart:48, :66 | Silent queue errors | Surface a "will retry" state | P2 | S |
| voice | lib/features/voice/presentation/voice_overlay.dart:100 | _error = 'Voice is off: $e' shown in overlay | Friendly text plus open-settings action | P1 | S |
| homeopathy | lib/features/homeopathy/presentation/homeopathy_case_taking_sheet.dart:842 | 'Could not save the case sheet: $e' | Friendly text; keep retry | P1 | S |
| homeopathy | lib/features/homeopathy/presentation/homeopathy_patient_details_screen.dart:291 | AsyncValue error branch builds CruCard (content not checked) | Verify card text is not e.toString(); add retry button | P2 | S |
| core/pdf | lib/core/pdf/presentation/editor/template_editor_screen.dart:516 and :576 | 'Save failed: $e' and 'Could not render preview: $e' | Friendly text plus retry | P1 | S |
| core/pdf | lib/core/pdf/presentation/editor/editor_panels.dart:326 and :1104 | 'Could not add the picture/it: $e' | Friendly text | P2 | S |
| campaigns | lib/features/campaigns/presentation/campaign_analytics_dialog.dart:92 | 'Retry failed: $e' | Friendly text | P2 | S |
| update | lib/core/update/platform/update_installer.dart:57 and :87 | Exception text 'Download interrupted: $e' surfaces to UI | Friendly text plus retry | P2 | S |
| radiology | lib/features/radiology (13 empty catch sites, grep: `catch (e) {}`) | Silent failure on viewer/import paths | Log and show a message on user-triggered actions | P1 | M |
| files | lib/features/files (18 empty catch sites) | Silent failure on file actions and LAN | Show SnackBar for user actions; keep silent only for background sync | P1 | M |
| messaging | lib/features/messaging (6 empty catch sites, 0 motion, 0 state widgets) | Silent failures and no loading/empty/error UI | Add loading and error states to the inbox | P1 | M |
| settings | lib/features/settings (7 empty catch sites) | Save toggles fail silently | Show error SnackBar and revert the toggle | P2 | S |
| scribe | lib/features/scribe (6 empty catch sites) | Recording/note save silently fails | Visible error with retry | P1 | S |
| dental | lib/features/dental (4 empty catch sites) | Charting save silently fails | Visible error | P2 | S |
| voice | lib/features/voice/voice_controller.dart:2678 and speech_engine.dart:757, :885 | Many debugPrint-only failures | Keep logging; add user state where mic or model fails | P2 | M |
| all | 140 raw Duration literals, 30 distinct values | No single motion token set in use | Map to CruMotion (fast 200, standard 250, pane 240, strip 220) and add slow 400 and quick 120; lint against new literals | P2 | M |
| all | 17 HapticFeedback calls in app; 0 in crudoc_shared | Haptics only on a few screens | Add haptic on check-in, save success, long press, destructive confirm via one helper | P2 | S |
| all | SnackBar/showIsland/say/mobileSay/_say/_toast helpers (about 174 hits, 70 files) | Five or more feedback helpers with different looks | One CruFeedback helper (success, error, undo) | P2 | M |
| all | about 51 dialog/sheet hits across 43 files | Ad hoc dialogs per feature (desktop_*_dialog.dart) | Route all sheets/dialogs through one CruSheet helper with a shared enter curve | P2 | M |
| all | about 205 animated widget hits, 0 shared route transition | Default route transitions everywhere; custom only in morph/appointment files | Define one shared route transition (fade-slide 250 ms) for go_router and Navigator | P2 | M |
| all | about 64 CircularProgressIndicator hits (campaigns 9, radiology 9, dental 8) | Spinners where skeletons would fit list screens | Use skeletons for list and table loads; keep spinners for button actions | P2 | M |
| queue | lib/features/queue/presentation/desktop_queue_screen.dart | Queue list changes (check-in, reorder) have no insert/remove animation (7 animated hits total for feature) | AnimatedList or AnimatedSwitcher for row changes; haptic on check-in | P2 | S |
| appointments | lib/features/appointments/presentation/widgets (34 skeleton hits, 20 animated hits) | Skeleton-to-content switch is abrupt; view changes (day/week/month) are not animated across dates | Crossfade skeleton to content; slide between dates | P2 | M |
| patients | lib/features/patients/presentation/widgets/list/patient_preview_pane.dart | Preview pane slides (uses CruMotion.pane); table selection change has no tween | Keep slide; add row highlight tween and count-up on summary strip | P3 | S |
| settings | lib/features/settings/presentation/desktop_settings_screen.dart | Section switch with no crossfade | AnimatedSwitcher on section body, 200 ms | P3 | S |
| radiology | lib/features/radiology/viewer/viewer_screen.dart and cbct/cbct_viewer_screen.dart | Tool switch and study load have no transition; 30 raw durations in feature | Shared viewer transition tokens; fade on study load | P3 | M |
| all | About 5 "empty" paths: lists with no empty widget (not fully counted) | Blank area when a list is empty in several screens (messaging, profile, reports) | Add a shared CruEmptyState with icon, text, action; apply per screen | P2 | M |
| shared | crudoc_shared/lib/theme/cru_tokens.dart:240-255 | CruMotion exists, has reduced-motion guard (MediaQuery) | Make it the only source; lint raw Duration in app | P2 | S |

## Notes for the owner

- Not checked in this pass: app_router.dart transition types, every AsyncValue `error:` branch, and whether each empty list has a blank state. Those need a second pass with file reads.
- Sensitive-looking paths were not opened: none needed.
- Dental and dental3d were read as they stood; no edits made.
