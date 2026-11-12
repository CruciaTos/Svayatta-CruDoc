import * as THREE from 'three';
import { MATERIALS, SHADES } from '../data/treatments.js';
import { setTint } from '../engine/toothMaterial.js';

// One function per step `visual`. Steps are cumulative: the player resets to the patient's
// state, then replays steps 0..n-1 with `instant: true` (no camera move, jump to the end)
// and animates step n. Every change pushes an undo onto one list that `reset()` runs in
// reverse, so stepping back or closing restores the exact starting look. Nothing here
// loops: a ticker returns false when it is done and the stage stops rendering.
export function createAnimationRunner({ stage, registry, store, gums, cameraRig, appearance, visuals }) {
  let activeTicker = null;
  let cancelTicker = null;
  const undo = [];
  let baselineMode = 'pbr';

  // Stops the running animation but leaves its changes in place.
  function stopMotion() {
    if (cancelTicker) {
      cancelTicker();
      cancelTicker = null;
    } else if (activeTicker && stage.removeTicker) {
      stage.removeTicker(activeTicker);
    }
    activeTicker = null;
  }

  // Back to the state before the first step.
  function reset() {
    stopMotion();
    for (let i = undo.length - 1; i >= 0; i--) {
      try { undo[i](); } catch (err) { console.error('Animation cleanup error:', err); }
    }
    undo.length = 0;
    stage.invalidate();
  }

  const setPreview = (patch) => {
    const cur = store.get().preview;
    if (cur) store.set({ preview: { ...cur, ...patch } });
  };

  // Pulps share a few materials; give the animated tooth's pulp its own colour.
  function ownPulp(fdi) {
    const obj = registry.pulps.get(+fdi);
    const mesh = obj?.userData?.meshes?.[0];
    if (!mesh) return null;
    const mat = mesh.material.clone();
    obj.userData.matOverride = mat;
    appearance.refresh();
    undo.push(() => { delete obj.userData.matOverride; mat.dispose(); appearance.refresh(); });
    return mat;
  }

  // Hides parts of a tooth (its own mesh, or treatment visuals) until the step that shows them.
  function hide(toothObj, pred) {
    const items = [];
    if (pred === 'natural') items.push(...toothObj.userData.meshes);
    else for (const c of toothObj.children) if (c.userData.isTreatmentVisual && pred(c)) items.push(c);
    for (const o of items) {
      const was = o.visible;
      o.visible = false;
      undo.push(() => { o.visible = was; });
    }
  }

  function runVisual({ visual, treatment, targetFdi, instant = false }) {
    stopMotion();

    const toothObj = targetFdi ? registry.teeth.get(+targetFdi) : null;
    const baseMesh = toothObj?.userData?.meshes?.[0];
    const mat = baseMesh?.userData?.natural;
    const cleanups = undo;
    const fly = (id) => { if (!instant && id) cameraRig.flyTo(id, 600); };
    const front = () => { if (!instant) cameraRig.preset('front', 600); };
    const teethOf = () => (treatment?.teeth?.length ? treatment.teeth.map(Number) : [+targetFdi]);

    // Runs onTick(k) over `duration` ms; with `instant` jumps straight to the end.
    const startTicker = (duration, onTick, onComplete) => {
      if (instant) {
        onTick(1, 1);
        if (onComplete) onComplete();
        return;
      }
      const startTime = performance.now();
      const tick = () => {
        const raw = Math.min(1, (performance.now() - startTime) / duration);
        const k = raw * raw * (3 - 2 * raw); // smoothstep
        onTick(k, raw);
        stage.invalidate();
        if (raw >= 1) {
          if (onComplete) onComplete();
          activeTicker = null;
          return false;
        }
        return true;
      };
      activeTicker = tick;
      cancelTicker = stage.addTicker(tick);
      stage.invalidate();
    };

    switch (visual) {
      // 1. CARIES & GROOVES
      case 'show_caries': {
        if (toothObj) {
          fly(toothObj?.name);
          if (mat) {
            const origTint = mat.userData.u?.uTint?.value?.clone();
            startTicker(900, (k) => {
              const pulse = Math.sin(k * Math.PI) * 0.45;
              setTint(mat, '#EF4444', pulse);
            }, () => {
              if (origTint) mat.userData.u.uTint.value.copy(origTint);
            });
            cleanups.push(() => {
              if (origTint && mat.userData.u) mat.userData.u.uTint.value.copy(origTint);
            });
          }
        }
        break;
      }

      case 'show_grooves': {
        if (toothObj) {
          fly(toothObj?.name);
          if (mat) {
            const origTint = mat.userData.u?.uTint?.value?.clone();
            startTicker(800, (k) => {
              const pulse = Math.sin(k * Math.PI) * 0.35;
              setTint(mat, '#3B82F6', pulse);
            }, () => {
              if (origTint) mat.userData.u.uTint.value.copy(origTint);
            });
            cleanups.push(() => {
              if (origTint && mat.userData.u) mat.userData.u.uTint.value.copy(origTint);
            });
          }
        }
        break;
      }

      case 'show_defect': {
        if (toothObj) {
          fly(toothObj?.name);
          if (mat) {
            const origTint = mat.userData.u?.uTint?.value?.clone();
            startTicker(800, (k) => {
              const pulse = Math.sin(k * Math.PI) * 0.4;
              setTint(mat, '#F59E0B', pulse);
            }, () => {
              if (origTint) mat.userData.u.uTint.value.copy(origTint);
            });
            cleanups.push(() => {
              if (origTint && mat.userData.u) mat.userData.u.uTint.value.copy(origTint);
            });
          }
        }
        break;
      }

      case 'show_gap': {
        if (toothObj) {
          fly(toothObj?.name);
        } else {
          front();
        }
        break;
      }

      case 'show_calculus': {
        if (toothObj) {
          fly(toothObj?.name);
          if (mat) {
            const origTint = mat.userData.u?.uTint?.value?.clone();
            startTicker(800, (k) => {
              const pulse = Math.sin(k * Math.PI) * 0.4;
              setTint(mat, '#D97706', pulse);
            }, () => {
              if (origTint) mat.userData.u.uTint.value.copy(origTint);
            });
            cleanups.push(() => {
              if (origTint && mat.userData.u) mat.userData.u.uTint.value.copy(origTint);
            });
          }
        }
        break;
      }

      case 'show_shade': {
        front();
        break;
      }

      case 'show_alignment': {
        front();
        break;
      }

      case 'drill_cavity': {
        if (mat?.userData?.u) {
          fly(toothObj?.name);
          const origCaries = [...mat.userData.u.uSurfCaries.value];
          const origFill = mat.userData.u.uSurfFill.value.map((v) => v.clone());
          startTicker(900, (k) => {
            for (let i = 0; i < 5; i++) {
              mat.userData.u.uSurfCaries.value[i] = origCaries[i] * (1 - k);
              // Dark excavated hollow
              if (origCaries[i] > 0.1) {
                mat.userData.u.uSurfFill.value[i].set(0.08, 0.05, 0.03, k);
              }
            }
          });
          cleanups.push(() => {
            if (mat.userData.u) {
              for (let i = 0; i < 5; i++) {
                mat.userData.u.uSurfCaries.value[i] = origCaries[i];
                mat.userData.u.uSurfFill.value[i].copy(origFill[i]);
              }
            }
          });
        }
        break;
      }

      case 'fill_material':
      case 'apply_sealant':
      case 'build_up': {
        if (mat?.userData?.u) {
          fly(toothObj?.name);
          const matKey = treatment.material || 'composite';
          const isAmalgam = matKey === 'amalgam';
          const fillCol = isAmalgam ? new THREE.Color(MATERIALS.amalgam.color) : new THREE.Color('#F2EFE8');
          const metal = isAmalgam ? 0.85 : 0;
          const origFill = mat.userData.u.uSurfFill.value.map((v) => v.clone());
          const origMetal = [...mat.userData.u.uSurfMetal.value];

          startTicker(900, (k) => {
            // Apply fill to surfaces (or occlusal if not specified)
            const surfs = treatment.surfaces || ['O'];
            const sMap = { M: 0, O: 1, D: 2, B: 3, L: 4 };
            for (const s of surfs) {
              const idx = sMap[s] ?? 1;
              mat.userData.u.uSurfFill.value[idx].set(fillCol.r, fillCol.g, fillCol.b, k);
              mat.userData.u.uSurfMetal.value[idx] = metal * k;
            }
          });
          cleanups.push(() => {
            if (mat.userData.u) {
              for (let i = 0; i < 5; i++) {
                mat.userData.u.uSurfFill.value[i].copy(origFill[i]);
                mat.userData.u.uSurfMetal.value[i] = origMetal[i];
              }
            }
          });
        }
        break;
      }

      case 'polish': {
        if (mat) {
          const origRough = mat.roughness;
          const origClearcoatRough = mat.clearcoatRoughness;
          startTicker(700, (k) => {
            const dip = Math.sin(k * Math.PI);
            mat.roughness = THREE.MathUtils.lerp(origRough, 0.02, dip);
            mat.clearcoatRoughness = THREE.MathUtils.lerp(origClearcoatRough, 0.02, dip);
          }, () => {
            mat.roughness = origRough;
            mat.clearcoatRoughness = origClearcoatRough;
          });
          cleanups.push(() => {
            mat.roughness = origRough;
            mat.clearcoatRoughness = origClearcoatRough;
          });
        }
        break;
      }

      // 2. ROOT CANAL TREATMENT (RCT)
      case 'xray_show_pulp': {
        const prevMode = store.get().mode;
        store.set({ mode: 'xray' });
        cleanups.push(() => { store.set({ mode: prevMode }); });
        fly(toothObj?.name);
        const pulpMat = ownPulp(targetFdi);
        if (pulpMat) {
          const origColor = pulpMat.color.clone();
          startTicker(900, (k) => {
            const pulse = Math.sin(k * Math.PI);
            pulpMat.color.setRGB(1.0, 0.23 + 0.5 * (1 - pulse), 0.19);
          }, () => { pulpMat.color.copy(origColor); });
        }
        break;
      }

      case 'access_opening': {
        if (mat?.userData?.u) {
          fly(toothObj.name);
          const origFill = mat.userData.u.uSurfFill.value[1].clone();
          startTicker(800, (k) => {
            // Small dark circle on O
            mat.userData.u.uSurfFill.value[1].set(0.05, 0.03, 0.02, k);
          });
          cleanups.push(() => mat.userData.u.uSurfFill.value[1].copy(origFill));
        }
        break;
      }

      case 'clean_canals':
      case 'fill_canals': {
        const prevMode = store.get().mode;
        if (prevMode !== 'xray') {
          store.set({ mode: 'xray' });
          cleanups.push(() => { store.set({ mode: prevMode }); });
        }
        const pulpMat = ownPulp(targetFdi);
        if (pulpMat) {
          const from = visual === 'clean_canals' ? pulpMat.color.clone() : new THREE.Color('#FCE7F3');
          const to = visual === 'clean_canals' ? new THREE.Color('#FCE7F3') : new THREE.Color(MATERIALS.guttaPercha.color);
          startTicker(900, (k) => { pulpMat.color.lerpColors(from, to, k); });
        }
        break;
      }

      case 'close_access': {
        if (mat?.userData?.u) {
          // Back to the plain tooth so the closed opening can be seen.
          const prevMode = store.get().mode;
          if (prevMode !== baselineMode) {
            store.set({ mode: baselineMode });
            cleanups.push(() => { store.set({ mode: prevMode }); });
          }
          const origFill = mat.userData.u.uSurfFill.value[1].clone();
          startTicker(800, (k) => {
            mat.userData.u.uSurfFill.value[1].set(0.95, 0.93, 0.90, k);
          });
          cleanups.push(() => mat.userData.u.uSurfFill.value[1].copy(origFill));
        }
        break;
      }

      // 3. CROWN & VENEER
      case 'prep_crown':
      case 'prep_veneer': {
        const amount = visual === 'prep_veneer' ? 0.7 : 1;
        const all = teethOf();
        const list = treatment?.type === 'bridge' && all.length >= 2 ? [all[0], all[all.length - 1]] : [+targetFdi];
        fly(toothObj?.name);
        for (const f of list) {
          const m = registry.teeth.get(f)?.userData?.meshes?.[0]?.userData?.natural;
          if (!m?.userData?.u) continue;
          const origPrep = m.userData.u.uPrep.value;
          startTicker(900, (k) => { m.userData.u.uPrep.value = k * amount; });
          cleanups.push(() => { m.userData.u.uPrep.value = origPrep; });
        }
        break;
      }

      case 'scan_flash': {
        if (mat) {
          fly(toothObj.name);
          const origTint = mat.userData.u?.uTint?.value?.clone();
          startTicker(600, (k) => {
            const flash = Math.sin(k * Math.PI) * 0.85;
            setTint(mat, '#FFFFFF', flash);
          }, () => {
            if (origTint) mat.userData.u.uTint.value.copy(origTint);
          });
          cleanups.push(() => {
            if (origTint && mat.userData.u) mat.userData.u.uTint.value.copy(origTint);
          });
        }
        break;
      }

      case 'seat_crown':
      case 'seat_veneer':
      case 'seat_bridge': {
        // The player puts the finished work in place first (preview); here the caps slide on.
        fly(toothObj?.name);
        for (const f of (visual === 'seat_bridge' ? teethOf() : [+targetFdi])) {
          const obj = registry.teeth.get(f);
          const cap = obj?.children.find((c) => c.userData.isTreatmentVisual && c.isMesh);
          if (!cap) continue;
          if (treatment?.type === 'implant') hide(obj, 'natural'); // the cap alone, not the old crown under it
          const origY = cap.position.y;
          cap.position.y = origY + 9.0;
          startTicker(900, (k) => { cap.position.y = THREE.MathUtils.lerp(origY + 9.0, origY, k); },
            () => { cap.position.y = origY; });
          cleanups.push(() => { cap.position.y = origY; });
        }
        break;
      }

      // 4. EXTRACTION
      case 'loosen_tooth': {
        if (toothObj) {
          fly(toothObj.name);
          const origRot = toothObj.quaternion.clone();
          const axis = new THREE.Vector3(0, 0, 1);
          const qWobble = new THREE.Quaternion();
          startTicker(800, (k) => {
            const angle = Math.sin(k * Math.PI * 4) * 0.06 * (1 - k);
            qWobble.setFromAxisAngle(axis, angle);
            toothObj.quaternion.copy(origRot).multiply(qWobble);
          }, () => { toothObj.quaternion.copy(origRot); });
          cleanups.push(() => { toothObj.quaternion.copy(origRot); });
        }
        break;
      }

      case 'lift_tooth': {
        if (toothObj) {
          fly(toothObj.name);
          const coronal = new THREE.Vector3(...toothObj.userData.part.frame.coronal);
          const origPos = toothObj.position.clone();
          const origVis = toothObj.visible;
          const origOpac = mat?.opacity ?? 1;
          const origTransp = mat?.transparent ?? false;
          if (mat) { mat.transparent = true; mat.needsUpdate = true; }
          startTicker(1000, (k) => {
            toothObj.position.copy(origPos).addScaledVector(coronal, 14.0 * k);
            if (mat) mat.opacity = 1.0 - k;
          });
          cleanups.push(() => {
            toothObj.position.copy(origPos);
            toothObj.visible = origVis;
            if (mat) {
              mat.opacity = origOpac;
              mat.transparent = origTransp;
              mat.needsUpdate = true;
            }
          });
        }
        break;
      }

      // The socket closing is the preview state itself (the tooth is gone, the gum rebuilds).
      case 'heal_socket': {
        fly(toothObj?.name);
        break;
      }

      // 5. IMPLANT
      case 'place_fixture': {
        if (toothObj) {
          fly(toothObj.name);
          hide(toothObj, 'natural');
          const fixture = toothObj.children.find((c) => c.userData.isTreatmentVisual && c.children?.length);
          hide(toothObj, (c) => c !== fixture); // connector and cap come later
          if (fixture) {
            const origPos = fixture.position.clone();
            const origRot = fixture.quaternion.clone();
            const startY = origPos.y + 10.0;
            startTicker(1000, (k) => {
              fixture.position.y = THREE.MathUtils.lerp(startY, origPos.y, k);
              fixture.rotation.y = (1.0 - k) * Math.PI * 4;
            }, () => {
              fixture.position.copy(origPos);
              fixture.quaternion.copy(origRot);
            });
            cleanups.push(() => {
              fixture.position.copy(origPos);
              fixture.quaternion.copy(origRot);
            });
          }
        }
        break;
      }

      case 'osseointegrate': {
        if (toothObj) {
          fly(toothObj.name);
          hide(toothObj, 'natural');
          const fixture = toothObj.children.find((c) => c.userData.isTreatmentVisual && c.children?.length);
          hide(toothObj, (c) => c !== fixture);
          if (!instant) {
            // Look through the gum at the bone while it grips the implant.
            const prevLayers = { ...store.get().layers };
            store.set({ layers: { gums: false, bone: true } });
            cleanups.push(() => { store.set({ layers: prevLayers }); });
          }
          const glow = (g) => fixture?.traverse((m) => {
            if (m.isMesh && m.material.emissive) m.material.emissive.setRGB(0.96 * g, 0.62 * g, 0.04 * g);
          });
          startTicker(1000, (k) => glow(Math.sin(k * Math.PI) * 0.7), () => glow(0));
          cleanups.push(() => glow(0));
        }
        break;
      }

      case 'place_abutment': {
        if (toothObj) {
          fly(toothObj.name);
          hide(toothObj, 'natural');
          hide(toothObj, (c) => c.isMesh); // the cap comes in the last step
          const list = toothObj.children.filter((c) => c.userData.isTreatmentVisual);
          const abutment = list[1] || list[0];
          if (abutment) {
            const origPos = abutment.position.clone();
            const startY = origPos.y + 6.0;
            startTicker(700, (k) => { abutment.position.y = THREE.MathUtils.lerp(startY, origPos.y, k); },
              () => { abutment.position.copy(origPos); });
            cleanups.push(() => { abutment.position.copy(origPos); });
          }
        }
        break;
      }

      // 6. SCALING & WHITENING
      case 'remove_calculus': {
        front();
        const orig = new Map();
        for (const [f, o] of registry.teeth) {
          const m = o.userData.meshes[0]?.userData?.natural;
          if (m?.userData?.u) orig.set(f, m.userData.u.uCalculus.value);
        }
        const set = (f, v) => {
          const m = registry.teeth.get(f)?.userData.meshes[0]?.userData?.natural;
          if (m?.userData?.u) m.userData.u.uCalculus.value = v;
        };
        startTicker(800, (k) => { for (const [f, v] of orig) set(f, v * (1 - k)); });
        cleanups.push(() => { for (const [f, v] of orig) set(f, v); });
        break;
      }

      // Healthy gums are the preview state itself (inflammation and tartar are gone).
      case 'gum_heal': {
        front();
        break;
      }

      case 'whiten': {
        front();
        const orig = new Map();
        const target = new THREE.Color(SHADES.BL1);
        for (const [f, o] of registry.teeth) {
          const m = o.userData.meshes[0]?.userData?.natural;
          if (m?.userData?.u?.uShade) orig.set(f, m.userData.u.uShade.value.clone());
        }
        const shade = (f) => registry.teeth.get(f)?.userData.meshes[0]?.userData?.natural?.userData?.u?.uShade;
        startTicker(900, (k) => { for (const [f, col] of orig) shade(f)?.value.lerpColors(col, target, k); });
        cleanups.push(() => { for (const [f, col] of orig) shade(f)?.value.copy(col); });
        break;
      }

      // 7. BRACES (brackets and wire come with the preview state)
      case 'place_braces':
      case 'remove_braces': {
        front();
        break;
      }

      case 'align_teeth': {
        front();
        // `quick` skips the heavy rebuild of brackets and wire while the teeth move.
        startTicker(1400, (k) => setPreview({ progress: k, quick: k < 1 }), () => setPreview({ progress: 1, quick: false }));
        break;
      }

      default: {
        if (toothObj) fly(toothObj?.name);
        break;
      }
    }
  }

  return { runVisual, reset, stopMotion, setBaselineMode(m) { baselineMode = m; } };
}

