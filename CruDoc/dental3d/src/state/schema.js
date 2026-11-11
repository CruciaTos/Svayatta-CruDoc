// Patient snapshot schema (version 1) — the JSON the host app sends with
// App3DBridge.applyStateSnapshot() and receives back in STATE_UPDATED.
// Everything is optional; missing fields fall back to these defaults.
// A future photo / CBCT matcher only has to produce this same JSON.

/**
 * @typedef {Object} ToothState
 * @property {boolean} present            false = missing in the mouth today
 * @property {'normal'|'flagged'|'planned'|'inProgress'|'completed'} status
 * @property {string|null} statusColor    optional hex override for the status colour
 * @property {string|null} shade          key of SHADES or '#rrggbb'; null = profile.baseShade
 * @property {number} stain               0..1 yellow-brown surface staining
 * @property {{md:number, bl:number, v:number}} shift   mm: md + = towards the midline (mesial), bl + = towards the lip/cheek, v + = further out of the gum
 * @property {{tip:number, torque:number, spin:number}} rotate   degrees: tip + = crown leans mesially, torque + = crown leans to the lip/cheek, spin = turn about the long axis
 * @property {{w:number, h:number}} scale  crown width / tooth length multipliers (1 = average)
 * @property {number} wear                mm worn off the biting edge
 * @property {number} chip                0..1 size of a broken incisal/cusp corner
 * @property {number} recession           mm of gum recession
 * @property {number} inflammation        0..1 gum redness/swelling next to this tooth
 * @property {number} calculus            0..1 tartar near the gum line
 * @property {number} boneLoss            mm of bone lost below the normal crest
 * @property {Array<{type:string, surfaces?:string[]}>} conditions   ids from CONDITIONS; surfaces from SURFACES
 */

/**
 * @typedef {Object} Treatment
 * @property {string} id                  unique in the snapshot
 * @property {string} type                id from TREATMENTS
 * @property {number[]} teeth             FDI numbers ([] for arch-wide: scaling, whitening, braces)
 * @property {('upper'|'lower')[]} [arches]  for arch-wide treatments
 * @property {string[]} [surfaces]        for fillings
 * @property {string} [material]          key of MATERIALS
 * @property {'planned'|'inProgress'|'completed'} status
 * @property {number} visit               1-based index into visits[]; the visit in which it is done
 * @property {Object} [options]           e.g. { post: true } for rct, { targetShade: 'BL3' } for whitening
 */

/**
 * @typedef {Object} Snapshot
 * @property {1} schema
 * @property {{baseShade:string, archWidth:number, archDepth:number}} profile   arch multipliers (1 = average)
 * @property {Object<string, Partial<ToothState>>} teeth   keyed by FDI number
 * @property {Treatment[]} treatments
 * @property {Array<{id:number, label:string, date?:string, note?:string}>} visits
 * @property {number} currentVisit        0 = today (before any treatment) … visits.length = final result
 */

export const defaultToothState = () => ({
  present: true, status: 'normal', statusColor: null, shade: null, stain: 0,
  shift: { md: 0, bl: 0, v: 0 }, rotate: { tip: 0, torque: 0, spin: 0 }, scale: { w: 1, h: 1 },
  wear: 0, chip: 0, recession: 0, inflammation: 0, calculus: 0, boneLoss: 0, conditions: [],
});

export const defaultSnapshot = () => ({
  schema: 1,
  profile: { baseShade: 'A2', archWidth: 1, archDepth: 1 },
  teeth: {}, treatments: [], visits: [], currentVisit: 0,
});

export const ALL_FDI = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28, 48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];
