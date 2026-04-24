import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  static String? _activeKitchenId;

  static void setActiveKitchen(String kitchenId) {
    _activeKitchenId = kitchenId;
  }

  static String get kitchenId {
    if (_activeKitchenId == null) throw StateError('Active kitchen not set');
    return _activeKitchenId!;
  }

  static Future<void> renameKitchen(String newName) async {
    await _db.collection('kitchens').doc(kitchenId).update({
      'name': newName,
    });
  }

  static CollectionReference get _inventory =>
      _db.collection('kitchens').doc(kitchenId).collection('inventory');

  static Future<String> _resolveDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Unknown';
    final doc = await _db.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (data != null && data['displayName'] is String) {
      return data['displayName'] as String;
    }
    return user.displayName ?? user.email ?? 'Unknown';
  }

  /// Looks up a previously-seen product in the shared `products/{barcode}`
  /// cache. Returns null if nothing has been written for this barcode yet.
  /// Entries in this cache are contributed by users (via addItem) and by
  /// OpenFoodFacts responses, so preferring this over a fresh OFF lookup
  /// means user corrections survive.
  static Future<Product?> fetchProductFromCache(String barcode) async {
    final doc = await _db.collection('products').doc(barcode).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return Product(
      barcode: barcode,
      name: (data['name'] as String?) ?? '',
      brand: (data['brand'] as String?) ?? '',
      imageUrl: (data['imageUrl'] as String?) ?? '',
      category: data['category'] as String?,
      shelfLifeDays: (data['shelfLifeDays'] as num?)?.toInt(),
    );
  }

  static Future<void> addItem(Product product) async {
    product.addedByName = await _resolveDisplayName();
    // Manual entries have no barcode, so skip the shared products cache
    // write — that cache is keyed by barcode and exists to help other users
    // who scan the same code later.
    final writes = <Future<void>>[
      _inventory.add(product.toInventoryMap()).then((_) {}),
    ];
    if (product.barcode.isNotEmpty) {
      writes.add(_db
          .collection('products')
          .doc(product.barcode)
          .set(product.toProductCacheMap(), SetOptions(merge: true)));
    }
    await Future.wait(writes);
  }

  static Stream<DocumentSnapshot> kitchenStream() {
    return _db.collection('kitchens').doc(kitchenId).snapshots();
  }

  static Stream<QuerySnapshot> membersStream() {
    return _db
        .collection('kitchens')
        .doc(kitchenId)
        .collection('members')
        .orderBy('role')
        .snapshots();
  }

  static Future<void> removeMember(String memberUid) async {
    await Future.wait([
      _db
          .collection('kitchens')
          .doc(kitchenId)
          .collection('members')
          .doc(memberUid)
          .delete(),
      _db.collection('users').doc(memberUid).update({
        'activeKitchenId': null,
      }),
    ]);
  }

  static Stream<QuerySnapshot> inventoryStream() {
    return _inventory.orderBy('expiresAt', descending: false).snapshots();
  }

  static Future<void> removeItem(String documentId) async {
    await _inventory.doc(documentId).delete();
  }

  static Future<void> updateItem(String documentId, Product product) async {
    await _inventory.doc(documentId).update({
      'name': product.name,
      'quantity': product.quantity,
      'imageUrl': product.imageUrl,
      'category': product.category,
      'shelfLifeDays': product.shelfLifeDays,
      'expiresAt': product.expiresAt != null
          ? Timestamp.fromDate(product.expiresAt!)
          : null,
      'isHouseholdItem': product.isHouseholdItem,
    });
  }

  static Future<List<Map<String, dynamic>>> getUserIngredients() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _inventory.get();
    return snap.docs.map((doc) => doc.data()! as Map<String, dynamic>).where((item) =>
      item['addedBy'] == uid || item['isHouseholdItem'] == true).toList();   
  }

  // ------------------------------------------------------------------
  // Admin-only helpers. These take an explicit kitchenId so that admins
  // can inspect other kitchens without changing the caller's own active
  // kitchen. Access is enforced at the Firestore security-rules layer
  // via isAdmin(); these methods intentionally do NO client-side checks.
  // ------------------------------------------------------------------

  static Stream<QuerySnapshot> allKitchensStream() {
    return _db
        .collection('kitchens')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Stream<DocumentSnapshot> kitchenStreamFor(String kitchenId) {
    return _db.collection('kitchens').doc(kitchenId).snapshots();
  }

  static Stream<QuerySnapshot> inventoryStreamFor(String kitchenId) {
    return _db
        .collection('kitchens')
        .doc(kitchenId)
        .collection('inventory')
        .orderBy('expiresAt', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot> membersStreamFor(String kitchenId) {
    return _db
        .collection('kitchens')
        .doc(kitchenId)
        .collection('members')
        .orderBy('role')
        .snapshots();
  }

  static Future<void> adminRemoveItem(
      String kitchenId, String documentId) async {
    await _db
        .collection('kitchens')
        .doc(kitchenId)
        .collection('inventory')
        .doc(documentId)
        .delete();
  }

  static Future<int> memberCountFor(String kitchenId) async {
    final snap = await _db
        .collection('kitchens')
        .doc(kitchenId)
        .collection('members')
        .get();
    return snap.size;
  }

  /// Calls the `adminDeleteKitchen` Cloud Function, which runs with the
  /// Admin SDK and recursively wipes the kitchen doc, its inventory, its
  /// members, and nulls out `activeKitchenId` on any user still pointing
  /// at it. Throws [FirebaseFunctionsException] on failure.
  ///
  /// Returns the number of users whose activeKitchenId was cleared.
  static Future<int> adminDeleteKitchen(String kitchenId) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('adminDeleteKitchen');
    final result = await callable.call<Map<Object?, Object?>>({
      'kitchenId': kitchenId,
    });
    final data = Map<String, dynamic>.from(result.data);
    return (data['clearedUsers'] as num?)?.toInt() ?? 0;
  }
}
