import { clearance, safety } from './plan.js';

export function planSummary(plan, measures, found) {
  const lines = ['Implant plan'];

  // Nerve canal line
  const rightPts = plan?.nerves?.right;
  const leftPts = plan?.nerves?.left;

  const rightStr = rightPts && rightPts.length > 0
    ? `right traced (${rightPts.length} points)`
    : 'right not traced';
  const leftStr = leftPts && leftPts.length > 0
    ? `left traced (${leftPts.length} points)`
    : 'left not traced';

  lines.push(`Nerve canal: ${rightStr}, ${leftStr}`);

  // Implants
  const implants = plan?.implants || [];
  const validNerves = [rightPts, leftPts].filter((n) => n && n.length >= 2);

  implants.forEach((im, idx) => {
    const num = idx + 1;
    const diam = im.diameter != null ? im.diameter.toFixed(1) : '–';
    const len = im.length != null ? im.length.toFixed(1) : '–';
    const jaw = im.jaw === 'upper' ? 'upper jaw' : 'lower jaw';
    const tiltAP = im.tiltAP != null ? Math.round(im.tiltAP) : 0;
    const tiltLR = im.tiltLR != null ? Math.round(im.tiltLR) : 0;

    lines.push(`Implant ${num}: ${diam} x ${len} mm, ${jaw}, tilt A-P ${tiltAP}°, L-R ${tiltLR}°`);

    // Distance to nerve canal
    if (validNerves.length === 0) {
      lines.push('  Distance to the nerve canal: not checked (no canal traced)');
    } else {
      const dist = clearance(im, validNerves);
      if (dist == null) {
        lines.push('  Distance to the nerve canal: not checked (no canal traced)');
      } else {
        const s = safety(dist);
        const safetyWord = s === 'danger' ? 'too close' : s === 'close' ? 'close' : 'safe';
        lines.push(`  Distance to the nerve canal ${dist.toFixed(1)} mm (${safetyWord})`);
      }
    }

    // Bone width / height measurements if available
    const m = measures ? measures[idx] : null;
    if (m) {
      const wc = m.widthCrest != null ? m.widthCrest.toFixed(1) : '–';
      const wm = m.widthMid != null ? m.widthMid.toFixed(1) : '–';
      const isUpper = im.jaw === 'upper';
      const hRoof = isUpper ? 'height to the sinus floor' : 'height to the canal roof';
      const hVal = isUpper
        ? (m.heightToAir != null ? m.heightToAir.toFixed(1) : '–')
        : (m.heightToNerve != null ? m.heightToNerve.toFixed(1) : '–');

      lines.push(`  Bone width ${wc} mm near the crest, ${wm} mm at mid; ${hRoof} ${hVal} mm`);
    }
  });

  // Found automatically
  if (found && found.length > 0) {
    const count = found.length;
    const objWord = count === 1 ? 'object' : 'objects';
    const sizes = found.map((f) => {
      const dims = f.sizeMm || [0, 0, 0];
      const x = dims[0] != null ? dims[0].toFixed(1) : '–';
      const y = dims[1] != null ? dims[1].toFixed(1) : '–';
      const z = dims[2] != null ? dims[2].toFixed(1) : '–';
      return `${x} x ${y} x ${z} mm`;
    });
    lines.push(`Found automatically: ${count} metal or very dense ${objWord} (${sizes.join(', ')})`);
  }

  return lines.join('\n');
}

