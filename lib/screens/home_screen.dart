import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product.dart';
import '../services/firestore_service.dart';
import 'admin_console_screen.dart';
import 'product_detail_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isOwner = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkRole();
    _checkAdmin();
  }

  Future<void> _checkRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('kitchens')
        .doc(FirestoreService.kitchenId)
        .collection('members')
        .doc(uid)
        .get();
    if (!mounted) return;
    setState(() {
      _isOwner = (doc.data()?['role'] as String?) == 'owner';
    });
  }

  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Force a token refresh so newly-granted custom claims are picked up
    // without requiring the user to sign out and back in.
    try {
      final token = await user.getIdTokenResult(true);
      if (token.claims?['admin'] == true) {
        if (!mounted) return;
        setState(() => _isAdmin = true);
        return;
      }
    } catch (_) {
      // Ignore; we'll fall back to the Firestore flag below.
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!mounted) return;
    setState(() {
      _isAdmin = doc.data()?['isAdmin'] == true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirestoreService.kitchenStream(),
          builder: (context, snapshot) {
            String subtitle = '';
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              final kitchenName = data?['name'] as String? ?? '';
              final inviteCode = data?['inviteCode'] as String? ?? '';
              if (kitchenName.isNotEmpty || inviteCode.isNotEmpty) {
                subtitle = '$kitchenName · Code: $inviteCode';
              }
            }
            return Column(
              children: [
                const Text('FreshTrace'),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
              ],
            );
          },
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<_HomeMenuAction>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case _HomeMenuAction.kitchenSettings:
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const KitchenSettingsScreen()),
                  );
                  break;
                case _HomeMenuAction.viewMembers:
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ViewMembersScreen()),
                  );
                  break;
                case _HomeMenuAction.adminConsole:
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminConsoleScreen()),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _HomeMenuAction.kitchenSettings,
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Kitchen Settings'),
                  subtitle: Text('Manage your kitchen settings'),
                ),
              ),
              const PopupMenuItem(
                value: _HomeMenuAction.viewMembers,
                child: ListTile(
                  leading: Icon(Icons.people),
                  title: Text('View Members'),
                  subtitle: Text('See who is in your kitchen'),
                ),
              ),
              if (_isAdmin)
                PopupMenuItem(
                  value: _HomeMenuAction.adminConsole,
                  child: ListTile(
                    leading: Icon(
                      Icons.shield_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Admin Console'),
                    subtitle: const Text('Browse all kitchens'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          

          const Divider(height: 1),

          // INVENTORY
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Kitchen Inventory',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),

          // FIRESTORE INVENTORY
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirestoreService.inventoryStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading inventory: ${snapshot.error}'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.kitchen_outlined,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'No items yet — scan something to get started!',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data()! as Map<String, dynamic>;
                    final name = (data['name'] as String?) ?? 'Unknown';
                    final imageUrl = (data['imageUrl'] as String?) ?? '';
                    final quantity = data['quantity'] ?? 1;
                    final category = data['category'] as String?;
                    final shelfLifeDays = data['shelfLifeDays'] as int?;
                    final expiresAtTs = data['expiresAt'] as Timestamp?;
                    final expiresAt = expiresAtTs?.toDate();
                    final daysLeft = expiresAt?.difference(DateTime.now()).inDays;
                    final addedByName =
                        (data['addedByName'] as String?) ?? 'Unknown';
                    final addedBy = data['addedBy'] as String?;
                    final currentUid =
                        FirebaseAuth.instance.currentUser?.uid;
                    final isHousehold = data['isHouseholdItem'] as bool? ?? false;
                    final canModify = _isOwner || addedBy == currentUid || isHousehold;

                    return InkWell(
                      onTap: () {
                        final product = Product(
                          barcode: data['barcode'] as String,
                          name: name,
                          imageUrl: imageUrl,
                          quantity: quantity,
                          category: category,
                          shelfLifeDays: shelfLifeDays,
                          expiresAt: expiresAt,
                          addedByName: addedByName,
                          isHouseholdItem: isHousehold,
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProductDetailScreen(
                              product: product,
                              documentId: docs[index].id,
                              canEdit: canModify,
                            ),
                          ),
                        );
                      },
                    child: Column(
                      children: [
                        Expanded(
                          child: Card(
                      clipBehavior: Clip.antiAlias,
                      elevation: 2,
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: imageUrl.isNotEmpty
                                    ? Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            color: Colors.grey[200],
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) =>
                                            Container(
                                          color: Colors.grey[200],
                                          child: const Icon(Icons.broken_image,
                                              color: Colors.grey),
                                        ),
                                      )
                                    : Container(
                                        color: Colors.grey[200],
                                        child: const Icon(
                                            Icons.image_not_supported,
                                            color: Colors.grey),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text(
                                  '$name  x$quantity',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            top: 4,
                            left: 4,
                            child: isHousehold
                              ? CircleAvatar(
                                radius: 12,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: const Icon(Icons.home, size: 14),
                              )
                              : CircleAvatar(
                                radius: 12,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: Text(
                                  addedByName.isNotEmpty
                                      ? addedByName[0].toUpperCase()
                                      : '?',
                                ),
                              ),
                          ),
                          if (canModify)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: IconButton(
                                  onPressed: () => _confirmDelete(context, docs[index].id, name),
                                  icon: const Icon(Icons.close, size: 14),
                                  padding: EdgeInsets.zero,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.red[100],
                                    foregroundColor: Colors.red[600],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                        ),
                        if (daysLeft != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              daysLeft < 0
                                  ? 'Replace now'
                                  : daysLeft == 0
                                      ? 'Expires today'
                                      : daysLeft == 1
                                          ? '1 day left'
                                          : '$daysLeft days left',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: daysLeft < 0
                                    ? Colors.red[700]
                                    : daysLeft == 0
                                        ? Colors.red
                                        : daysLeft <= 3
                                            ? Colors.orange[800]
                                            : Colors.green[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  // PRODUCT REMOVAL CONFIRMATION MESSAGE
  Future<void> _confirmDelete(BuildContext context, String documentId, String itemName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove $itemName from your kitchen inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    // Firestore remove product
    if (confirmed == true) {
      await FirestoreService.removeItem(documentId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item removed from kitchen!')),
      );
    }
  }
}
enum _HomeMenuAction {
  kitchenSettings,
  viewMembers,
  adminConsole,
}

class KitchenSettingsScreen extends StatefulWidget {
  const KitchenSettingsScreen({super.key});

  @override
  State<KitchenSettingsScreen> createState() => _KitchenSettingsScreenState();
}

class _KitchenSettingsScreenState extends State<KitchenSettingsScreen> {
  final _nameController = TextEditingController();
  bool _isSaving = false;
  bool _isOwner = false;
  bool _nameInitialized = false;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('kitchens')
        .doc(FirestoreService.kitchenId)
        .collection('members')
        .doc(uid)
        .get();
    if (mounted) {
      setState(() => _isOwner = doc.data()?['role'] == 'owner');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveKitchenName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a kitchen name')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await FirestoreService.renameKitchen(newName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kitchen name updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update kitchen name: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kitchen Settings')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirestoreService.kitchenStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final kitchenName = data?['name'] as String? ?? '';
          final inviteCode = data?['inviteCode'] as String? ?? '';
          if (!_nameInitialized && kitchenName.isNotEmpty) {
            _nameController.text = kitchenName;
            _nameInitialized = true;
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Kitchen Name',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_isOwner) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Kitchen Name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isSaving ? null : _saveKitchenName,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save'),
                  ),
                ] else
                  Text(kitchenName,
                      style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 32),
                Text('Invite Code',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(inviteCode,
                    style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          );
        },
      ),
    );
  }
}


class ViewMembersScreen extends StatelessWidget {
  const ViewMembersScreen({super.key});

  Future<void> _confirmRemoveMember(
    BuildContext context,
    String memberUid,
    String memberName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $memberName from this kitchen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirestoreService.removeMember(memberUid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$memberName has been removed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Kitchen Members')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirestoreService.membersStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading members: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'No members found',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final isOwner = docs.any(
            (doc) =>
                doc.id == currentUid &&
                (doc.data()! as Map<String, dynamic>)['role'] == 'owner',
          );

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final memberData =
                  docs[index].data()! as Map<String, dynamic>;
              final displayName =
                  (memberData['displayName'] as String?) ?? 'Unknown';
              final role = (memberData['role'] as String?) ?? 'member';

              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(displayName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: role == 'owner'
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        role[0].toUpperCase() + role.substring(1),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    if (isOwner && docs[index].id != currentUid) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _confirmRemoveMember(
                          context,
                          docs[index].id,
                          displayName,
                        ),
                        icon: Icon(Icons.person_remove,
                            size: 20, color: Colors.red[600]),
                        tooltip: 'Remove member',
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}