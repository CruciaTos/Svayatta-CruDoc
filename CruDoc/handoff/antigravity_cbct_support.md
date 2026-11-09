# Antigravity tasks: CBCT 3D viewer, round 2 (fix the review findings)

You are doing small, mechanical jobs around the CBCT 3D viewer. This whole file is
your brief. Claude (the lead) reviewed your round 1 work and found a few wrong
statements in the documents. Fix them, and do one more test file.

## ▶ DO NOW

**Do R1, R2, R3 and R4, in order, in one run.** Do NOT redo round 1 (see "Done").
There are no GATE lines: do not stop between tasks. Anywhere a task says "STOP",
that means: skip that part, write one line in your report saying what and why, and
carry on.

### Done in round 1 (reviewed by Claude, do not touch again)
Unit tests `src/state.test.js` and `src/core.test.js` (19 of 19 node tests pass with
`npm test`), `tools/make_phantom.mjs`, `tests/smoke.mjs` (all pass), `tests/shot.mjs`,
`tests/serve.mjs`, `tests/compare.html`, `tests/responsive.mjs` (30 of 30 pass),
three Dart test files, the analyzer fix in `radiology_providers.dart`. Your STOP on
the cloud-download hook (no study-level "download finished" point) and on the Settings
label (no screen lists the caches) was correct.

---

## Rules

> Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`, a Flutter app. The
> CBCT viewer is a web page (`cbct_viewer/`) shown in a WebView by
> `lib/features/radiology/cbct/`.
> - Change ONLY the files a task names. Never touch `cbct_viewer/src/` (except
>   adding the new files a task names), `vite.config.js`, `index.html`,
>   `package*.json`, `assets/`, or anything in `lib/` (read only).
> - Do not run `vite build`, `npm run build`, `flutter` or `dart` commands except the
>   single Dart check in R4.
> - Never `git commit` / `git push`. No real patient scans anywhere. No invented
>   features: write ONLY what the code does. When unsure, read the code; when the code
>   does not say, leave the sentence out.
> - If the code you find does not match the task, skip that part, say what you
>   found, and carry on.

**How to work (no pauses):** do all four tasks, then run the Checks once at the end.
Do not stop to ask questions. Reply with every file you changed, each Check's output,
and anything you skipped (with the reason).

---

## R1. Correct `docs/cbct_3d_viewer_guide.md`

Claude found these errors. Fix each one (edit the sentence, do not add new content):
1. Section 5 lists the 3D looks as "Bone, Soft, Skin + bone, X-ray". The real chips
   (`VIEW3D_CHIPS` in `cbct_viewer/src/chrome.js`) are **Bone, Teeth, Skin + bone,
   X-ray, MIP**. Remove "Soft", add "Teeth" and "MIP" with one honest line each (from
   `cbct_viewer/src/view3d.js`: Teeth shows only the densest structures; X-ray is an
   average-intensity picture, MIP the brightest voxel along each ray).
2. Section 8 says the data lives in an "encrypted local app directory". Nothing in the
   viewer encrypts anything. Say only: the 3D data is a cache stored next to the study
   on this device (`<study folder>/.cbct/`), it is rebuilt automatically if deleted, and
   the viewer page itself never uses the network.
3. Section 1 says to tap a "3D button on any CBCT study card". The worklist's row menu
   item is **"Open in 3D"** (the "⋯" menu, `worklist_screen.dart`), and the 2D viewer's
   toolbar has a **"3D"** button (`viewer_toolbar.dart`). Write exactly that.
4. Section 7 says the snapshot is "linked to the patient's radiology record for reports,
   referral letters". The code (`lib/features/radiology/cbct/cbct_snapshot.dart`) only
   saves the picture as a key image on the study. Say exactly that.
5. Section 6: delete the sentence about "Frame of Reference" anchoring and the part that
   says the ellipse shows "width, height" unless you can point to the code that does it
   (`cbct_viewer/src/engine.js`, Cornerstone's EllipticalROI shows area, mean and
   standard deviation by default: write only what you can verify in the Cornerstone
   tool or leave the measurements line generic: "Ellipse: draws an oval and shows its
   statistics").

## R2. Correct `handoff/cbct_protocol.md`

Fix these (keep everything else):
1. Section 4, message `close`: the screen does NOT call `Navigator.maybePop()`. In
   `cbct_viewer_screen.dart` the handler sets `_saved = true` and calls `_leave()`, which
   asks the page to run `CbctViewer.prepareClose()` (skipped when already saved), then pops
   the route. Also describe the system back / Esc path: a `PopScope` calls `_leave()`.
2. Section 4: `boot` and `timing` are ignored by Flutter (no case in the switch). Remove the
   sentence that says they are logged.
3. Section 1, query parameter `device`: it only chooses which volume the page loads
   (`mid.i16` on a tablet when the pack has one, else `full.i16`; `session.js`). The side
   panel starts closed when the window is narrower than 1100 px unless a saved state says
   otherwise (`session.js`, `applySavedUi`). Fix the sentence.
4. Section 1, parameter `first`: the first-open "solidify" animation needs `first=1`, no
   saved cameras, and reduced motion off (`session.js`, `open`). Add the two missing
   conditions.
5. Section 1, the Note that says Flutter does not pass `badge` is wrong:
   `cbct_viewer_screen.dart` passes `badge` ("Anonymized" when the DICOM `IdentityRemoved`
   is YES, else "On this device"). Fix the Note.
6. Section 5, `state.json`: add that `cameras` and `centre` can be `null` (when saved before
   a volume was loaded), and that `posters` only lists views that were big enough to
   capture (a view hidden by the single-view layout is skipped; the 3D view is stored under
   the key `3d`, the others under `axial`, `coronal`, `sagittal`).
7. Section 2: add one line: a PUT or GET with an unknown or revoked token, or for a pack
   folder that no longer exists, returns 404.

## R3. Complete `cbct_viewer/README.md`

1. In the module map add one line each for `src/shims/events.js` and `src/shims/url.js`
   (tiny stand-ins for the Node modules `events` and `url`, which vtk.js needs at load) and
   `src/styles/tokens.css`, `src/styles/viewer.css` (design tokens and all page styling).
2. Add one line under Commands: `?debug` in the page URL exposes `window.__cbct` (the
   engine state and the annotation store) for the test scripts.
3. `npm test` now runs `node --test "src/*.test.js"`; make the README comment match.

## R4. One more Dart test: the poster layer (new file only)

Create `test/features/radiology/cbct/cbct_poster_layer_test.dart`. Read
`lib/features/radiology/cbct/cbct_poster_layer.dart` and
`test/features/radiology/cbct/cbct_pack_test.dart` first (copy its `synthetic()` helper,
do not import it). Use `testWidgets`:
1. Build a pack with `ensureCbctPack` inside `tester.runAsync(...)` (the packer uses an
   isolate and real files, so it needs real async), using the synthetic CBCT.
2. Pump `CbctPosterLayer(packDir: ..., meta: ..., visible: true, background: null)` inside a
   `MaterialApp` and a `SizedBox(width: 800, height: 600)`; expect four `Image` widgets (one
   per view) and that the layer is visible (opacity 1).
3. Pump it again with `visible: false`, call `await tester.pump(const Duration(milliseconds: 300))`
   and expect the layer to be faded out (opacity 0, or ignoring pointers: check what the
   widget really does and assert that).
If the widget needs something the test cannot provide (a provider, a platform channel),
STOP this task, write what is missing, and carry on.

**Check (the only Flutter command you may run, once, at the very end):**
`flutter test test/features/radiology/cbct/cbct_poster_layer_test.dart`
then `dart format test/features/radiology/cbct/cbct_poster_layer_test.dart`. If it
crashes on sqlite3.dll, wait one minute and retry once. For R1 to R3 the Check is:
every file name and shortcut you mention exists, and `grep -n "TODO" docs/cbct_3d_viewer_guide.md handoff/cbct_protocol.md cbct_viewer/README.md` prints nothing.
