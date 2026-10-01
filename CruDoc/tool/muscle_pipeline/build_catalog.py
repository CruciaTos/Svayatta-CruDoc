import json,re
c=json.load(open('catalog_raw.json'))
REG={'Cranial part of muscular system':'Head','Cervical part of muscular system':'Neck','Dorsal part of muscular system':'Back','Thoracic part of muscular system':'Chest','Abdominal part of muscular system':'Abdomen','Pelvic part of muscular system':'Pelvis','Muscular system of upper limb':'Upper limb','Muscular system of lower limb':'Lower limb'}
FIX=[(r'splenius|interspinales|levatores|thoracolumbar','Back'),(r'intercostal|pectoralis|serratus|subclavius|transversus thoracis|diaphragm','Chest'),
     (r'coccyg|pubo|anal sphincter','Pelvis'),(r'palmar|digits of hand','Upper limb'),(r'iliopectineal','Lower limb')]
NOT_ACTION={'Tendon','Superficial','Fascia','Ligament','Cartilage','Articular capsule','Trapezius','Diaphragm'}
out=dict(muscles=[],bones=[])
for r in c:
    if r['kind']=='muscle':
        reg=REG.get(r['path'][0]) if r['path'] else None
        if not reg:
            reg=next((v for k,v in FIX if re.search(k,r['name'],re.I)),'Other')
        sub=r['path'][-1] if r['path'] and r['path'][-1] not in REG else None
        out['muscles'].append(dict(id=r['id'],name=r['name'],side=r['side'],region=reg,group=sub,
            superficial=r['superficial'],actions=[a for a in r['action'] if a not in NOT_ACTION]))
    else:
        out['bones'].append(dict(id=r['id'],name=r['name'],side=r['side']))
json.dump(out,open('catalog.json','w'),separators=(',',':'))
import collections;print(collections.Counter(m['region'] for m in out['muscles']))
