/**
 * Maps an ABDM Health Facility Registry ID (hipId) to a CruDoc clinic.
 * Usage: node scripts/abdm-facility.js <hipId> <clinicId>
 */
const admin = require("firebase-admin");
const {Timestamp} = require("firebase-admin/firestore");

const [hipId, clinicId] = process.argv.slice(2).map((s) => (s || "").trim());
if (!hipId || !clinicId) {
  console.error("Usage: node scripts/abdm-facility.js <hipId> <clinicId>");
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

(async () => {
  const ref = db.collection("abdmFacilities").doc(hipId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      const existingClinicId = snap.data()?.clinicId;
      if (existingClinicId && existingClinicId !== clinicId) {
        throw new Error(`Facility ${hipId} already belongs to another clinic.`);
      }
    }
    tx.set(ref, {
      clinicId,
      approved: true,
      createdAt: Timestamp.now(),
    });
  });
  console.log(`Mapped facility ${hipId} -> ${clinicId}`);
})().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
