import 'package:doctor_management_app/features/homeopathy/data/materia_medica_data.dart';

/// A remedy's full name and its standard abbreviation.
class RemedyName {
  const RemedyName(this.name, this.abbr);
  final String name;
  final String abbr;
}

/// Commonly used remedies that have no Materia medica entry. Everything in
/// [kMateriaMedica] is added to this by [homeopathyRemedies], so this is
/// the one place remedy names live.
const _extraRemedies = <RemedyName>[
  RemedyName('Abrotanum', 'Abrot.'),
  RemedyName('Absinthium', 'Absin.'),
  RemedyName('Aesculus hippocastanum', 'Aesc.'),
  RemedyName('Aethusa cynapium', 'Aeth.'),
  RemedyName('Agaricus muscarius', 'Agar.'),
  RemedyName('Agnus castus', 'Agn.'),
  RemedyName('Ailanthus glandulosa', 'Ail.'),
  RemedyName('Alfalfa', 'Alf.'),
  RemedyName('Aloe socotrina', 'Aloe'),
  RemedyName('Alumina', 'Alum.'),
  RemedyName('Ambra grisea', 'Ambr.'),
  RemedyName('Ammonium carbonicum', 'Am-c.'),
  RemedyName('Ammonium muriaticum', 'Am-m.'),
  RemedyName('Anacardium orientale', 'Anac.'),
  RemedyName('Angustura vera', 'Ang.'),
  RemedyName('Apocynum cannabinum', 'Apoc.'),
  RemedyName('Argentum metallicum', 'Arg-met.'),
  RemedyName('Arsenicum iodatum', 'Ars-i.'),
  RemedyName('Arum triphyllum', 'Arum-t.'),
  RemedyName('Asafoetida', 'Asaf.'),
  RemedyName('Asarum europaeum', 'Asar.'),
  RemedyName('Aurum muriaticum natronatum', 'Aur-m-n.'),
  RemedyName('Avena sativa', 'Aven.'),
  RemedyName('Badiaga', 'Bad.'),
  RemedyName('Baryta muriatica', 'Bar-m.'),
  RemedyName('Benzoicum acidum', 'Benz-ac.'),
  RemedyName('Berberis vulgaris', 'Berb.'),
  RemedyName('Bismuthum', 'Bism.'),
  RemedyName('Borax', 'Bor.'),
  RemedyName('Bovista', 'Bov.'),
  RemedyName('Bromium', 'Brom.'),
  RemedyName('Bufo rana', 'Bufo'),
  RemedyName('Cadmium sulphuratum', 'Cadm-s.'),
  RemedyName('Caladium seguinum', 'Calad.'),
  RemedyName('Calcarea arsenicosa', 'Calc-ar.'),
  RemedyName('Calcarea iodata', 'Calc-i.'),
  RemedyName('Calcarea silicata', 'Calc-sil.'),
  RemedyName('Calcarea sulphurica', 'Calc-s.'),
  RemedyName('Camphora', 'Camph.'),
  RemedyName('Cannabis indica', 'Cann-i.'),
  RemedyName('Cannabis sativa', 'Cann-s.'),
  RemedyName('Capsicum annuum', 'Caps.'),
  RemedyName('Carbo animalis', 'Carb-an.'),
  RemedyName('Carduus marianus', 'Card-m.'),
  RemedyName('Caulophyllum thalictroides', 'Caul.'),
  RemedyName('Ceanothus americanus', 'Cean.'),
  RemedyName('Cedron', 'Cedr.'),
  RemedyName('Cenchris contortrix', 'Cench.'),
  RemedyName('Chininum arsenicosum', 'Chin-ar.'),
  RemedyName('Chininum sulphuricum', 'Chin-s.'),
  RemedyName('Cicuta virosa', 'Cic.'),
  RemedyName('Cina', 'Cina'),
  RemedyName('Cinnabaris', 'Cinnb.'),
  RemedyName('Clematis erecta', 'Clem.'),
  RemedyName('Cobaltum', 'Cob.'),
  RemedyName('Coca', 'Coca'),
  RemedyName('Coccus cacti', 'Cocc-c.'),
  RemedyName('Colchicum autumnale', 'Colch.'),
  RemedyName('Collinsonia canadensis', 'Coll.'),
  RemedyName('Corallium rubrum', 'Cor-r.'),
  RemedyName('Crataegus oxyacantha', 'Crat.'),
  RemedyName('Crocus sativus', 'Croc.'),
  RemedyName('Croton tiglium', 'Crot-t.'),
  RemedyName('Cyclamen europaeum', 'Cycl.'),
  RemedyName('Digitalis purpurea', 'Dig.'),
  RemedyName('Diphtherinum', 'Diph.'),
  RemedyName('Dioscorea villosa', 'Dios.'),
  RemedyName('Elaps corallinus', 'Elaps'),
  RemedyName('Equisetum hyemale', 'Equis.'),
  RemedyName('Eupatorium purpureum', 'Eup-pur.'),
  RemedyName('Euphorbium', 'Euphorb.'),
  RemedyName('Fagopyrum esculentum', 'Fago.'),
  RemedyName('Ferrum arsenicosum', 'Ferr-ar.'),
  RemedyName('Ferrum picricum', 'Ferr-pic.'),
  RemedyName('Fluoricum acidum', 'Fl-ac.'),
  RemedyName('Formica rufa', 'Form.'),
  RemedyName('Gambogia', 'Gamb.'),
  RemedyName('Gaultheria procumbens', 'Gaul.'),
  RemedyName('Gnaphalium polycephalum', 'Gnaph.'),
  RemedyName('Gratiola officinalis', 'Grat.'),
  RemedyName('Guaiacum', 'Guai.'),
  RemedyName('Gymnema sylvestre', 'Gymn.'),
  RemedyName('Helleborus niger', 'Hell.'),
  RemedyName('Helonias dioica', 'Helon.'),
  RemedyName('Hydrastis canadensis', 'Hydr.'),
  RemedyName('Hydrocotyle asiatica', 'Hydrc.'),
  RemedyName('Hyoscyamus niger', 'Hyos.'),
  RemedyName('Iberis amara', 'Iber.'),
  RemedyName('Iodum', 'Iod.'),
  RemedyName('Iris versicolor', 'Iris'),
  RemedyName('Jaborandi', 'Jab.'),
  RemedyName('Justicia adhatoda', 'Just.'),
  RemedyName('Kali arsenicosum', 'Kali-ar.'),
  RemedyName('Kali bromatum', 'Kali-br.'),
  RemedyName('Kali iodatum', 'Kali-i.'),
  RemedyName('Kali muriaticum', 'Kali-m.'),
  RemedyName('Kali nitricum', 'Kali-n.'),
  RemedyName('Kali sulphuricum', 'Kali-s.'),
  RemedyName('Kalmia latifolia', 'Kalm.'),
  RemedyName('Kreosotum', 'Kreos.'),
  RemedyName('Lac defloratum', 'Lac-d.'),
  RemedyName('Lac felinum', 'Lac-f.'),
  RemedyName('Lachnanthes tinctoria', 'Lachn.'),
  RemedyName('Lapis albus', 'Lap-a.'),
  RemedyName('Latrodectus mactans', 'Lat-m.'),
  RemedyName('Lilium tigrinum', 'Lil-t.'),
  RemedyName('Lobelia inflata', 'Lob.'),
  RemedyName('Lycopus virginicus', 'Lycps.'),
  RemedyName('Magnesia carbonica', 'Mag-c.'),
  RemedyName('Magnesia muriatica', 'Mag-m.'),
  RemedyName('Magnesia sulphurica', 'Mag-s.'),
  RemedyName('Manganum aceticum', 'Mang.'),
  RemedyName('Medusa', 'Medus.'),
  RemedyName('Melilotus officinalis', 'Meli.'),
  RemedyName('Menyanthes trifoliata', 'Meny.'),
  RemedyName('Mercurius corrosivus', 'Merc-c.'),
  RemedyName('Mercurius cyanatus', 'Merc-cy.'),
  RemedyName('Mercurius iodatus flavus', 'Merc-i-f.'),
  RemedyName('Mercurius iodatus ruber', 'Merc-i-r.'),
  RemedyName('Mezereum', 'Mez.'),
  RemedyName('Millefolium', 'Mill.'),
  RemedyName('Moschus', 'Mosch.'),
  RemedyName('Murex purpurea', 'Murx.'),
  RemedyName('Muriaticum acidum', 'Mur-ac.'),
  RemedyName('Mygale lasiodora', 'Mygal.'),
  RemedyName('Myrica cerifera', 'Myric.'),
  RemedyName('Naja tripudians', 'Naja'),
  RemedyName('Natrum arsenicosum', 'Nat-ar.'),
  RemedyName('Natrum carbonicum', 'Nat-c.'),
  RemedyName('Natrum phosphoricum', 'Nat-p.'),
  RemedyName('Niccolum', 'Nicc.'),
  RemedyName('Nux moschata', 'Nux-m.'),
  RemedyName('Ocimum canum', 'Ocim.'),
  RemedyName('Oleander', 'Olnd.'),
  RemedyName('Oleum jecoris aselli', 'Ol-j.'),
  RemedyName('Onosmodium', 'Onos.'),
  RemedyName('Origanum majorana', 'Orig.'),
  RemedyName('Oxalicum acidum', 'Ox-ac.'),
  RemedyName('Paeonia officinalis', 'Paeon.'),
  RemedyName('Palladium', 'Pall.'),
  RemedyName('Paris quadrifolia', 'Par.'),
  RemedyName('Petroleum', 'Petr.'),
  RemedyName('Petroselinum', 'Petros.'),
  RemedyName('Physostigma venenosum', 'Phys.'),
  RemedyName('Picricum acidum', 'Pic-ac.'),
  RemedyName('Plantago major', 'Plan.'),
  RemedyName('Platinum metallicum', 'Plat.'),
  RemedyName('Plumbum metallicum', 'Plb.'),
  RemedyName('Populus tremuloides', 'Pop.'),
  RemedyName('Prunus spinosa', 'Prun.'),
  RemedyName('Ptelea trifoliata', 'Ptel.'),
  RemedyName('Radium bromatum', 'Rad-br.'),
  RemedyName('Ranunculus bulbosus', 'Ran-b.'),
  RemedyName('Raphanus sativus', 'Raph.'),
  RemedyName('Ratanhia', 'Rat.'),
  RemedyName('Rheum officinale', 'Rheum'),
  RemedyName('Rhododendron chrysanthum', 'Rhod.'),
  RemedyName('Rhus venenata', 'Rhus-v.'),
  RemedyName('Robinia pseudacacia', 'Rob.'),
  RemedyName('Rumex crispus', 'Rumx.'),
  RemedyName('Sabadilla', 'Sabad.'),
  RemedyName('Sabina', 'Sabin.'),
  RemedyName('Salicylicum acidum', 'Sal-ac.'),
  RemedyName('Sambucus nigra', 'Samb.'),
  RemedyName('Sarsaparilla', 'Sars.'),
  RemedyName('Scutellaria lateriflora', 'Scut.'),
  RemedyName('Secale cornutum', 'Sec.'),
  RemedyName('Selenium metallicum', 'Sel.'),
  RemedyName('Senecio aureus', 'Senec.'),
  RemedyName('Senega', 'Seneg.'),
  RemedyName('Serum anguillae', 'Ser-ang.'),
  RemedyName('Solidago virgaurea', 'Sol.'),
  RemedyName('Stannum metallicum', 'Stann.'),
  RemedyName('Sticta pulmonaria', 'Stict.'),
  RemedyName('Strophanthus hispidus', 'Stroph.'),
  RemedyName('Strychninum', 'Stry.'),
  RemedyName('Sulphuricum acidum', 'Sul-ac.'),
  RemedyName('Sulphur iodatum', 'Sul-i.'),
  RemedyName('Tabacum', 'Tab.'),
  RemedyName('Tarentula cubensis', 'Tarent-c.'),
  RemedyName('Tarentula hispanica', 'Tarent.'),
  RemedyName('Tellurium metallicum', 'Tell.'),
  RemedyName('Terebinthina', 'Ter.'),
  RemedyName('Teucrium marum verum', 'Teucr.'),
  RemedyName('Theridion curassavicum', 'Ther.'),
  RemedyName('Thlaspi bursa-pastoris', 'Thlas.'),
  RemedyName('Thyroidinum', 'Thyr.'),
  RemedyName('Trillium pendulum', 'Tril.'),
  RemedyName('Urtica urens', 'Urt-u.'),
  RemedyName('Ustilago maydis', 'Ust.'),
  RemedyName('Valeriana officinalis', 'Valer.'),
  RemedyName('Variolinum', 'Vario.'),
  RemedyName('Veratrum viride', 'Verat-v.'),
  RemedyName('Verbascum thapsus', 'Verb.'),
  RemedyName('Viburnum opulus', 'Vib.'),
  RemedyName('Vinca minor', 'Vinc.'),
  RemedyName('Viola tricolor', 'Viol-t.'),
  RemedyName('Vipera berus', 'Vip.'),
  RemedyName('Zincum metallicum', 'Zinc.'),
  RemedyName('Zincum phosphoricum', 'Zinc-p.'),
  RemedyName('Zingiber officinale', 'Zing.'),
  RemedyName('Placebo (Sac lac)', 'Sac lac'),
];

