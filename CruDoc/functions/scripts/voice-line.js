/**
 * Registers or changes an AI receptionist line (`voice_lines/{aiNumber}`)
 * until the app and Super Admin have screens for it.
 *
 * Usage, from functions/ (needs `gcloud auth application-default login` once):
 *
 *   node scripts/voice-line.js --project svayatta-crudoc-dev \
 *     --ai-number +918064261740 --clinic <clinic owner uid> \
 *     --published +919822011111 [--doctors uid1,uid2] [--included-calls 20] [--name "Sharma Dental Clinic"]
 *
 *   node scripts/voice-line.js --project svayatta-crudoc-dev --ai-number +918064261740 --status paused
 *   node scripts/voice-line.js --project svayatta-crudoc-dev --ai-number +918064261740 --show
 *
 * --ai-number   the clinic's Sarvam number; also the `line_id` variable in its Sarvam agent
 * --clinic      the clinic id (the owner's uid in `users`)
 * --published   the doctor's own number that patients call and that forwards to the AI
 * --doctors     who the line books for; defaults to the clinic owner
 *
 * A new line starts as pending_test; the doctor's test call from --published
 * makes it active (or pass --status active).
 */
const admin = require('firebase-admin');

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
const has = (name) => process.argv.includes(`--${name}`);

function digits(raw) {
  if (!raw) return null;
  let d = String(raw).replace(/\D/g, '').replace(/^0+/, '');
  if (d.length === 10) d = `91${d}`;
  return d.length === 12 && d.startsWith('91') ? d : null;
}

async function main() {
  const projectId = arg('project');
  const lineId = digits(arg('ai-number'));
  if (!projectId || !lineId) {
    console.error('Pass --project and --ai-number (an Indian number).');
    process.exit(1);
  }
  admin.initializeApp({projectId});
  const db = admin.firestore();
  const ref = db.collection('voice_lines').doc(lineId);

  if (has('show')) {
    const snap = await ref.get();
    console.log(snap.exists ? {id: snap.id, ...snap.data()} : `No line ${lineId}`);
    return;
  }

  const existing = (await ref.get()).data() || {};
  const clinicId = arg('clinic') || existing.doctorId;
  if (!clinicId) {
    console.error('A new line needs --clinic <clinic owner uid>.');
    process.exit(1);
  }

  const owner = await db.collection('users').doc(clinicId).get();
  if (!owner.exists) {
    console.error(`users/${clinicId} does not exist.`);
    process.exit(1);
  }
  const modules = (owner.data().enabledModules || []).map((m) => String(m).toLowerCase());
  if (!modules.includes('ai_agentic_calling')) {
    console.warn('WARNING: the clinic does not have the ai_agentic_calling module, so the AI ' +
      'will answer every call with the "not available" message. Enable it in Super Admin.');
  }

  const doctorIds = arg('doctors') ? arg('doctors').split(',').map((s) => s.trim()).filter(Boolean) :
    (existing.doctorIds || [clinicId]);
  for (const id of doctorIds) {
    const u = await db.collection('users').doc(id).get();
    if (!u.exists) {
      console.error(`Doctor users/${id} does not exist.`);
      process.exit(1);
    }
    if (id !== clinicId && (u.data().clinicId || id) !== clinicId) {
      console.error(`Doctor ${id} is not in clinic ${clinicId}.`);
      process.exit(1);
    }
  }

  const published = arg('published') ? digits(arg('published')) : existing.publishedNumber;
  if (arg('published') && !published) {
    console.error('--published must be an Indian number.');
    process.exit(1);
  }
  if (published) {
    const clash = await db.collection('voice_lines').where('publishedNumber', '==', published).get();
    const other = clash.docs.find((d) => d.id !== lineId);
    if (other) {
      console.error(`${published} is already the published number of line ${other.id}.`);
      process.exit(1);
    }
  }

  const status = arg('status') || existing.status || 'pending_test';
  if (!['pending_test', 'active', 'paused'].includes(status)) {
    console.error('--status must be pending_test, active or paused.');
    process.exit(1);
  }

  const update = {
    doctorId: clinicId,
    doctorIds,
    publishedNumber: published || null,
    status,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (!existing.createdAt) update.createdAt = admin.firestore.FieldValue.serverTimestamp();
  if (arg('included-calls')) update.includedCalls = Number(arg('included-calls'));
  if (arg('name')) update.clinicName = arg('name');
  if (arg('agent-id')) update.sarvamAgentId = arg('agent-id');

  await ref.set(update, {merge: true});
  console.log(`Saved voice_lines/${lineId}:`, {...existing, ...update, updatedAt: 'now'});
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
