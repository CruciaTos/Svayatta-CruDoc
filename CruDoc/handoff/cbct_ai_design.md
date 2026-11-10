# Design: assistance in the 3D dental viewer (automation first, AI later)

Written 2026-11-10 by Claude. The user's meaning of "AI assistance": anything that
automates or helps a task (automatic marking, boxing, measuring), not necessarily AI.
So plain image-measurement automation comes first; trained models only where nothing
simpler works. Viewer code: `cbct_viewer/src/`. Related: `handoff/claude_3d_viewer_handoff.md`.

## 0. Automation without AI

Built 2026-11-10 (`assist.js` pure functions + tests, UI in `planning.js`, `findings.js`):
- **Nerve canal auto-follow**: click the start and end (more clicks to steer); the
  cheapest path through soft-tissue-dark voxels walled in by bone joins them. Undo
  removes the whole followed piece.
- **Bone measurements at each implant**: crest (where the axis enters bone), narrowest
  ridge width near the crest and at mid-implant, height to the canal roof (lower) or to
  the sinus / nose floor (upper), how far the top sits above or below the crest.
- **Seat at crest** and **Suggest size** (standard diameters / lengths; 1.5 mm bone each
  side, 2 mm above the canal, 1 mm under a sinus; warnings for narrow or short bone).
- **Automatic boxing** of metal / very dense objects (implants, crowns, fillings, root
  fillings) when the scan opens: dashed boxes "M1.." in the slice views and 3D, listed
  under "Found automatically"; click one to go there.

Next without AI (most need the arch from Antigravity's Part B):
1. Panoramic view + cross-sections along the arch (the dentist's main view).
2. **Tooth boxing and numbering**: along the arch, teeth are bright blocks separated by
   darker gaps; split the panoramic density profile at the gaps, box each tooth in 3D,
   number them from the midline (FDI). Editable; a model (section 2) replaces it later
   if it is not reliable enough on real scans.
3. Auto-orientation: level the occlusal plane and centre the arch (from the arch fit).
4. Sinus floor and airway: mark the maxillary sinus floor; airway minimum cross-section
   (orthodontics / sleep) from the air region behind the tongue.
5. Plan summary text (implants, sizes, clearances, found objects) for the record and the
   report, without AI (Antigravity B4 writes the pure function).

## What already exists (no AI, built 2026-11-10)

- Surface 3D (`surface.js`, `mesher.js`): any voxel mask can become a mesh in ~0.2 s in a
  worker. Per-tooth meshes later reuse this.
- Implant plan (`plan.js`, `planning.js`): the dentist traces the nerve canal by clicking,
  places implants at the crosshair, sees the distance to the canal live (green >= 2 mm,
  amber 1-2, red < 1). Saved in `state.json` as `plan`.
- Panoramic view: arch curve + panoramic + cross-section functions are Antigravity's Part B
  (`arch.js`, `panoramic.js`); Claude adds the view to the UI afterwards.

## 1. Decisions for the user

| Question | Options | Recommended |
|---|---|---|
| Where does scan AI run? | A) inside the viewer on the device (ONNX Runtime Web, WebGPU, WASM fallback); B) native in Flutter (onnxruntime package); C) server (Cloud Run GPU, India region) | **A**: the scan never leaves the device (DPDP), works offline, one code path for Windows, Android, iPad. C later only as an opt-in for weak tablets. |
| Which model? | Use a published dental CBCT model; or train our own on clinic scans | **Published first**, after a licence check (many are non-commercial only). Own training needs patient consent and labelled scans: later. |
| What may the AI claim? | "Diagnosis" vs "draft the dentist confirms" | **Draft only.** Every suggestion is accepted or rejected by the dentist; wording never says "diagnosis". A diagnostic claim may make it a medical device needing CDSCO registration: get advice before marketing. |
| Text AI (report writing)? | Gemini through the app's existing Firebase AI path, text only | Yes, with no name, ID or images in the prompt; images only with the patient's consent. |

## 2. Features in order (each one useful on its own)

1. **Tooth segmentation and FDI numbering** (model). Output: one label per voxel
   (32 teeth + canal + jaws). Enables:
   - tap "36" -> 3D flies to the tooth, it is highlighted in all views;
   - show / hide single teeth (one mesh per tooth via `mesher.js` on the label mask);
   - findings and plans attached to a tooth number, linked to CruDoc's tooth chart.
2. **Automatic nerve canal** (same model, canal label): fills `state.plan.nerves` as
   points the dentist can edit. The manual trace stays as the fallback.
3. **Findings draft** (rules on the labels first, explainable): missing teeth (number
   gaps), impacted / tilted teeth (axis angle vs neighbours), roots close to the canal or
   sinus (distance), implant clearance. A lesion model (periapical dark areas) later.
4. **Report**: accepted findings + implant plan -> Gemini writes the report and a
   plain-language patient summary; the dentist edits and signs.
5. **Intraoral scan merge** (later, no model): import the clinic's STL, line it up with the
   CBCT (pick 3 points, then refine). This is the honest way to show gums and crowns:
   gums cannot be separated reliably from a CBCT alone.

## 3. How it fits the viewer (option A)

- Model files (`.onnx`, tens of MB) ship as app assets or download once; served by the
  app's local server like the scan (CSP already allows `'wasm-unsafe-eval'` and blob
  workers; `connect-src 'self'` means the model must be served locally).
- Runs in a worker: resample the slice volume to the model's spacing, sliding-window
  patches, write a `Uint8Array` label volume. Progress shown; the viewer stays usable.
- Result cached next to the pack as `labels.bin` (+ `labels.json`: model name, version,
  date), so it runs once per scan. `meta.json` / protocol gain an optional `labels` entry.
- Every suggestion stored with model version and the dentist's accept / reject (audit).

## 4. Milestones

| # | Work | Who |
|---|---|---|
| M0 | Decisions in section 1 | User |
| M1 | Speed spike: ONNX Runtime Web + WebGPU in WebView2 (Windows) and Android WebView with a dummy 3D U-Net of realistic size; time and memory on this PC and a mid tablet | Claude |
| M2 | Pick the model and confirm its licence | User + Claude |
| M3 | Labels pipeline in the viewer, per-tooth meshes, tooth fly-to, auto canal | Claude (hard), Antigravity (panel UI, tests, docs) |
| M4 | Findings draft rules + accept / reject UI | Claude rules, Antigravity UI |
| M5 | Report via Gemini, link to the tooth chart | Antigravity (from a brief) |

## 5. Risks

- Weak devices: a 3D model on a tablet may take minutes. M1 decides; fallback is C.
- Licence: a good public model may be non-commercial. Check before building on it.
- Wrong numbering on unusual mouths (missing / extra teeth, implants, metal): always
  editable; never auto-filled into the chart without the dentist confirming.
