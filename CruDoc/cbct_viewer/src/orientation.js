// Orientation letters for a view's four edges (guide A3.8).
// World axes are DICOM LPS: +x Left, +y Posterior, +z Superior.
const NAMES = [
  ['L', 'R'],
  ['P', 'A'],
  ['S', 'I'],
];

// The letters for direction d: components above 0.25, biggest first, at most two.
export function letters(d) {
  return d
    .map((v, i) => ({ size: Math.abs(v), letter: NAMES[i][v >= 0 ? 0 : 1] }))
    .filter((c) => c.size > 0.25)
    .sort((a, b) => b.size - a.size)
    .slice(0, 2)
    .map((c) => c.letter)
    .join('');
}

const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const neg = (v) => v.map((x) => -x);

// Screen right = viewUp x viewPlaneNormal.
export function orientationLetters(viewUp, viewPlaneNormal) {
  const right = cross(viewUp, viewPlaneNormal);
  return { top: letters(viewUp), bottom: letters(neg(viewUp)), right: letters(right), left: letters(neg(right)) };
}
