// Treatment and condition catalogue. Text is written for the patient:
// short, plain words. Each step is one beat of the explainer animation.
// `visual` names the animation the viewer plays for that step
// (implemented in src/treatments/).

export const SURFACES = ['M', 'O', 'D', 'B', 'L']; // mesial, occlusal/incisal, distal, buccal/labial, lingual/palatal

export const SHADES = {
  // VITA-style shade -> sRGB hex of the enamel body colour
  BL1: '#F6F4EC', BL3: '#F2EEE2', A1: '#EFE7D3', A2: '#E9DEC4', A3: '#E2D2B0', A35: '#DAC69E',
  A4: '#CFB688', B2: '#E8DFC0', C2: '#D6CDB4', C3: '#C9BE9F', D3: '#D2C4A8',
  STAIN_YELLOW: '#D9B25A', STAIN_BROWN: '#9C6B3A', NONVITAL_GREY: '#A39C8C',
};

export const MATERIALS = {
  composite: { label: 'Tooth-coloured (composite)', color: null /* matches tooth shade */, roughness: 0.35, metalness: 0 },
  amalgam: { label: 'Silver (amalgam)', color: '#8E9196', roughness: 0.45, metalness: 0.85 },
  gic: { label: 'Glass ionomer', color: '#E6E0CC', roughness: 0.6, metalness: 0 },
  zirconia: { label: 'Zirconia', color: '#F1EDE2', roughness: 0.18, metalness: 0 },
  emax: { label: 'Ceramic (E-max)', color: '#EFE8D6', roughness: 0.12, metalness: 0, transmission: 0.15 },
  pfm: { label: 'Porcelain on metal (PFM)', color: '#ECE5D2', roughness: 0.22, metalness: 0, metalCollar: '#7D8085' },
  metal: { label: 'Metal', color: '#A9ADB3', roughness: 0.28, metalness: 1 },
  gold: { label: 'Gold', color: '#D4AF37', roughness: 0.25, metalness: 1 },
  titanium: { label: 'Titanium', color: '#9EA3A8', roughness: 0.38, metalness: 1 },
  guttaPercha: { label: 'Root filling', color: '#F08A5D', roughness: 0.6, metalness: 0 },
};

export const CONDITIONS = [
  { id: 'caries', label: 'Decay (cavity)', perSurface: true, patientText: 'Bacteria have made a hole in the tooth. It grows deeper if left alone.' },
  { id: 'fracture', label: 'Chipped / broken', patientText: 'A piece of the tooth has broken off.' },
  { id: 'discolored', label: 'Discoloured', patientText: 'The tooth has turned darker than the others.' },
  { id: 'missing', label: 'Missing', patientText: 'This tooth is not there. Nearby teeth can drift into the gap.' },
  { id: 'impacted', label: 'Impacted', patientText: 'This tooth is stuck under the gum and cannot come out fully.' },
  { id: 'calculus', label: 'Tartar', patientText: 'Hard deposits have built up near the gum. They irritate the gum.' },
  { id: 'recession', label: 'Gum recession', patientText: 'The gum has moved down and part of the root is showing.' },
  { id: 'inflammation', label: 'Swollen gum', patientText: 'The gum is red and swollen and may bleed.' },
  { id: 'abscess', label: 'Infection at root tip', patientText: 'Infection has reached the tip of the root inside the bone.' },
  { id: 'attrition', label: 'Worn down', patientText: 'The biting edge has worn away over the years.' },
];

