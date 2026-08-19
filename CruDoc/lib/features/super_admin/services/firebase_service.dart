import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../config/app_constants.dart';

/// Singleton service for Firebase initialization and core access.
class SuperAdminFirebaseService {
  static final SuperAdminFirebaseService _instance = SuperAdminFirebaseService._internal();
  factory SuperAdminFirebaseService() => _instance;
  SuperAdminFirebaseService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // --------------- Auth ---------------

  FirebaseAuth get auth => _auth;
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --------------- Firestore ---------------

  FirebaseFirestore get firestore => _firestore;

  CollectionReference get usersCollection =>
      _firestore.collection(SuperAdminConstants.collectionUsers);

  CollectionReference get subscriptionsCollection =>
      _firestore.collection(SuperAdminConstants.collectionSubscriptions);

  CollectionReference get featureFlagsCollection =>
      _firestore.collection(SuperAdminConstants.collectionFeatureFlags);

  CollectionReference get plansCollection =>
      _firestore.collection(SuperAdminConstants.collectionPlans);

  CollectionReference get auditLogsCollection =>
      _firestore.collection(SuperAdminConstants.collectionAuditLogs);

  CollectionReference get doctorSettingsCollection =>
      _firestore.collection(SuperAdminConstants.collectionDoctorSettings);

  CollectionReference get analyticsCollection =>
      _firestore.collection(SuperAdminConstants.collectionAnalytics);

  CollectionReference get notificationsCollection =>
      _firestore.collection(SuperAdminConstants.collectionNotifications);

  CollectionReference get supportTicketsCollection =>
      _firestore.collection(SuperAdminConstants.collectionSupportTickets);

  CollectionReference get systemConfigCollection =>
      _firestore.collection(SuperAdminConstants.collectionSystemConfig);

  CollectionReference get apiKeysCollection =>
      _firestore.collection(SuperAdminConstants.collectionApiKeys);

  CollectionReference get apiLogsCollection =>
      _firestore.collection(SuperAdminConstants.collectionApiLogs);

  // --------------- Storage ---------------

  FirebaseStorage get storage => _storage;
  Reference get profilePicturesRef => _storage.ref().child('admin_profiles');

  // --------------- Helpers ---------------

  String? get currentUserId => _auth.currentUser?.uid;
  String? get currentUserEmail => _auth.currentUser?.email;

  /// Get a document reference by collection and ID.
  DocumentReference docRef(String collection, String docId) {
    return _firestore.collection(collection).doc(docId);
  }

  /// Run a Firestore transaction.
  Future<T> runTransaction<T>(Future<T> Function(Transaction transaction) handler) {
    return _firestore.runTransaction(handler);
  }

  /// Get server timestamp sentinel value.
  FieldValue get serverTimestamp => FieldValue.serverTimestamp();

  /// Create a batch writer.
  WriteBatch batch() => _firestore.batch();
}