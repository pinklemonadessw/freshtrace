import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';

class AdminKitchenDetailScreen extends StatelessWidget {
  final String kitchenId;
  final String kitchenName;

  const AdminKitchenDetailScreen({
    super.key,
    required this.kitchenId,
    required this.kitchenName,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(kitchenName, overflow: TextOverflow.ellipsis),
              Text(
                'Admin View  ·  id: $kitchenId',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onErrorContainer
                          .withValues(alpha: 0.7),
                    ),
              ),
            ],
          ),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Inventory'),
              Tab(icon: Icon(Icons.people_outline), text: 'Members'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AdminInventoryTab(kitchenId: kitchenId),
            _AdminMembersTab(kitchenId: kitchenId),
          ],
        ),
      ),
    );
  }
}

class _AdminInventoryTab extends StatelessWidget {
  final String kitchenId;
  const _AdminInventoryTab({required this.kitchenId});

  Future<void> _confirmDelete(
    BuildContext context,
    String documentId,
    String itemName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete as Admin'),
        content: Text(
          'Remove "$itemName" from this kitchen\'s inventory?\n\n'
          'This action bypasses normal ownership checks.',
        ),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirestoreService.adminRemoveItem(kitchenId, documentId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "$itemName"')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreService.inventoryStreamFor(kitchenId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading inventory: ${snapshot.error}'),
            ),
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
                  'This kitchen has no inventory items.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data()! as Map<String, dynamic>;
            final name = (data['name'] as String?) ?? 'Unknown';
            final imageUrl = (data['imageUrl'] as String?) ?? '';
            final quantity = data['quantity'] ?? 1;
            final category = (data['category'] as String?) ?? '—';
            final addedByName =
                (data['addedByName'] as String?) ?? 'Unknown';
            final expiresTs = data['expiresAt'] as Timestamp?;
            final expiresAt = expiresTs?.toDate();
            final isHousehold =
                data['isHouseholdItem'] as bool? ?? false;

            return ListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image,
                                color: Colors.grey),
                          ),
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.image_not_supported,
                              color: Colors.grey),
                        ),
                ),
              ),
              title: Text(
                '$name  x$quantity',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category: $category  ·  '
                    'Added by: $addedByName'
                    '${isHousehold ? '  ·  Household' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (expiresAt != null)
                    Text(
                      'Expires ${DateFormat.yMMMd().format(expiresAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: expiresAt.isBefore(DateTime.now())
                                ? Colors.red[700]
                                : null,
                          ),
                    ),
                  Text(
                    'doc: ${doc.id}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: Icon(Icons.delete_outline,
                    color: Colors.red[700]),
                tooltip: 'Delete as Admin',
                onPressed: () => _confirmDelete(context, doc.id, name),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminMembersTab extends StatelessWidget {
  final String kitchenId;
  const _AdminMembersTab({required this.kitchenId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreService.membersStreamFor(kitchenId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading members: ${snapshot.error}'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No members in this kitchen.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data()! as Map<String, dynamic>;
            final displayName =
                (data['displayName'] as String?) ?? 'Unknown';
            final role = (data['role'] as String?) ?? 'member';
            final joinedTs = data['joinedAt'] as Timestamp?;
            final joinedAt = joinedTs?.toDate();

            return ListTile(
              leading: CircleAvatar(
                child: Text(
                  displayName.isNotEmpty
                      ? displayName[0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(displayName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('uid: ${doc.id}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey)),
                  if (joinedAt != null)
                    Text(
                      'Joined ${DateFormat.yMMMd().add_jm().format(joinedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: role == 'owner'
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  role.isEmpty
                      ? 'member'
                      : role[0].toUpperCase() + role.substring(1),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
