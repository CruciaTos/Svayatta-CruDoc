const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Load service account key
const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id
});

// REPLACE THIS with your User ID from Firebase
const uid = 'JWFRqMhpqacAH3hYDxnmFj4lwRv2';

// Set custom claims
admin.auth().setCustomUserClaims(uid, {
  role: 'superAdmin',
  isTwoFAVerified: true
})
.then(() => {
  console.log('✅ Super Admin claims set successfully!');
  console.log(`User ${uid} is now a Super Admin`);
  process.exit(0);
})
.catch(err => {
  console.error('❌ Error setting claims:', err.message);
  process.exit(1);
});