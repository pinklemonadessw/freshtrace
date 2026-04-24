import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/firestore_service.dart';
import '../data/shelf_lives.dart';
import 'package:intl/intl.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final String? documentId;
  final bool canEdit;

  /// True when the scanner fell all the way through to manual entry
  /// (i.e. the barcode wasn't in either the Firestore products cache or
  /// OpenFoodFacts). In this mode we show a banner, autofocus the name
  /// field, and require a non-empty name before saving.
  final bool isManualEntry;

  const ProductDetailScreen({
    super.key,
    required this.product,
    this.documentId,
    this.canEdit = true,
    this.isManualEntry = false,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late TextEditingController _nameController;
  late TextEditingController _quantityController;
  late int _quantity;
  bool _isSaving = false;
  late final DateTime _addedAt;
  String? _selectedCategory;
  int? _shelfLifeDays;
  DateTime? _expiresAt;
  bool _isManualDate = false;
  bool _isHouseholdItem = false;

  @override
  void initState() {
    super.initState();
    _quantity = widget.product.quantity;
    _nameController = TextEditingController(text: widget.product.name);
    _quantityController = TextEditingController(text: _quantity.toString());
    _addedAt = DateTime.now();
    _isHouseholdItem = widget.product.isHouseholdItem;

    if (widget.product.category != null &&
        shelfLives.containsKey(widget.product.category)) {
      _selectedCategory = widget.product.category;
      _shelfLifeDays = shelfLives[_selectedCategory]!['days'] as int;
      _expiresAt = widget.product.expiresAt ??
          DateTime.now().add(Duration(days: _shelfLifeDays!));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _incrementQuantity() {
    setState(() {
      _quantity++;
      _quantityController.text = _quantity.toString();
    });
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() {
        _quantity--;
        _quantityController.text = _quantity.toString();
      });
    }
  }

  void _onQuantityFieldChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed > 0) {
      setState(() => _quantity = parsed);
    } else {
      // Reset the field to the last valid quantity
      _quantityController.text = _quantity.toString();
      _quantityController.selection = TextSelection.fromPosition(
        TextPosition(offset: _quantityController.text.length),
      );
    }
  }

  void _onCategoryChanged(String? value) {
    if (value == null) return;
    final days = shelfLives[value]?['days'] as int?;
    setState(() {
      _selectedCategory = value;
      _shelfLifeDays = days;
      _expiresAt = days != null
          ? DateTime.now().add(Duration(days: days))
          : null;
      _isManualDate = false;
    });
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      _isManualDate = true;
      _expiresAt = picked;
      _shelfLifeDays = picked.difference(DateTime.now()).inDays;
    });
  }

  Future<void> _addToKitchen() async {
    if (widget.isManualEntry &&
        _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a product name')),
      );
      return;
    }
    if (_selectedCategory == null && widget.documentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a food category')),
      );
      return;
    }

    setState(() => _isSaving = true);

    widget.product.name = _nameController.text.trim().isEmpty
        ? widget.product.name
        : _nameController.text.trim();
    widget.product.quantity = _quantity;
    widget.product.category = _selectedCategory;
    widget.product.shelfLifeDays = _shelfLifeDays;
    widget.product.expiresAt = _expiresAt;
    widget.product.isHouseholdItem = _isHouseholdItem;

    try {
      if (widget.documentId != null) {
        await FirestoreService.updateItem(widget.documentId!, widget.product);
      } else {
        await FirestoreService.addItem(widget.product);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.documentId != null
              ? 'Item updated!'
              : 'Item added to kitchen!'),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save item: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
          tooltip: 'Cancel',
        ),
        title: const Text('Product Details'),
        actions: [
        if (widget.canEdit)
          TextButton.icon(
            onPressed: _isSaving ? null : _addToKitchen,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: Text(widget.documentId != null ? 'Save Changes' : 'Add to Kitchen'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isManualEntry) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.edit_note,
                      color: Theme.of(context)
                          .colorScheme
                          .onSecondaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.barcode.isEmpty
                                ? 'Manual entry'
                                : 'New barcode',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.barcode.isEmpty
                                ? 'Adding an item without a barcode. Fill '
                                    'in the details below to save it to '
                                    'your kitchen.'
                                : 'Barcode ${product.barcode} isn\'t in our '
                                    'catalog yet. Fill in the details '
                                    'below — your entry will help the next '
                                    'person who scans it.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Product image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: product.imageUrl.isNotEmpty
                  ? Image.network(
                      product.imageUrl,
                      height: 250,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 250,
                          color: Colors.grey[200],
                          child:
                              const Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 250,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image,
                            size: 64, color: Colors.grey),
                      ),
                    )
                  : Container(
                      height: 250,
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.image_not_supported,
                            size: 64, color: Colors.grey),
                      ),
                    ),
            ),

            const SizedBox(height: 20),

            // Product name & brand 
            Text(
              product.name.isEmpty ? 'New Product' : product.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontStyle: product.name.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                    color: product.name.isEmpty
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5)
                        : null,
                  ),
            ),
            if (product.brand.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                product.brand,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],

            const SizedBox(height: 24),

            // Quantity
            Text(
              'Quantity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filled(
                  onPressed: widget.canEdit ? _decrementQuantity : null,
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: _onQuantityFieldChanged,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: widget.canEdit ? _incrementQuantity : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),

            const SizedBox(height: 24),


            Text(
              widget.isManualEntry
                  ? 'Product Name *'
                  : 'Edit Name (if incorrect)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              enabled: widget.canEdit,
              autofocus: widget.isManualEntry,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: widget.isManualEntry
                    ? 'e.g. Chocolate Chip Cookies'
                    : 'Product name',
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'Category',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              items: shelfLives.entries
                  .map((entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value['label'] as String),
                      ))
                  .toList(),
              onChanged: _onCategoryChanged,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Select a category',
              ),
            ),
            if (_shelfLifeDays != null && _expiresAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Shelf life: $_shelfLifeDays days · '
                'Est. expiry: ${DateFormat.yMMMd().format(_expiresAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.canEdit ? _pickExpiryDate : null,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                _isManualDate && _expiresAt != null
                    ? 'Best-by: ${DateFormat.yMMMd().format(_expiresAt!)} (tap to change)'
                    : 'Manually Set Expiry Date',
              
              ),
            ),
            if (_isManualDate) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: widget.canEdit ? () {
                  if (!context.mounted) return;
                  if (_selectedCategory == null) return;
                  final days = shelfLives[_selectedCategory]?['days'] as int?;
                  if (widget.canEdit) {
                    setState(() {
                      _isManualDate = false;
                      _shelfLifeDays = days;
                      _expiresAt = days != null
                          ? DateTime.now().add(Duration(days: days))
                          : null;
                    });
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a category first')),
                    );
                  }
                  } : null,
                child: widget.canEdit ? Text(
                  'Reset to category default',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ) : const SizedBox.shrink(),
                ),
              ],

            const SizedBox(height: 24),

            // Manual name fallback
            

            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Household Item'),
              subtitle: const Text('Anyone in the household can use this item'),
              value: _isHouseholdItem,
              onChanged: widget.canEdit ? (val) => setState(() => _isHouseholdItem = val) : null,
              secondary: const Icon(Icons.home),
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Colors.grey[300],
              inactiveThumbColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),

            const SizedBox(height: 16),

            // Barcode info
            if (product.barcode.isNotEmpty) ...[
              Text(
                'Barcode: ${product.barcode}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Added at: ${DateFormat.yMMMd().add_jm().format(_addedAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            if (widget.product.addedByName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Added by: ${widget.product.addedByName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