export const TREATMENTS = [
  {
    id: 'filling', label: 'Filling', scope: 'tooth', needsSurfaces: true, materials: ['composite', 'amalgam', 'gic'],
    summary: 'We clean out the decay and fill the hole.',
    steps: [
      { title: 'The cavity', text: 'This dark area is decay.', visual: 'show_caries' },
      { title: 'Clean', text: 'We remove the decayed part. The area is numb, so it does not hurt.', visual: 'drill_cavity' },
      { title: 'Fill', text: 'We place the filling material in layers.', visual: 'fill_material' },
      { title: 'Shape and polish', text: 'We shape it to your bite and polish it smooth.', visual: 'polish' },
    ],
  },
  {
    id: 'sealant', label: 'Sealant', scope: 'tooth', materials: ['composite'],
    summary: 'A thin coat that seals the deep grooves so decay cannot start.',
    steps: [
      { title: 'Deep grooves', text: 'Food and germs hide in these grooves.', visual: 'show_grooves' },
      { title: 'Seal', text: 'We paint a thin coat that flows into the grooves and set it with light.', visual: 'apply_sealant' },
    ],
  },
  {
    id: 'bonding', label: 'Bonding / build-up', scope: 'tooth', materials: ['composite'],
    summary: 'We rebuild a chipped edge or close a small gap with tooth-coloured material.',
    steps: [
      { title: 'The problem', text: 'A chipped edge or a gap.', visual: 'show_defect' },
      { title: 'Build up', text: 'We add tooth-coloured material and shape it by hand.', visual: 'build_up' },
      { title: 'Polish', text: 'We polish it to match your other teeth.', visual: 'polish' },
    ],
  },
  {
    id: 'rct', label: 'Root canal', scope: 'tooth', materials: ['guttaPercha'], options: ['post'],
    summary: 'We remove the infected nerve, clean the canals and seal them. The tooth stays.',
    steps: [
      { title: 'Inside the tooth', text: 'The nerve inside is infected. That is the cause of the pain.', visual: 'xray_show_pulp' },
      { title: 'Open', text: 'We make a small opening on top to reach the nerve.', visual: 'access_opening' },
      { title: 'Clean the canals', text: 'We remove the infected nerve and clean each canal.', visual: 'clean_canals' },
      { title: 'Fill the canals', text: 'We fill the canals so germs cannot come back.', visual: 'fill_canals' },
      { title: 'Close', text: 'We close the opening. A cap is usually needed afterwards to protect the tooth.', visual: 'close_access' },
    ],
  },
  {
    id: 'crown', label: 'Cap (crown)', scope: 'tooth', materials: ['zirconia', 'emax', 'pfm', 'metal', 'gold'],
    summary: 'A cap covers the whole tooth to protect it and restore its shape.',
    steps: [
      { title: 'Shape the tooth', text: 'We trim the tooth a little all around to make room for the cap.', visual: 'prep_crown' },
      { title: 'Measure', text: 'We take a scan or mould so the lab can make your cap.', visual: 'scan_flash' },
      { title: 'Fit the cap', text: 'The cap slides over the tooth and is cemented in place.', visual: 'seat_crown' },
    ],
  },
  {
    id: 'veneer', label: 'Veneer', scope: 'tooth', materials: ['emax', 'composite'],
    summary: 'A thin shell on the front of the tooth to improve colour and shape.',
    steps: [
      { title: 'Light trim', text: 'We remove a very thin layer from the front.', visual: 'prep_veneer' },
      { title: 'Bond the veneer', text: 'A thin shell is bonded to the front of the tooth.', visual: 'seat_veneer' },
    ],
  },
  {
    id: 'extraction', label: 'Removal (extraction)', scope: 'tooth',
    summary: 'We remove the tooth. The gum heals over in a few weeks.',
    steps: [
      { title: 'Loosen', text: 'The area is numb. We gently loosen the tooth.', visual: 'loosen_tooth' },
      { title: 'Remove', text: 'The tooth is lifted out.', visual: 'lift_tooth' },
      { title: 'Heal', text: 'The gum closes over the space as it heals.', visual: 'heal_socket' },
    ],
  },
  {
    id: 'implant', label: 'Implant', scope: 'tooth', materials: ['zirconia', 'pfm', 'emax'],
    summary: 'A titanium screw replaces the root. A cap is fixed on top.',
    steps: [
      { title: 'The gap', text: 'There is no tooth or root here.', visual: 'show_gap' },
      { title: 'Place the implant', text: 'A small titanium screw is placed in the bone.', visual: 'place_fixture' },
      { title: 'Heal', text: 'Over a few months the bone grips the implant firmly.', visual: 'osseointegrate' },
      { title: 'Connector', text: 'A small connector is fixed on the implant.', visual: 'place_abutment' },
      { title: 'New tooth', text: 'The cap is fixed on top. It looks and works like a tooth.', visual: 'seat_crown' },
    ],
  },
  {
    id: 'bridge', label: 'Bridge', scope: 'span', materials: ['zirconia', 'pfm', 'metal'],
    summary: 'The teeth next to the gap hold a false tooth between them.',
    steps: [
      { title: 'The gap', text: 'The missing tooth leaves a gap.', visual: 'show_gap' },
      { title: 'Shape the supports', text: 'We trim the teeth on each side of the gap.', visual: 'prep_crown' },
      { title: 'Fit the bridge', text: 'One piece: caps on the supports with a false tooth joined in the middle.', visual: 'seat_bridge' },
    ],
  },
  {
    id: 'scaling', label: 'Cleaning (scaling)', scope: 'arch',
    summary: 'We remove tartar and stains so the gums can heal.',
    steps: [
      { title: 'Tartar', text: 'These hard deposits irritate the gum.', visual: 'show_calculus' },
      { title: 'Clean', text: 'We remove the tartar from above and just below the gum line.', visual: 'remove_calculus' },
      { title: 'Healthy gums', text: 'The gum becomes pink and firm again.', visual: 'gum_heal' },
    ],
  },
  {
    id: 'whitening', label: 'Whitening', scope: 'arch',
    summary: 'A gel lightens the colour of the teeth.',
    steps: [
      { title: 'Before', text: 'Your current shade.', visual: 'show_shade' },
      { title: 'Whiten', text: 'The gel lightens the teeth by a few shades.', visual: 'whiten' },
    ],
  },
  {
    id: 'braces', label: 'Braces', scope: 'arch',
    summary: 'Brackets and a wire move the teeth slowly into line.',
    steps: [
      { title: 'Now', text: 'The teeth are out of line.', visual: 'show_alignment' },
      { title: 'Brackets and wire', text: 'A bracket is bonded on each tooth and joined by a wire.', visual: 'place_braces' },
      { title: 'Teeth move', text: 'Over months the wire guides each tooth into place.', visual: 'align_teeth' },
      { title: 'Remove', text: 'The braces come off. A retainer keeps the result.', visual: 'remove_braces' },
    ],
  },
];

// How the app's status maps to the heat-map colours.
export const STATUS_COLORS = { normal: null, selected: '#3B82F6', flagged: '#EF4444', planned: '#F59E0B', inProgress: '#8B5CF6', completed: '#10B981' };
