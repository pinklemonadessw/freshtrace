import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import 'admin_kitchen_detail_screen.dart';

class AdminConsoleScreen extends StatefulWidget {
  const AdminConsoleScreen({super.key});

  @override
  State<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends State<AdminConsoleScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteKitchen(
    BuildContext context,
    String kitchenId,
    String kitchenName,
  ) async {
    final typedController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final matches =
                typedController.text.trim() == kitchenName;
            return AlertDialog(
              title: const Text('Delete Kitchen Permanently'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This will permanently delete "$kitchenName", every '
                    'inventory item inside it, and eject every member. '
                    'This action cannot be undone.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Type the kitchen name to confirm:',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: typedController,
                    autofocus: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: kitchenName,
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(ctx).colorScheme.error,
                  ),
                  onPressed:
                      matches ? () => Navigator.pop(ctx, true) : null,
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
    typedController.dispose();
    if (confirmed != true) return;
    if (!context.mounted) return;

    // Show a blocking progress indicator while the Cloud Function runs.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final cleared =
          await FirestoreService.adminDeleteKitchen(kitchenId);
      if (!context.mounted) return;
      Navigator.pop(context); // dismiss progress
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted "$kitchenName"'
            '${cleared > 0 ? '  ·  cleared $cleared user${cleared == 1 ? '' : 's'}' : ''}',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Delete failed (${e.code}): ${e.message ?? 'unknown error'}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You are viewing every kitchen. Use this for '
                      'troubleshooting only.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or invite code',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirestoreService.allKitchensStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading kitchens: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                final filtered = _query.isEmpty
                    ? docs
                    : docs.where((doc) {
                        final data = doc.data()! as Map<String, dynamic>;
                        final name = (data['name'] as String? ?? '')
                            .toLowerCase();
                        final code = (data['inviteCode'] as String? ?? '')
                            .toLowerCase();
                        return name.contains(_query) ||
                            code.contains(_query) ||
                            doc.id.toLowerCase().contains(_query);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _query.isEmpty
                            ? 'No kitchens found.'
                            : 'No kitchens match "$_query".',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final data = doc.data()! as Map<String, dynamic>;
                    final name =
                        (data['name'] as String?)?.trim() ?? '(unnamed)';
                    final code = (data['inviteCode'] as String?) ?? '';
                    final createdTs = data['createdAt'] as Timestamp?;
                    final createdAt = createdTs?.toDate();

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: const Icon(Icons.kitchen),
                      ),
                      title: Text(
                        name,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Code: $code  ·  id: ${doc.id}'),
                          if (createdAt != null)
                            Text(
                              'Created ${DateFormat.yMMMd().add_jm().format(createdAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          FutureBuilder<int>(
                            future: FirestoreService.memberCountFor(doc.id),
                            builder: (context, countSnap) {
                              final count = countSnap.data;
                              return Text(
                                count == null
                                    ? 'Loading members…'
                                    : '$count member${count == 1 ? '' : 's'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              );
                            },
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<_KitchenRowAction>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (action) {
                          switch (action) {
                            case _KitchenRowAction.open:
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdminKitchenDetailScreen(
                                    kitchenId: doc.id,
                                    kitchenName: name,
                                  ),
                                ),
                              );
                              break;
                            case _KitchenRowAction.delete:
                              _confirmDeleteKitchen(context, doc.id, name);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _KitchenRowAction.open,
                            child: ListTile(
                              leading: Icon(Icons.open_in_new),
                              title: Text('Open Kitchen'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _KitchenRowAction.delete,
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_forever,
                                color:
                                    Theme.of(context).colorScheme.error,
                              ),
                              title: const Text('Delete Kitchen'),
                              subtitle:
                                  const Text('Permanent · cannot be undone'),
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminKitchenDetailScreen(
                              kitchenId: doc.id,
                              kitchenName: name,
                            ),
                          ),
                        );
                      },
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
}

enum _KitchenRowAction { open, delete }
