# Outcome measures

One JSON file per patient-reported outcome measure. The app loads these at
startup; `odi.json` is the worked example to copy the shape from.

## Why these are data and not code

These are **licensed third-party instruments**. Three consequences:

1. **The wording is the instrument.** A validated scale with reworded
   options is no longer that scale, and its score is no longer comparable to
   anything published about it. The text in these files must come from your
   clinic's own authorised copy, copied exactly — not retyped from memory,
   not paraphrased, not shortened to fit a screen.
2. **Licences differ per instrument, and some cost money.** Keeping each one
   as a file means adding or removing an instrument is an edit here, not a
   code change and a release.
3. **A missing instrument stays visibly missing.** A file that is absent or
   malformed is reported in the app rather than silently substituted, so a
   clinic that believes it has the NDI is told when it does not.

## Which ones ship, and which do not

| Instrument | Status |
|---|---|
| ODI (Oswestry Disability Index) | `odi.json` — present |
| NDI (Neck Disability Index) | **not supplied** — add `ndi.json` yourself |
| TUG, 6MWT | built into the app; no item text, nothing to license |
| DASH / QuickDASH | not supplied. Free for clinical use via the Institute for Work & Health, but with registration terms — settle those before adding it |
| WOMAC | **do not add without a licence.** Commercially licensed; embedding its items without one is real legal exposure |

## Adding an instrument

Copy `odi.json`, replace the contents, and add the filename to
`kScaleAssets` in
`lib/features/therapy/data/outcome_scale_registry.dart`.

```json
{
  "id": "ndi",
  "name": "Neck Disability Index",
  "short": "NDI",
  "region": "Neck",
  "kind": "questionnaire",
  "unit": "%",
  "higherIsBetter": false,
  "source": "who published it, and which version",
  "instruction": "how it is administered",
  "usageNote": "licence terms, or anything the physio should know",
  "mdc": 10,
  "minAnswered": 8,
  "bands": [{ "from": 0, "to": 9, "label": "No disability" }],
  "items": [
    {
      "id": "pain",
      "label": "the section heading, exactly as printed",
      "options": ["the 0 answer", "the 1 answer", "…"]
    }
  ]
}
```

### The fields that change the score

- **`options`** — order is the score. Index 0 scores 0, index 1 scores 1,
  and so on. Never re-order them to read better.
- **Every item must have the same number of options.** The loader refuses a
  file where they differ, because a percentage across unequal items is
  meaningless.
- **`minAnswered`** — how many items must be answered before the app shows a
  figure at all. The instrument itself usually scores over whatever was
  answered; this is an additional CruDoc guard so a figure built from three
  sections is not put beside one built from ten. ODI uses 8 of 10.
- **`mdc`** — minimal detectable change, in the reported unit. **Leave it
  out if the published figure depends on the population.** The app only
  claims a change is real when it exceeds this; with no value it reports the
  change and makes no claim, which is the honest default.
- **`higherIsBetter`** — `false` for a disability index, `true` for
  something like a walk distance. This is what decides whether a falling
  number is reported as improvement.
- **`bands`** — contiguous and inclusive, covering the whole range. Omit
  them entirely rather than inventing cut-offs; TUG and 6MWT ship with none
  for exactly this reason.

## Regenerating `odi.json`

```
dart run tool/export_odi_scale.dart --force
```

That script copies the strings out of `odi_scale.dart` mechanically, so the
asset matches the source character for character.
