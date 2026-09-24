import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';

/// What a new radiologist login starts with: report templates with
/// normal wording, shortcut phrases and a fee list. All can be edited.
abstract final class RadSeed {
  static RadReportSection _s(String title, [String body = '']) =>
      RadReportSection(title: title, body: body);

  static List<RadTemplate> templates() => [
        RadTemplate(
          id: 'tpl_cbct_full',
          name: 'CBCT — full volume',
          modality: RadModality.cbct,
          builtIn: true,
          technique:
              'CBCT acquired with a large field of view. Axial, coronal and sagittal '
              'reconstructions, a panoramic reformat and cross-sections were reviewed.',
          sections: [
            _s('Dentition', 'Dentition is within normal limits for age. No periapical pathology is seen.'),
            _s('Maxilla and mandible',
                'Maxilla and mandible show normal trabecular pattern and intact cortices. '
                    'No lytic or sclerotic lesion is seen.'),
            _s('Maxillary sinuses',
                'Both maxillary sinuses are well pneumatised and clear. Sinus floors are intact. '
                    'Ostiomeatal complexes are patent.'),
            _s('Nasal cavity and nasopharynx',
                'Nasal septum is midline. Turbinates are normal. Nasopharynx is clear.'),
            _s('Temporomandibular joints',
                'Condylar heads are normal in shape and position with well-defined cortical '
                    'outlines. Joint spaces are preserved bilaterally.'),
            _s('Airway', 'Airway is patent with no significant narrowing.'),
            _s('Soft tissues and incidental findings',
                'No incidental findings of clinical significance.'),
          ],
          impression: 'No significant abnormality detected within the scanned volume.',
        ),
        RadTemplate(
          id: 'tpl_cbct_limited',
          name: 'CBCT — limited field of view',
          modality: RadModality.cbct,
          builtIn: true,
          technique:
              'CBCT acquired with a small field of view limited to the region of interest. '
              'Multiplanar reconstructions and cross-sections were reviewed.',
          sections: [
            _s('Region of interest'),
            _s('Teeth in the field of view'),
            _s('Periapical and periodontal status'),
            _s('Bone', 'Normal trabecular pattern with intact cortices.'),
            _s('Adjacent structures'),
            _s('Incidental findings', 'None within the field of view.'),
          ],
        ),
        RadTemplate(
          id: 'tpl_opg',
          name: 'Panoramic (OPG)',
          modality: RadModality.opg,
          builtIn: true,
          technique: 'Digital panoramic radiograph.',
          sections: [
            _s('Dentition'),
            _s('Periodontal bone levels', 'Alveolar bone levels are within normal limits.'),
            _s('Maxilla and mandible', 'No lytic or sclerotic lesion is seen.'),
            _s('Maxillary sinuses', 'Maxillary sinus floors appear intact.'),
            _s('Condyles', 'Both condyles appear normal in outline.'),
            _s('Other findings'),
          ],
        ),
        RadTemplate(
          id: 'tpl_ceph',
          name: 'Lateral cephalogram',
          modality: RadModality.ceph,
          builtIn: true,
          technique: 'Digital lateral cephalometric radiograph in natural head position.',
          sections: [
            _s('Skeletal pattern'),
            _s('Dental relationships'),
            _s('Soft tissue profile'),
            _s('Airway', 'Pharyngeal airway appears adequate.'),
            _s('Cephalometric values'),
            _s('Other findings', 'Cervical vertebrae and sella turcica appear normal.'),
          ],
        ),
        RadTemplate(
          id: 'tpl_iopa',
          name: 'Periapical (IOPA)',
          modality: RadModality.iopa,
          builtIn: true,
          technique: 'Digital intraoral periapical radiograph.',
          sections: [
            _s('Teeth'),
            _s('Crowns and restorations'),
            _s('Root canals and periapical region', 'Periapical region appears normal.'),
            _s('Periodontal status', 'Lamina dura is intact. Bone levels are normal.'),
          ],
        ),
        RadTemplate(
          id: 'tpl_bitewing',
          name: 'Bitewing',
          modality: RadModality.bitewing,
          builtIn: true,
          technique: 'Digital bitewing radiographs.',
          sections: [
            _s('Interproximal caries', 'No interproximal caries detected.'),
            _s('Restorations'),
            _s('Crestal bone levels', 'Crestal bone levels are within normal limits.'),
          ],
        ),
        RadTemplate(
          id: 'tpl_occlusal',
          name: 'Occlusal',
          modality: RadModality.occlusal,
          builtIn: true,
          technique: 'Digital occlusal radiograph.',
          sections: [
            _s('Findings'),
            _s('Cortical outline', 'Buccal and lingual cortices are intact.'),
          ],
        ),
        RadTemplate(
          id: 'tpl_tmj',
          name: 'TMJ series',
          modality: RadModality.tmj,
          builtIn: true,
          technique:
              'Bilateral TMJ imaging in closed and open mouth positions (corrected '
              'sagittal and coronal views).',
          sections: [
            _s('Right TMJ'),
            _s('Left TMJ'),
            _s('Condylar translation'),
            _s('Joint spaces'),
            _s('Other findings'),
          ],
        ),
        RadTemplate(
          id: 'tpl_implant',
          name: 'Implant site assessment',
          modality: RadModality.cbct,
          builtIn: true,
          technique:
              'CBCT with cross-sections perpendicular to the arch at 1 mm intervals through '
              'the proposed site.',
          sections: [
            _s('Proposed site'),
            _s('Available bone height'),
            _s('Available bone width'),
            _s('Bone density and cortex'),
            _s('Vital structures',
                'Inferior alveolar canal, mental foramen, sinus floor and incisive canal '
                    'are identified and their distances recorded.'),
            _s('Suggested implant'),
          ],
        ),
        RadTemplate(
          id: 'tpl_sinus',
          name: 'Paranasal sinus assessment',
          modality: RadModality.cbct,
          builtIn: true,
          technique: 'CBCT covering the paranasal sinuses.',
          sections: [
            _s('Right maxillary sinus'),
            _s('Left maxillary sinus'),
            _s('Ostiomeatal complexes'),
            _s('Septa and floor'),
            _s('Relationship to posterior teeth'),
          ],
        ),
        RadTemplate(
          id: 'tpl_airway',
          name: 'Airway analysis',
          modality: RadModality.cbct,
          builtIn: true,
          technique: 'CBCT with segmentation of the pharyngeal airway.',
          sections: [
            _s('Nasopharynx'),
            _s('Oropharynx'),
            _s('Hypopharynx'),
            _s('Minimum cross-sectional area'),
            _s('Total airway volume'),
            _s('Adenoids and tonsils'),
          ],
        ),
        RadTemplate(
          id: 'tpl_pathology',
          name: 'Pathology / lesion',
          modality: RadModality.cbct,
          builtIn: true,
          technique: 'CBCT with multiplanar reconstructions through the lesion.',
          sections: [
            _s('Location and extent'),
            _s('Periphery and shape'),
            _s('Internal structure'),
            _s('Effects on surrounding structures'),
            _s('Differential diagnosis'),
          ],
        ),
      ];

