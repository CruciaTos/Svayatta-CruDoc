// The one fit rule, shared with Dart (lib/features/radiology/cbct/cbct_fit.dart).
// A viewport of W x H px showing a plane of u x v mm: the whole plane fits,
// centred. parallelScale is half the visible height in mm (Cornerstone's unit).
export function fitCamera(W, H, u, v) {
  const aspect = W / H;
  const parallelScale = Math.max(v / 2, u / (2 * aspect));
  const pxPerMm = H / (2 * parallelScale);
  return { parallelScale, pxPerMm, rectW: u * pxPerMm, rectH: v * pxPerMm };
}
