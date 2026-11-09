# CBCT 3D Viewer Guide

A quick reference for clinicians using the four-panel 3D CBCT viewer in CruDoc.

---

## 1. Opening 3D & "Preparing 3D, once per scan"

You can open a CBCT scan in 3D from the sidebar's **Tasks** page (its **Worklist** tab): use the "Open in 3D" item in the study row's "⋯" menu. You can also open the study in the 2D slice viewer and tap the "3D" button on its toolbar. Scans are added with **Import scans** on the same Worklist tab.

The first time a CBCT scan is opened on your device, CruDoc prepares an optimized volume pack (raw 16-bit voxel files and preview posters) in a background process. While this runs, a progress indicator displays:

> **"Preparing 3D · once per scan · XX%"**

This process happens only once per scan. The processed volume is saved to local storage so subsequent visits open instantly with zero waiting time.

---

## 2. The Four Views & Coloured Reference Lines

The screen is arranged in a 2×2 grid displaying three orthogonal cross-sectional multi-planar reconstructions (MPR) alongside a 3D volume rendering:

- **Axial (Gold / Amber line):** Top-down horizontal view (transverse). Looking from superior toward inferior, with the patient's anterior (A) at the top and right side (R) on the left.
- **3D Volume (Grey):** Interactive 3D reconstruction showing bones, teeth, and soft tissues in space.
- **Coronal (Teal / Cyan line):** Front-to-back vertical view. Looking from anterior toward posterior, with superior (S) at the top and patient's right (R) on the left.
- **Sagittal (Violet / Purple line):** Side-to-side vertical profile. Looking from lateral toward medial, with superior (S) at the top and anterior (A) on the left.

The colored crosshair lines intersect at the exact same physical 3D point across all three planar views. Moving the crosshair or scrolling a slice in one view immediately updates the slice positions in the other two views. In the 3D viewport, colored planar outlines show exactly where each current slice sits within the volume.

---

## 3. Mouse, Keyboard & Touch Shortcuts

The viewer provides quick single-key shortcuts and mouse navigation:

| Shortcut | Action |
|---|---|
| `C P Z W` | Crosshair, pan, zoom, window / level |
| `L A E` | Length, angle, ellipse measurement |
| `1 – 5` | Contrast presets |
| `↑ ↓  PgUp PgDn` | Slice ±1 / ±10 in the hovered view |
| `H` | Hide or show lines, labels and measurements |
| `R` | Reset views, window, slab, cut and invert |
| `S` | Save the active view as a key image |
| `F` | Maximise the hovered view |
| `]` | Show or hide the right panel |
| `?` | This sheet |
| `Esc` | Close this sheet, then leave the maximised view |
| `Left-drag` | The active tool (3D: rotate) |
| `Right-drag` | Window and level |
| `Middle-drag` | Pan |
| `Wheel  ·  Shift + wheel` | Scroll slices  ·  10 slices (3D: zoom) |
| `Ctrl + wheel` | Zoom at the cursor |
| `Double-click` | Maximise or restore a view |

---

## 4. Contrast Presets

Window and level settings control image brightness and contrast. Select them from the side panel or press keys `1` to `5`:

- **Bone (`1`):** Default window optimized for cortical bone, trabecular structures, alveolar ridges, and jaw boundaries.
- **Teeth (`2`):** High-density threshold separating enamel, dentine, pulp chambers, root canals, and restorative materials.
- **Soft tissue (`3`):** Narrow contrast window revealing airway patency, soft tissue margins, and sinus mucosal thickening.
- **Fine bone (`4`):** High-contrast bone preset enhancing thin cortical plates, the mandibular canal cortex, and delicate periodontal bone margins.
- **Full range (`5`):** Displays the full dynamic range captured by the detector, from air (-1000) through soft tissue and bone up to high-density dental restorations.

---

## 5. 3D Looks & "Cut at Crosshair"

The 3D viewport renders spatial relationships using specialized transfer functions:

- **Bone:** Clean volume rendering of the bony skull, maxilla, and mandible.
- **Teeth:** Shows only the densest structures.
- **Skin + bone:** Composite view showing the facial surface overlaid upon the underlying skeletal anatomy.
- **X-ray:** An average-intensity picture through the volume.
- **MIP:** Maximum intensity projection showing the brightest voxel along each ray.

### Cut at Crosshair
Allows virtual resection of the 3D volume along any anatomical plane:
- Set cut to **Axial**, **Coronal**, or **Sagittal** to slice open the 3D volume at the current crosshair position.
- Tap **Flip** to invert which half of the volume is removed.
- Set cut to **Off** to restore the complete volume.

---

## 6. Measuring Tools

Select measurement tools from the top toolbar or using keyboard shortcuts:

- **Length (`L`):** Click and drag between two anatomical landmarks to measure linear distance in millimeters.
- **Angle (`A`):** Click three points to measure anatomical angles in degrees.
- **Ellipse (`E`):** Draws an oval and shows its statistics.

Press `H` at any time to temporarily hide all annotations and reference lines for an unobstructed view.

---

## 7. Saving Key Images (`S`)

Pressing `S` or clicking the camera icon instantly captures the currently active viewport at high resolution:
- The saved snapshot burns in the active slice, orientation tags, scale bar, and any drawn measurements.
- The picture is saved as a key image on the study.

---

## 8. Privacy, Storage & Offline Architecture

The CBCT 3D viewer is designed with privacy and reliability at its core:
- The 3D data is a cache stored next to the study on this device (`<study folder>/.cbct/`).
- It is rebuilt automatically if deleted.
- The viewer page itself never uses the network.
