/**
 * Complete Super Admin Setup Script
 * Run this ONCE to create everything needed.
 * 
 * Usage: node setup_super_admin_complete.js
 */

const admin = require('./functions/node_modules/firebase-admin');
const fs = require('fs');
const path = require('path');

// Load service account key
const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error('❌ serviceAccountKey.json not found in the project root!');
  console.error('   Download it from Firebase Console → Project Settings → Service Accounts');
  process.exit(1);
}
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id
});

const auth = admin.auth();
const db = admin.firestore();

// ==========================================
// CONFIGURATION — CHANGE THESE VALUES
// ==========================================
const ADMIN_EMAIL = 'admin@crudoc.com';
const ADMIN_PASSWORD = 'Admin@123';    // Minimum 6 characters
const ADMIN_NAME = 'Super Admin';
// ==========================================

async function setupSuperAdmin() {
  let uid;

  try {
    // STEP 1: Check if user already exists
    console.log('🔍 Checking if admin user exists...');
    let userRecord;
    try {
      userRecord = await auth.getUserByEmail(ADMIN_EMAIL);
      uid = userRecord.uid;
      console.log(`✅ User already exists with UID: ${uid}`);
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        // STEP 1b: Create new user
        console.log('📝 Creating new admin user...');
        userRecord = await auth.createUser({
          email: ADMIN_EMAIL,
          password: ADMIN_PASSWORD,
          displayName: ADMIN_NAME,
        });
        uid = userRecord.uid;
        console.log(`✅ Created user with UID: ${uid}`);
      } else {
        throw e;
      }
    }

    // STEP 2: Set custom claims
    console.log('🔑 Setting custom claims (role + 2FA)...');
    await auth.setCustomUserClaims(uid, {
      role: 'superAdmin',
      isTwoFAVerified: true
    });
    console.log('✅ Custom claims set!');

    // STEP 3: Create/update Firestore document
    console.log('📄 Creating Firestore document in users collection...');
    await db.collection('users').doc(uid).set({
      email: ADMIN_EMAIL,
      name: ADMIN_NAME,
      role: 'superAdmin',
      isTwoFAEnabled: false,
      isTwoFAVerified: true,
      isActive: true,
      failedLoginAttempts: 0,
      profilePictureUrl: '',
      accountCreated: admin.firestore.FieldValue.serverTimestamp(),
      lastLogin: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ Firestore document created!');

    console.log('\n========================================');
    console.log('✅ SETUP COMPLETE!');
    console.log('========================================');
    console.log(`📧 Email:    ${ADMIN_EMAIL}`);
    console.log(`🔑 Password: ${ADMIN_PASSWORD}`);
    console.log(`🆔 UID:      ${uid}`);
    console.log('========================================');
    console.log('\n▶️  Now go to your browser and navigate to:');
    console.log('   http://localhost:63791/#/admin/login');
    console.log('   (replace 63791 with whatever port you see)');
    console.log('\n▶️  Login with the email and password above.');

  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error('Full error:', error);
  }

  process.exit(0);
}

setupSuperAdmin();