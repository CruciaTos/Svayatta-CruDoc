# Antigravity brief: grow the mini-repertory data (content only)

Model: Gemini Flash. Small, explicit steps. Do the steps in order and stop at each GATE.
Do not commit. Do not touch any file not named below.

## Background
CruDoc (Flutter) has a homeopathy mini-repertory. It ships 120 rubrics in three data files
under `lib/features/homeopathy/data/repertory/`:
`repertory_part_mind.dart`, `repertory_part_generals.dart`, `repertory_part_particulars.dart`.
The engine, registry and screens are finished. Your job is ONLY to add more rubrics as new
data files. Read the header comment at the top of `repertory_part_mind.dart` first: it
documents the exact format.

## The format (one rubric)
```dart
Rubric(
  id: 'head-pain-forehead-sun',          // unique across ALL files, never reused
  chapter: 'Head',                       // see chapter list below, keep spelling exact
  path: 'Head > Pain > forehead > sun, from exposure to',
  remedies: {'Glon.': 3, 'Nat-m.': 3, 'Bell.': 2, 'Lach.': 1},
),
```
- Grades: 1 = plain, 2 = italic, 3 = bold.
- Remedy keys MUST be abbreviations that already exist in
  `lib/features/homeopathy/data/homeopathy_remedies.dart` (case and full stops ignored).
  Open that file and use only abbreviations found there. Do not invent abbreviations.
- Ids: prefix with the chapter short code (`head-`, `eye-`, `ear-`, `nose-`, `face-`, `mouth-`,
  `throat-`, `stom-`, `abd-`, `stool-`, `urine-`, `male-`, `female-`, `resp-`, `chest-`, `back-`,
  `ext-`, `sleep-`, `fever-`, `skin-`, `gen-`, `mind-`). Before adding, search the existing
  files for the id and for the same `path` so nothing is duplicated.

## Rules for the content (very important)
1. Only add rubrics and remedy entries you are SURE are classical and widely agreed.
   A short correct rubric is better than a long doubtful one. If unsure, leave the remedy out.
2. Write in your own words from your own knowledge. Do NOT copy text from a published repertory.
3. Prefer 3 to 12 remedies per rubric. Grade 3 only for the best-known, strongest remedies.
4. Common, clinically useful rubrics first: things physicians hit every day.
5. Never add rubrics that tell the physician what to prescribe for a disease name. Rubrics are
   symptom descriptions (location, sensation, modality, cause, concomitant).

## Task 1: new files, about 450 more rubrics in total
Create these files in `lib/features/homeopathy/data/repertory/`, each a
`const List<Rubric>` with the same header comment (copy it) and at most 100 rubrics:
- `repertory_part_head_face.dart`  (chapters Head, Face, Eye, Ear, Nose)
- `repertory_part_mouth_throat_stomach.dart`  (Mouth, Throat, Stomach, Abdomen)
- `repertory_part_stool_urine_genitalia.dart`  (Stool, Urine, Male genitalia, Female genitalia)
- `repertory_part_respiration_chest_back.dart`  (Respiration, Cough, Chest, Back)
- `repertory_part_extremities_skin_fever.dart`  (Extremities, Skin, Sleep, Fever, Chill)
- `repertory_part_mind_more.dart`  (extra Mind rubrics not already in `repertory_part_mind.dart`)

Name each list `kRepertory<Something>` (e.g. `kRepertoryHeadFace`). Register each list by adding
ONE line to `allRepertoryParts` in `repertory_registry.dart`. Make no other change to that file.

GATE 1 (after each new file): run
`flutter analyze lib/features/homeopathy/data/repertory` from the `CruDoc` folder.
It must say "No issues found". Fix and re-run before the next file.

GATE 2 (after the last file): run a debug check that nothing is dropped. In the debug console of
the app, or with a small Dart script run with asserts on (`dart --enable-asserts`), load
`repertory_registry.dart` and confirm: no unknown remedy abbreviations, no repeated ids, no bad
grades. If anything is dropped, fix the data file (never edit the engine).

## Task 2 (only if time remains): chapter chips
Check the repertory screen still shows every new chapter as a filter chip with a sensible order
(Mind, Generalities, then body chapters head to foot). If chips come out in an odd order, report
it; do NOT change screen code.

## Report back (short)
- Files created, rubric count per file.
- Output of both gates.
- Any remedy you wanted to add but could not (abbreviation missing from the remedy list).
- Anything you were unsure about, listed by rubric id, so a homeopath can check it first.

## Must still happen after this (not your job)
A qualified homeopath must review ALL rubrics (the 120 existing and every new one) before any
release. The data was written by language models.
