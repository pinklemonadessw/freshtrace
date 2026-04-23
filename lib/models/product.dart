import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Product {
  final String barcode;
  String name;
  String brand;
  String imageUrl;
  int quantity;
  String? category;
  int? shelfLifeDays;
  DateTime? expiresAt;
  String? addedByName;
  bool isHouseholdItem = false;

  Product({
    required this.barcode,
    required this.name,
    this.brand = '',
    this.imageUrl = '',
    this.quantity = 1,
    this.category,
    this.shelfLifeDays,
    this.expiresAt,
    this.addedByName,
    this.isHouseholdItem = false,
  });

  factory Product.fromOpenFoodFacts(
    String barcode,
    Map<String, dynamic> json, {
    String? Function(List<String> tags)? detectCategory,
  }) {
    final product = json['product'] as Map<String, dynamic>? ?? {};
    final tags = (product['categories_tags'] as List<dynamic>?)
            ?.cast<String>() ??
        [];
    final detectedCategory = detectCategory?.call(tags);
    return Product(
      barcode: barcode,
      name: (product['product_name'] as String?) ?? 'Unknown Product',
      brand: (product['brands'] as String?) ?? '',
      imageUrl: (product['image_front_url'] as String?) ?? '',
      category: detectedCategory,
    );
  }

  Map<String, dynamic> toInventoryMap() {
    final user = FirebaseAuth.instance.currentUser;
    return {
      'barcode': barcode,
      'name': name,
      'imageUrl': imageUrl,
      'quantity': quantity,
      'category': category,
      'shelfLifeDays': shelfLifeDays,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'addedAt': FieldValue.serverTimestamp(),
      'addedBy': user?.uid ?? '',
      'addedByName': addedByName ?? 'Unknown',
      'isHouseholdItem': isHouseholdItem,
    };
  }

  Map<String, dynamic> toProductCacheMap() {
    final user = FirebaseAuth.instance.currentUser;
    return {
      'barcode': barcode,
      'name': name,
      'brand': brand,
      'imageUrl': imageUrl,
      'category': category,
      'shelfLifeDays': shelfLifeDays,
      'fetchedAt': FieldValue.serverTimestamp(),
      'lastEditedBy': user?.uid,
    };
  }
}
