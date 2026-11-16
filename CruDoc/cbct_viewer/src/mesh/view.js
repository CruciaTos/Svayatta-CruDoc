// The 3D scene for one surface mesh: an intraoral scan, a lab design or a
// printed model. vtk.js draws it the same way the CBCT viewer draws its
// surfaces (actor + mapper + polydata), so the look matches: ivory by default,
// the scanner's own colours when the file carries them.
import '@kitware/vtk.js/Rendering/Profiles/Geometry.js';
import vtkGenericRenderWindow from '@kitware/vtk.js/Rendering/Misc/GenericRenderWindow.js';
import vtkActor from '@kitware/vtk.js/Rendering/Core/Actor.js';
import vtkMapper from '@kitware/vtk.js/Rendering/Core/Mapper.js';
import vtkPolyData from '@kitware/vtk.js/Common/DataModel/PolyData.js';
import vtkDataArray from '@kitware/vtk.js/Common/Core/DataArray.js';

// #ece1c9, the same ivory the CBCT viewer's bone surfaces use (tokens.css).
const IVORY = [0.925, 0.882, 0.788];
// Clear to nothing, so the page's own radial gradient (--3d-bg, the same one
// the CBCT viewer's 3D panel uses) shows through behind the surface.
const BACKGROUND = [0, 0, 0, 0];

/** The view direction of each named look, in the file's own axes. */
const LOOKS = {
  front: { dir: [0, -1, 0], up: [0, 0, 1] },
  top: { dir: [0, 0, 1], up: [0, -1, 0] },
  side: { dir: [1, 0, 0], up: [0, 0, 1] },
};

/** Triangle corners as a vtk cell array: a count in front of every triangle. */
export function cellArray(indices, triangles) {
  const cells = new Uint32Array(triangles * 4);
  for (let t = 0; t < triangles; t++) {
    cells[t * 4] = 3;
    cells[t * 4 + 1] = indices ? indices[t * 3] : t * 3;
    cells[t * 4 + 2] = indices ? indices[t * 3 + 1] : t * 3 + 1;
    cells[t * 4 + 3] = indices ? indices[t * 3 + 2] : t * 3 + 2;
  }
  return cells;
}

export function createScene(container) {
  const win = vtkGenericRenderWindow.newInstance({ background: BACKGROUND, listenWindowResize: false });
  win.setContainer(container);
  const renderer = win.getRenderer();
  const renderWindow = win.getRenderWindow();
  const camera = renderer.getActiveCamera();

  let actor = null;
  let mapper = null;
  let hasColours = false;
  let bounds = null;

  const render = () => renderWindow.render();

  const sizeToContainer = () => {
    win.resize();
  };
  const observer = new ResizeObserver(sizeToContainer);
  observer.observe(container);

  /** Puts one parsed mesh on screen, replacing whatever was there. */
  function showMesh(mesh) {
    if (actor) {
      renderer.removeActor(actor);
      actor.delete();
      mapper.delete();
    }
    const polydata = vtkPolyData.newInstance();
    polydata.getPoints().setData(mesh.positions, 3);
    polydata.getPolys().setData(cellArray(mesh.indices, mesh.triangles));
    if (mesh.normals) {
      polydata.getPointData().setNormals(
        vtkDataArray.newInstance({ name: 'Normals', numberOfComponents: 3, values: mesh.normals }),
      );
    }
    hasColours = !!mesh.colors;
    if (hasColours) {
      polydata.getPointData().setScalars(
        vtkDataArray.newInstance({ name: 'Colours', numberOfComponents: 3, values: mesh.colors }),
      );
    }

    mapper = vtkMapper.newInstance();
    mapper.setInputData(polydata);
    mapper.setScalarVisibility(false); // ivory to begin with, even when the file has colours
    mapper.setScalarModeToUsePointData();
    mapper.setColorModeToDirectScalars();

    actor = vtkActor.newInstance();
    actor.setMapper(mapper);
    const prop = actor.getProperty();
    prop.setColor(...IVORY);
    prop.setInterpolationToPhong();
    prop.setAmbient(0.22);
    prop.setDiffuse(0.88);
    prop.setSpecular(0.22);
    prop.setSpecularPower(28);
    renderer.addActor(actor);

    bounds = mesh.bounds;
    look('front');
  }

  /** Frames the whole mesh from one of the named directions. */
  function look(name) {
    const { dir, up } = LOOKS[name] || LOOKS.front;
    const centre = bounds
      ? [(bounds[0] + bounds[1]) / 2, (bounds[2] + bounds[3]) / 2, (bounds[4] + bounds[5]) / 2]
      : [0, 0, 0];
    camera.setFocalPoint(...centre);
    camera.setPosition(centre[0] - dir[0], centre[1] - dir[1], centre[2] - dir[2]);
    camera.setViewUp(...up);
    camera.orthogonalizeViewUp();
    renderer.resetCamera();
    // A touch off dead-on, so the surface reads as a solid from the first frame.
    camera.elevation(-12);
    camera.azimuth(12);
    camera.orthogonalizeViewUp();
    // resetCamera frames the mesh's bounding ball, which leaves a wide margin
    // around an arch: this fills the view without cropping the far corners.
    camera.zoom(1.35);
    renderer.resetCameraClippingRange();
    render();
  }

  /** 'ivory' or 'scan' (the colours in the file; ignored when it has none). */
  function setColourMode(mode) {
    if (!mapper) return;
    mapper.setScalarVisibility(mode === 'scan' && hasColours);
    render();
  }

  return {
    showMesh,
    look,
    setColourMode,
    render,
    resize: sizeToContainer,
    hasColours: () => hasColours,
    canvas: () => container.querySelector('canvas'),
    destroy() {
      observer.disconnect();
      if (actor) {
        renderer.removeActor(actor);
        actor.delete();
        mapper.delete();
        actor = null;
        mapper = null;
      }
      win.delete();
    },
  };
}
