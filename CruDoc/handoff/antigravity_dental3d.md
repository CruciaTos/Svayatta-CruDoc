# Dental 3D "Show patient" viewer — pass 2 tasks (for Antigravity)

Pass 1 is built and tested: 32 modelled teeth with pulp/canals, live gums and bone, Natural / X-ray / Status modes, explode, open mouth, camera fly-to, inspector panel, phone bottom sheet, Flutter host screen. Pass 2 adds what the dentist actually shows the patient: the patient's own tooth shape, each treatment step by step, and the visit-by-visit result.

Do the tasks in order. One task = one change. Stop at each **GATE** and wait for Soham.

## Rules for every task
- Work only in `CruDoc/dental3d/src/` and `CruDoc/dental3d/tests/` unless a task names another file. Never edit `blender/`, `tools/`, `scene_manifest.json`, `public/models/`.
- Plain JavaScript, no new npm packages, no CDN links, no web fonts (the app runs offline).
- Run from `CruDoc/dental3d`: `npm install` once, `npm run dev` to look at it, `npm test` (headless Chrome, must stay green), `npm run build` at the end of each phase (writes `CruDoc/assets/dental3d/`).
- Every state change goes through `src/engine/actions.js` → `store.set(...)`. UI never touches meshes directly.
- Read these before starting: `src/state/schema.js` (the snapshot JSON, already written), `src/data/treatments.js` (catalogue with step texts, already written), `src/state/store.js`, `src/engine/actions.js`, `src/engine/toothMaterial.js`, `src/engine/gums.js`, `src/engine/explode.js`.
- Tooth local axes: origin at the neck, `+Y` towards the crown tip (crown is `y` 0…`dims.crownHeight`, root below 0), `+Z` facial (lip/cheek), `+X` mesial when `mesialSign` is +1 and distal when −1. Each tooth object has `userData.part` (manifest entry) and `userData.rest = { p, q }` (rest position/quaternion). After changing `rest`, call `explode.apply()` and `gums.rebuildGums(arch)`.
- UI style: reuse the CSS variables and classes in `src/ui/styles.css`. Touch targets ≥ 40 px. Plain words for labels (patient may be watching).
- No commits. Report after each task: files changed, what you checked, anything not working.

---

## Phase A — the patient's own teeth

**A1. Hide bone under healthy gums.** Today a beige bone band shows above and below the pink gum. Find where `layers.bone` sets the bone meshes' `visible` (search `bone` in `src/engine/modes.js` and `src/main.js`). New rule: bone is visible only when `layers.bone` is on AND (`layers.gums` is off OR `mode === 'xray'`). Done when the Natural front view shows no beige band and X-ray still shows bone.

**A2. Store accepts the full snapshot.** In `store.js` replace `defaultTooth()` with `defaultToothState()` from `schema.js`, and add top-level state `profile`, `treatments`, `visits`, `currentVisit` from `defaultSnapshot()`. In `actions.applyStateSnapshot` also accept: every `ToothState` field (clamp: shift −6…6, rotate −45…45, scale 0.7…1.3, wear 0…4, 0…1 fields to 0…1), `profile`, `treatments` (array, keep only items whose `type` is in `TREATMENTS`), `visits`, `currentVisit` (0…visits.length). If the snapshot has `saved` (object): first apply `saved`, then apply the snapshot itself on top, but keep from `saved` the `visit` of any treatment with the same `id`, and keep `saved` treatments whose `origin` is not `"chart"`. Add `actions.getPersist()` returning `{schema:1, profile, teeth, treatments, visits, currentVisit}` and include it as `payload.persist` in every `STATE_UPDATED` bridge event (see `src/bridge.js`). Done when `npm test` passes and a new test case in `tests/verify.mjs` round-trips a snapshot.

