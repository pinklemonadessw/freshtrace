import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

String _generateInviteCode({int length = 6}) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(length, (_) => chars[random.nextInt(chars.length)])
      .join();
}

class HouseholdSetupScreen extends StatefulWidget {
  const HouseholdSetupScreen({super.key});

  @override
  State<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends State<HouseholdSetupScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController(text: 'My Kitchen');
  bool _isLoading = false;

  Future<String> _resolveDisplayName(
      FirebaseFirestore db, User currentUser) async {
    final userDoc = await db.collection('users').doc(currentUser.uid).get();
    final storedName = (userDoc.data()?['displayName'] as String?)?.trim();
    if (storedName != null && storedName.isNotEmpty) {
      return storedName;
    }

    final authName = currentUser.displayName?.trim();
    if (authName != null && authName.isNotEmpty) {
      return authName;
    }

    return currentUser.email ?? 'Unknown';
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a kitchen name')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final db = FirebaseFirestore.instance;
      final currentUser = FirebaseAuth.instance.currentUser!;
      final uid = currentUser.uid;
      final displayName = await _resolveDisplayName(db, currentUser);
      final inviteCode = _generateInviteCode();

      // Sequential writes: security rules validate each step against the
      // previous one (kitchen.createdBy for the owner doc, owner membership
      // for the invite-code lookup doc).
      final kitchenRef = db.collection('kitchens').doc();
      await kitchenRef.set({
        'name': name,
        'inviteCode': inviteCode,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await kitchenRef.collection('members').doc(uid).set({
        'displayName': displayName,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      await db.collection('inviteCodes').doc(inviteCode).set({
        'kitchenId': kitchenRef.id,
      });

      await db.collection('users').doc(uid).set({
        'activeKitchenId': kitchenRef.id,
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create kitchen: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinHousehold() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an invite code')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final db = FirebaseFirestore.instance;
      final currentUser = FirebaseAuth.instance.currentUser!;
      final uid = currentUser.uid;
      final displayName = await _resolveDisplayName(db, currentUser);

      // Look up the kitchen through the inviteCodes collection (get by doc
      // ID only — kitchens themselves are not readable by non-members).
      final codeDoc = await db.collection('inviteCodes').doc(code).get();

      if (!codeDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No kitchen found with that code')),
        );
        setState(() => _isLoading = false);
        return;
      }

      final kitchenId = codeDoc.data()!['kitchenId'] as String;

      // inviteCode is included so security rules can verify it against the
      // kitchen doc before allowing the join.
      await db
          .collection('kitchens')
          .doc(kitchenId)
          .collection('members')
          .doc(uid)
          .set({
        'displayName': displayName,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'inviteCode': code,
      });

      await db.collection('users').doc(uid).set({
        'activeKitchenId': kitchenId,
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join kitchen: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Your Kitchen'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create a new kitchen or join an existing one',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                /// ------ CREATE A KITCHEN SECTION ------ ///
                Text('Create a Kitchen',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Kitchen Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.kitchen),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _createHousehold,
                  icon: const Icon(Icons.add_home),
                  label: const Text('Create Kitchen'),
                ),

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 32),

                // --- Join section ---
                Text('Join a Kitchen',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Invite Code',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _joinHousehold,
                  icon: const Icon(Icons.group_add),
                  label: const Text('Join Kitchen'),
                ),

                if (_isLoading) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
