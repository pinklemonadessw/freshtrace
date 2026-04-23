import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';

const Map<String, String> _categoryTagMapping = {
  'ground-beef':       'meat_beef_ground',
  'ground-meat':       'meat_beef_ground',
  'minced-meat':       'meat_beef_ground',
  'ice-cream':         'frozen_food',
  'ice-creams':        'frozen_food',
  'cold-cuts':         'meat_deli',
  'orange-juice':      'beverages',
  'apple-juice':       'beverages',
  'frozen-foods':      'frozen_food',
  'frozen':            'frozen_food',
  'beef':              'meat_beef_steak',
  'veal':              'meat_beef_steak',
  'steak':             'meat_beef_steak',
  'roast':             'meat_beef_steak',
  'pork':              'meat_pork',
  'ham':               'meat_pork',
  'bacon':             'meat_pork',
  'chicken':           'meat_poultry',
  'poultry':           'meat_poultry',
  'turkey':            'meat_poultry',
  'deli':              'meat_deli',
  'salami':            'meat_deli',
  'sausage':           'meat_deli',
  'salmon':            'meat_fish',
  'tuna':              'meat_fish',
  'fish':              'meat_fish',
  'shrimp':            'meat_seafood',
  'seafood':           'meat_seafood',
  'cream':             'dairy_milk',
  'milk':              'dairy_milk',
  'cheese':            'dairy_cheese',
  'yogurt':            'dairy_yogurt',
  'yoghurt':           'dairy_yogurt',
  'egg':               'eggs',
  'eggs':              'eggs',
  'tortilla':          'bread',
  'bakery':            'bread',
  'bread':             'bread',
  'bun':               'bread',
  'lettuce':           'produce_greens',
  'spinach':           'produce_greens',
  'kale':              'produce_greens',
  'salad':             'produce_greens',
  'berries':           'produce_fruits',
  'berry':             'produce_fruits',
  'apple':             'produce_fruits',
  'banana':            'produce_fruits',
  'citrus':            'produce_fruits',
  'orange':            'produce_fruits',
  'fruit':             'produce_fruits',
  'watermelon':        'produce_fruits',
  'broccoli':          'produce_vegetables',
  'pepper':            'produce_vegetables',
  'tomato':            'produce_vegetables',
  'onion':             'produce_vegetables',
  'vegetable':         'produce_vegetables',
  'potato':            'produce_root',
  'carrot':            'produce_root',
  'beet':              'produce_root',
  'turnip':            'produce_root',
  'canned':            'canned_goods',
  'preserve':          'canned_goods',
  'pasta':             'dry_goods',
  'rice':              'dry_goods',
  'cereal':            'dry_goods',
  'grain':             'dry_goods',
  'flour':             'dry_goods',
  'chip':              'dry_goods',
  'chips':             'dry_goods',
  'cracker':           'dry_goods',
  'snack':             'dry_goods',
  'ketchup':           'condiments',
  'mustard':           'condiments',
  'mayonnaise':        'condiments',
  'dressing':          'condiments',
  'condiment':         'condiments',
  'sauce':             'condiments',
  'soda':              'beverages',
  'juice':             'beverages',
  'tea':               'beverages',
  'coffee':            'beverages',
  'drink':             'beverages',
  'beverage':          'beverages',
  'water':             'beverages',
};

final List<MapEntry<String, String>> _sortedTagEntries = () {
  final entries = _categoryTagMapping.entries.toList();
  entries.sort((a, b) => b.key.length.compareTo(a.key.length));
  return entries;
}();

String? _detectCategory(List<String> tags) {
  for (final tag in tags) {
    final normalized = tag.replaceFirst(RegExp(r'^en:'), '').toLowerCase();
    final segments = normalized.split('-').toSet();
    for (final entry in _sortedTagEntries) {
      final keyParts = entry.key.split('-');
      if (keyParts.every((part) => segments.contains(part))) {
        return entry.value;
      }
    }
  }
  return null;
}

class OpenFoodFactsService {
  static const String _baseUrl =
      'https://world.openfoodfacts.org/api/v2/product';

  static const Map<String, String> _headers = {
    'User-Agent': 'GroceryManager/0.1.0 (prototype)',
  };

  static Future<Product?> fetchProduct(String barcode) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/$barcode.json?fields=product_name,brands,image_front_url,categories_tags',
      );
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['status'] != 1) return null;

      return Product.fromOpenFoodFacts(
        barcode,
        json,
        detectCategory: _detectCategory,
      );
    } catch (e) {
      return null;
    }
  }
}