**A3. Apply tooth shape.** New file `src/engine/shape.js` exporting `applyShape(registry, store, explode, gums)`; call it from `main.js` whenever `teeth` or `profile` changes (store subscribers get the set of changed FDI numbers as the third argument). For each tooth, from `part = obj.userData.part` and its effective state `t` (see C1; until then use the stored state):
- base position = `part.position` with `x * profile.archWidth` and `z * profile.archDepth`;
- add `−part.frame.tangentDistal * t.shift.md`, `part.frame.facial * t.shift.bl`, `part.frame.coronal * t.shift.v`;
- quaternion = `part.quaternion` × rotZ(−mesialSign · tip°) × rotX(torque°) × rotY(spin°) (local rotations, in that order);
- `obj.scale.set(t.scale.w, t.scale.h, t.scale.w)`;
- `obj.visible = t.present` (also respect the arch layer toggle);
- write the result into `obj.userData.rest.p / .q`, then `explode.apply()` and rebuild the gums of each changed arch once.
Done when setting `shift.bl = 3` on tooth 11 through `App3DBridge.applyStateSnapshot` moves it forward and the gum follows.

**A4. Shade, stain, wear, chip.** In `toothMaterial.js`: set `uShade` from `t.shade ?? profile.baseShade` (a key of `SHADES` or a `#rrggbb`), `uStain`, `uCalculus`, `uWear`, `uChip` from the tooth state (add a small `updateToothMaterial(mat, t, profile)` function and call it from A3's loop). Shader additions in the vertex stage, after `#include <begin_vertex>`: wear — `transformed.y = min(transformed.y, uCrownH - uWear);` chip — a scoop at the mesio-incisal corner: centre `vec3(uMesialSign * uMd * 0.5, uCrownH, 0.0)`, radius `uChip * 0.5 * uMd`; if a vertex is inside the sphere, push it out to the sphere surface along (vertex − centre). Bump `customProgramCacheKey` to `'tooth-enamel-v2'`. Done when a screenshot shows a worn lower incisor and a chipped 21.

**A5. "Match patient" panel.** New `src/ui/matchPanel.js`, shown inside the inspector under the selected-tooth card when a tooth is selected, collapsed by default behind a button "Match this tooth". Controls (each writes through `actions.applyStateSnapshot({teeth:{[fdi]:{...}}})`): Present / Missing switch; sliders Move sideways (shift.md −4…4), Move in/out (shift.bl −4…4), Move up/down (shift.v −4…4), Tilt sideways (tip −30…30), Tilt in/out (torque −30…30), Turn (spin −45…45), Width (scale.w 0.8…1.2), Length (scale.h 0.8…1.2); shade chips (the `SHADES` keys, coloured); sliders Stain, Worn (wear 0…3), Chipped, Gum recession (0…6), Gum swelling, Tartar, Bone loss (0…6); a "Reset tooth" button. Done when it works on phone width (bottom sheet) without horizontal scroll.

**A6. Example patients.** New `src/data/presets.js` exporting 5 full snapshots, and a "Example patient" menu in the toolbar that applies one:
1. `healthy` — empty snapshot.
2. `gap_stained_front` — 11: shift.md −1.2, scale.w 0.9, shade A35; 21: shift.md −1.2, scale.w 0.9, shade A4, stain 0.6; visits ["Visit 1 – caps", "Visit 2 – whitening"]; treatments: crown on 11 and on 21 (material emax, visit 1, `options:{shade:'A1', shape:{w:1.1, md:1.2}}`), whitening both arches visit 2 (`options:{targetShade:'A1'}`).
3. `missing_front` — 11 present false; 21: torque 10, shift.md −1.5; 12: shift.md −1.0; 41 present false; 31: tip 8; visits ["Visit 1 – implants placed", "Visit 2 – healing check", "Visit 3 – new teeth"]; treatments: implant 11 (zirconia, visit 3), implant 41 (visit 3), crown 21 (visit 3, `options:{shape:{md:1.5, torque:-10}}`).
4. `crowding` — profile.archWidth 0.95; 41: spin 18, shift.bl 1.2; 31: spin −15, shift.bl −1.0; 42: shift.bl −1.5, spin 10; 32: spin −12, shift.bl 0.8; 12: shift.bl −1.8; 22: shift.bl −1.5; 13: shift.v −1.5, shift.bl 1.5; visits ["Visit 1 – braces on", "Visit 2 – half way", "Visit 3 – braces off"]; treatments: braces both arches (visit 1, `options:{endVisit:3}`), whitening visit 3.
5. `worn_gum_disease` — lower incisors 42,41,31,32: wear 1.5, recession 2.5, calculus 0.7, inflammation 0.6, boneLoss 2; 16 and 26: recession 2; 36: conditions [{type:'caries', surfaces:['O','D']}]; 46 present false; visits ["Visit 1 – cleaning + filling", "Visit 2 – implant", "Visit 3 – new tooth"]; treatments: scaling both arches visit 1, filling 36 O,D composite visit 1, implant 46 visit 3.

**GATE A — stop. Soham checks the presets on phone and PC.**

---

## Phase B — fillings and decay on the tooth surface

**B1. Surface regions in the tooth shader.** In `toothMaterial.js` fragment code add a function returning 5 weights (M, O, D, B, L) for the crown only (`vLocalPos.y > 0`): with `xn = vLocalPos.x * uMesialSign / (uMd * 0.5)`, `zn = vLocalPos.z / (uBl * 0.5)`, `yn = vLocalPos.y / uCrownH` — O = smoothstep(0.72, 0.82, yn) · (1 − smoothstep(0.55, 0.8, length(vec2(xn, zn)))); M = smoothstep(0.45, 0.6, xn) · smoothstep(0.25, 0.4, yn); D = same with −xn; B = smoothstep(0.45, 0.6, zn) · smoothstep(0.2, 0.35, yn) · (1 − smoothstep(0.7, 0.85, yn)); L = same with −zn. Then: caries — `base = mix(base, vec3(0.16, 0.09, 0.05), w_i * uSurfCaries[i])` with a little noise at the edge; filling — `base = mix(base, uSurfFill[i].rgb, w_i * uSurfFill[i].a)`, and where a metallic filling (amalgam) is used raise `metalnessFactor` to 0.85 in the same region (add a `uSurfMetal[5]` float array). Done when a screenshot shows decay on 36 O+D and a silver filling on 46 O.

**B2. Drive them from state.** Conditions `caries` set `uSurfCaries` for their surfaces. A `filling` treatment that is in effect (C1) clears caries on its surfaces and sets `uSurfFill` (colour from `MATERIALS[material].color`, or the tooth shade lightened 4 % for composite).

---

## Phase C — treatments and the visit timeline

**C1. Effective state.** New `src/treatments/effective.js`: `effectiveTooth(state, fdi)` returns the tooth state as it looks after `state.currentVisit`: start from the stored tooth; for each treatment with `status === 'completed'` or `visit <= currentVisit` that includes this tooth (or its arch): filling → B2; scaling → calculus 0, inflammation 0; whitening → shade = options.targetShade (not on crowned/implant teeth); crown/veneer → shade = options.shade ?? 'A1', stain 0, chip 0, wear 0, plus `options.shape` (w multiplies scale.w; md/torque add to shift/rotate); rct → remove `abscess` condition, flag `rctDone`; extraction → present false; implant → present true, `implant: true`; bridge → teeth[1…n−2] are pontics (`pontic: true`, present true), first and last get crowns; braces → shift and rotate of every tooth in those arches scaled by `1 − progress`, progress = clamp((currentVisit − visit + 1) / (endVisit − visit + 1), 0, 1), and `brackets: true` while visit ≤ currentVisit < endVisit. A3/A4/B2/gums must read `effectiveTooth` instead of the raw state.

**C2. Hardware and caps (static result).** New `src/treatments/visuals.js`, rebuilt whenever effective state changes; all meshes are children of the tooth object so they follow it:
- crown: clone the tooth mesh, scale 1.03, material from `MATERIALS[material]`, with a clipping plane keeping only local y > 0.6 (needs `renderer.localClippingEnabled = true`);
- veneer: same clone, scale 1.02, clipped to local z > 0.15·bl and y > 0.8;
- implant: hide the tooth's own mesh below y = 0 (clip the tooth material to y > 0.3), add clones of `tpl_implant_fixture` (origin at y = −1.5) and `tpl_implant_abutment` (base at y = −1.5), material `MATERIALS.titanium`, plus the crown as above;
- pontic: tooth mesh clipped to y > 0.5 (no root), raised so it does not touch the gum line;
- braces: a clone of `tpl_bracket` on each tooth at local (0, 0.45·crownHeight, 0.5·bl·0.92) and one tube mesh per arch through the bracket slots (CatmullRomCurve3 → TubeGeometry radius 0.25, steel);
- rct done: recolour that tooth's `pulp_<fdi>` to `MATERIALS.guttaPercha.color` (visible in X-ray).
The `templates` node stays hidden; clone its children with `clone()` and share geometry.

**C3. Timeline bar.** New `src/ui/timeline.js`: a slim row above the bottom toolbar: `Today` · one chip per visit · `Final`; tapping sets `currentVisit`. A "Before / After" button toggles between 0 and visits.length while held. Hidden when there are no visits. Shape changes between visits must animate (lerp rest position/quaternion and shade over 500 ms).

**C4. Treatment panel.** Fill `#treatment-panel` (in `src/ui/inspector.js`) for the selected tooth: list its conditions (label + `patientText` from `CONDITIONS`), its treatments (label, material, visit, status chip), and an "Add treatment" menu limited to `part.interactiveActions` that asks for surfaces (fillings), material and visit, then appends a treatment with `origin: 'viewer'` and a unique `id`. A remove button on viewer-made treatments only.

**GATE C — stop. Soham checks presets 2–5 across the timeline.**

---

## Phase D — step-by-step explainer

**D1. Player.** New `src/treatments/player.js`: `play(treatmentId)` flies the camera to the tooth, switches to the mode the step needs, and shows a card bottom-centre with the step title and text from `TREATMENTS[...].steps`, with Back / Next / Close and step dots. Each step runs a short animation keyed by its `visual` name. A "Show me how" button on each treatment row in C4 starts it.

**D2. Animations, one small function per `visual`** (500–1200 ms each, all reversible when the player closes): `show_caries`, `show_grooves`, `show_defect`, `show_gap`, `show_calculus`, `show_shade`, `show_alignment` — camera move + pulse the relevant region/tooth; `drill_cavity` — caries weight to 0 and the region darkens as a hollow; `fill_material`, `apply_sealant`, `build_up` — fill weight 0 → 1; `polish` — brief roughness dip; `xray_show_pulp` — X-ray mode, pulp pulses red; `access_opening` — small dark circle on O; `clean_canals` — pulp colour red → pale; `fill_canals` — pulp colour → gutta-percha from the tip upwards; `close_access` — O filling appears; `prep_crown` — `uPrep` 0 → 1 (add to the vertex stage: for y > 0.6 scale x and z by `1 − 0.18·uPrep` and lower the top by `0.12·uCrownH·uPrep`); `scan_flash` — quick white rim flash; `seat_crown`, `seat_veneer`, `seat_bridge` — the cap starts 9 mm above (along +Y local) and slides on; `loosen_tooth` — small wobble; `lift_tooth` — tooth moves 14 mm out along +Y and fades; `heal_socket` — set present false so the gum closes; `place_fixture` — fixture screws in from 10 mm above with rotation; `osseointegrate` — bone visible, soft glow around the fixture; `place_abutment` — abutment drops in; `remove_calculus`, `gum_heal` — calculus and inflammation 1 → 0; `whiten` — shade lerp; `place_braces` — brackets pop on one by one, then the wire; `align_teeth` — braces progress 0 → 1; `remove_braces` — brackets fade.

**GATE D — stop.**

---

## Phase E — app side (Flutter), only after Soham says go
**E1.** In `lib/features/dental/explain3d/dental3d_screen.dart`, handle a new packet type `TREATMENT_ADDED` (payload: fdi, type, surfaces, material) by opening the app's existing "add to treatment plan" flow pre-filled — ask Soham which flow before coding.
**E2.** Sync the saved snapshot (`dental3d.saved.<patientId>` in shared_preferences today) to the patient's cloud record so it follows the dentist across devices — needs Soham's decision on where it lives.
**E3.** Once the new viewer is approved, remove the old in-card 3D (`tooth_chart_3d.dart`, `chart/jaw_model.dart`) and the "3D" half of the Chart | 3D toggle.