  static List<RadPhrase> phrases() {
    var n = 0;
    RadPhrase ph(String trigger, String text) =>
        RadPhrase(id: 'phr_seed_${n++}', trigger: trigger, text: text);
    return [
      ph('.nad', 'No abnormality detected.'),
      ph('.sinus',
          'Both maxillary sinuses are well pneumatised and clear. Sinus floors are intact.'),
      ph('.sinusmuc',
          'Mild mucosal thickening along the floor of the ___ maxillary sinus, likely '
              'inflammatory. No air-fluid level.'),
      ph('.tmj',
          'Condylar heads are normal in shape and position with well-defined cortical '
              'outlines. Joint spaces are preserved.'),
      ph('.pa',
          'Periapical radiolucency associated with the ___ root of tooth __, measuring about '
              '__ × __ mm, suggestive of periapical pathology.'),
      ph('.bl', 'Generalised horizontal bone loss involving the coronal third of the roots.'),
      ph('.imp',
          'Impacted tooth __ with ___ angulation. The roots are in close relation to the '
              'inferior alveolar canal.'),
      ph('.ian',
          'The inferior alveolar canal is clearly seen. The distance from the proposed site '
              'to the superior border of the canal is __ mm.'),
      ph('.caries',
          'Radiolucency suggestive of caries on the ___ surface of tooth __, approaching '
              'the pulp.'),
      ph('.rct', 'Root canal treated tooth __ with adequate obturation length and density.'),
      ph('.airway', 'Airway is patent with no significant narrowing.'),
      ph('.cyst',
          'Well-defined unilocular radiolucency with a corticated border, measuring about '
              '__ × __ × __ mm.'),
      ph('.mental', 'The mental foramen lies __ mm below the alveolar crest.'),
      ph('.corr', 'Clinical correlation is recommended.'),
      ph('.fu', 'Follow-up imaging in 6 months is suggested to assess healing.'),
      ph('.incid', 'No incidental findings of clinical significance.'),
    ];
  }

  static List<RadFee> fees() => const [
        RadFee(id: 'fee_cbct_full', label: 'CBCT — full volume', modality: RadModality.cbct, amount: 3500),
        RadFee(id: 'fee_cbct_limited', label: 'CBCT — limited field of view', modality: RadModality.cbct, amount: 2000),
        RadFee(id: 'fee_opg', label: 'Panoramic (OPG)', modality: RadModality.opg, amount: 500),
        RadFee(id: 'fee_ceph', label: 'Lateral ceph with tracing', modality: RadModality.ceph, amount: 700),
        RadFee(id: 'fee_iopa', label: 'Periapical (IOPA)', modality: RadModality.iopa, amount: 150),
        RadFee(id: 'fee_bitewing', label: 'Bitewing', modality: RadModality.bitewing, amount: 200),
        RadFee(id: 'fee_occlusal', label: 'Occlusal', modality: RadModality.occlusal, amount: 300),
        RadFee(id: 'fee_tmj', label: 'TMJ series', modality: RadModality.tmj, amount: 2500),
      ];
}
