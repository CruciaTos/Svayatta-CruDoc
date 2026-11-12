"""Update blender/contact_scale.json (per tooth: how far the mesial / distal edge of the crown grows, mm; identical for
the left/right mirror teeth) from a neighbour-gap measurement made with blender/checks.py, so every contact ends
0.00-0.10 mm apart without overlap.  Tooth poses (manifest) are never touched.
  python blender/solve_contacts.py <checks.json>
Loop: build.py -> checks.py -> solve_contacts.py until in range (2-3 rounds)."""
import json, os, sys
import numpy as np
from scipy.optimize import minimize
HERE = os.path.dirname(os.path.abspath(__file__)); D = os.path.dirname(HERE)
chk = json.load(open(sys.argv[1]))['pairs']
man = json.load(open(os.path.join(D, 'scene_manifest.json')))
cp = os.path.join(HERE, 'contact_scale.json')
cs = json.load(open(cp)) if os.path.exists(cp) else {}
md = {p['fdi']: p['dims']['md'] for p in man['parts'] if p['kind'] == 'tooth'}
LO, HI, MID = 0.015, 0.075, 0.045
for arch, qs, mid in (('upper', (1, 2), '11-21'), ('lower', (4, 3), '31-41')):
    g = np.array([chk[mid]] + [0.5 * (chk['%d%d-%d%d' % (qs[0], k, qs[0], k + 1)] + chk['%d%d-%d%d' % (qs[1], k, qs[1], k + 1)]) for k in range(1, 8)])
    # x = [em1..em8, ed1..ed8]; row 0 midline: 2*em1 ; row j (tooth j <-> j+1): ed_j + em_(j+1)
    A = np.zeros((8, 16)); A[0, 0] = 2.0
    for j in range(1, 8): A[j, 8 + j - 1] = 1.0; A[j, j] = 1.0
    m = np.array([md[qs[0] * 10 + k] for k in range(1, 9)])
    lim = 0.04 * m
    bounds = [(-l, l) for l in lim] * 2
    cons = [{'type': 'ineq', 'fun': lambda x, i=i: (g[i] - A[i] @ x) - LO} for i in range(8)] + \
           [{'type': 'ineq', 'fun': lambda x, i=i: HI - (g[i] - A[i] @ x)} for i in range(8)]
    def obj(x):
        em, ed = x[:8], x[8:]
        return (np.sum(((em + ed) / m) ** 2) + 3.0 * np.sum(((em - ed) / m) ** 2) + 400.0 * np.sum((g - A @ x - MID) ** 2))
    r = minimize(obj, np.zeros(16), constraints=cons, bounds=bounds, method='SLSQP')
    x = r.x
    print(arch, 'gaps now', np.round(g, 2), '-> predicted', np.round(g - A @ x, 2), 'ok' if r.success else 'NOT CONVERGED')
    print('   em', np.round(x[:8], 3), 'ed', np.round(x[8:], 3))
    for q in qs:
        for k in range(1, 9):
            cur = cs.get(str(q * 10 + k), {'em': 0.0, 'ed': 0.0})
            cs[str(q * 10 + k)] = {'em': round(cur['em'] + float(x[k - 1]), 4), 'ed': round(cur['ed'] + float(x[8 + k - 1]), 4)}
json.dump(cs, open(cp, 'w'), indent=0, sort_keys=True)
print('written', cp)