List<RemedyName>? _cache;

/// Every remedy name: all Materia medica entries plus the extras, sorted
/// by name, with no repeats.
List<RemedyName> get homeopathyRemedies {
  final cached = _cache;
  if (cached != null) return cached;
  final seen = <String>{};
  final out = <RemedyName>[];
  void add(String name, String abbr) {
    if (seen.add(name.toLowerCase())) out.add(RemedyName(name, abbr));
  }

  for (final e in kMateriaMedica) {
    add(e.name, e.abbr);
  }
  for (final r in _extraRemedies) {
    add(r.name, r.abbr);
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return _cache = out;
}

/// Remedies matching 2+ typed letters in the name or abbreviation; names
/// that start with the text come first.
List<RemedyName> searchRemedies(String text, {int limit = 8}) {
  final q = text.trim().toLowerCase();
  if (q.length < 2) return const [];
  final qn = q.replaceAll('.', '');
  final starts = <RemedyName>[];
  final contains = <RemedyName>[];
  for (final r in homeopathyRemedies) {
    final n = r.name.toLowerCase();
    final a = r.abbr.toLowerCase().replaceAll('.', '');
    if (n.startsWith(q) || a.startsWith(qn)) {
      starts.add(r);
    } else if (n.contains(q) || a.contains(qn)) {
      contains.add(r);
    }
  }
  return [...starts, ...contains].take(limit).toList();
}
