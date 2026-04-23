import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/product.dart';
import '../services/firestore_service.dart';
import '../services/openfoodfacts_service.dart';
import 'product_detail_screen.dart';

class ScannerScreen extends StatefulWidget {
  final VoidCallback? onProductAdded;

  const ScannerScreen({super.key, this.onProductAdded});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    // Prevent duplicate requests
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    setState(() => _isProcessing = true);

    // Three-tier lookup:
    //   1. Firestore products/{barcode} — user-contributed catalog.
    //   2. OpenFoodFacts — public seed data.
    //   3. Manual entry — let the user fill it in; their save repopulates
    //      the Firestore cache for the next person who scans this barcode.
    Product? product = await FirestoreService.fetchProductFromCache(barcode);
    product ??= await OpenFoodFactsService.fetchProduct(barcode);

    final isManualEntry = product == null;
    product ??= Product(barcode: barcode, name: '');

    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: product!,
          isManualEntry: isManualEntry,
        ),
      ),
    );

    if (result == true && mounted) {
      widget.onProductAdded?.call();
      return;
    }

    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onBarcodeDetected,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Looking up product…',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
