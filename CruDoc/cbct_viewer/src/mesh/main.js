// Entry point of the scan viewer page (mesh.html). Flutter opens it as
// mesh.html?file=/m/<token>&name=upper.stl&title=... (see
// handoff/cbct_protocol.md, "Scan viewer").
import { start } from './boot.js';

console.log('Scan viewer booted');
start(new URLSearchParams(location.search));
