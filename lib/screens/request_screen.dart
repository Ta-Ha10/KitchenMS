import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _filterMode; // 'date', 'month', or null

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _sendRequest(ComponentModel component) {
    _createKitchenRequestFromComponent(component);
  }

  Future<void> _createKitchenRequestFromComponent(ComponentModel component) async {
    try {
      // fetch full raw_components document to get all fields
      final doc = await FirebaseFirestore.instance.collection('raw_components').doc(component.id).get();
      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Component not found')));
        return;
      }

      final data = doc.data() ?? <String, dynamic>{};

      // Build item map matching screenshot structure. Use available fields from raw_components.
      final now = DateTime.now();
      final item = <String, dynamic>{
        'name': data['name'] ?? component.name,
        'category': data['category'] ?? component.category,
        'fillingWay': data['fillingWay'] ?? data['filling_way'] ?? data['filling'] ?? '',
        'price': data['price'] ?? '',
        'quantity': data['quantity'] ?? data['qty'] ?? 1,
        'date': now.toIso8601String(),
        'status': 'pending',
        'supplier': data['supplier'] ?? '',
        'unit': data['unit'] ?? '',
      };

      // Store under a new document in kitchen_requests with a 'pending' map containing '0': item
      final payload = <String, dynamic>{
        'createdAt': Timestamp.fromDate(now),
        'pending': {'0': item},
      };

      await FirebaseFirestore.instance.collection('kitchen_requests').add(payload);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request created')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating request: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Raw Components Request'),
        centerTitle: true,
      ),
      body: Row(
        children: [
          // Left side: Filter, Search, and Table
          Expanded(
            child: Column(
              children: [
                // Filter buttons
                Padding(
                  padding: const EdgeInsets.all(12.0),
                
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by name or category...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                // Components table (expanded to fill available height)
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('raw_components')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;
                      final components = docs
                          .map((doc) => ComponentModel.fromDoc(doc))
                          .toList();

                      // Filter by search query
                      final filtered = _searchQuery.isEmpty
                          ? components
                          : components
                              .where((c) =>
                                  c.name.toLowerCase().contains(_searchQuery) ||
                                  (c.category?.toLowerCase().contains(_searchQuery) ?? false))
                              .toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text('No components found'),
                        );
                      }

                      return SingleChildScrollView(
                        child: Container(
                          color: Colors.white,
                          child: SizedBox(
                            width: double.infinity,
                            child: DataTable(
                              columnSpacing: 16,
                              horizontalMargin: 12,
                              columns: const [
                                DataColumn(label: Text('Name')),
                                DataColumn(label: Text('Category')),
                                DataColumn(label: Text('Action')),
                              ],
                            rows: filtered
                                .map(
                                  (component) => DataRow(
                                    cells: [
                                      DataCell(Text(component.name)),
                                      DataCell(Text(component.category ?? '—')),
                                      DataCell(
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xff6fad99),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                          ),
                                          onPressed: () => _sendRequest(component),
                                          child: const Text(
                                            'Request',
                                            style: TextStyle(color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // separator between left and right panels
          SizedBox(width: 12),
          VerticalDivider(width: 24, thickness: 1, color: Colors.grey.shade300),
          SizedBox(width: 12),

          // Right side: Two tables (Sent and Pending requests)
          Expanded(
            child: Container(
              color: Colors.white,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('kitchen_requests').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;

                  // Build flattened list of request entries. Firestore documents may be either:
                  // - individual request documents (having a 'name' field), or
                  // - documents that group requests under keys like 'pending'/'sent' as List or Map.
                  final List<Map<String, dynamic>> entries = [];

                  for (final d in docs) {
                    final data = Map<String, dynamic>.from(d.data());

                    // If doc itself looks like a single request, add it directly
                    if (data.containsKey('name')) {
                      final m = Map<String, dynamic>.from(data);
                      m['id'] = d.id;
                      entries.add(m);
                      continue;
                    }

                    // Otherwise scan top-level keys for lists or maps containing request items
                    for (final key in data.keys) {
                      final val = data[key];
                      if (val is List) {
                        for (final item in val) {
                          if (item is Map) {
                            final m = Map<String, dynamic>.from(item);
                            m['parentDoc'] = d.id;
                            m['sourceKey'] = key;
                            entries.add(m);
                          }
                        }
                      } else if (val is Map) {
                        // Maps may be keyed by numeric strings ('0','1',...)
                        for (final item in val.values) {
                          if (item is Map) {
                            final m = Map<String, dynamic>.from(item);
                            m['parentDoc'] = d.id;
                            m['sourceKey'] = key;
                            entries.add(m);
                          }
                        }
                      }
                    }
                  }

                  // Fallback: if nothing extracted above, include raw documents
                  if (entries.isEmpty) {
                    for (final d in docs) {
                      final m = Map<String, dynamic>.from(d.data());
                      m['id'] = d.id;
                      entries.add(m);
                    }
                  }

                  // Helper to test sent status and retrieve fallback fields
                  bool isSent(Map<String, dynamic> e) {
                    final sentDate = e['sentDate'] ?? e['sent_date'] ?? e['sentAt'] ?? e['dateSent'];
                    final status = e['status']?.toString().toLowerCase();
                    return (sentDate != null && sentDate.toString().isNotEmpty) || (status == 'sent');
                  }

                  dynamic getField(Map<String, dynamic> e, List<String> keys) {
                    for (final k in keys) {
                      if (e.containsKey(k) && e[k] != null) return e[k];
                    }
                    return null;
                  }

                  String formatDate(dynamic val) {
                    if (val == null) return '—';
                    try {
                      DateTime dt;
                      if (val is DateTime) {
                        dt = val;
                      } else if (val is Timestamp) {
                        dt = val.toDate();
                      } else {
                        dt = DateTime.parse(val.toString());
                      }
                      String two(int n) => n.toString().padLeft(2, '0');
                      return '${two(dt.hour)}:${two(dt.minute)} ${two(dt.day)}/${two(dt.month)}';
                    } catch (e) {
                      return val.toString();
                    }
                  }

                  final sent = entries.where((e) => isSent(e)).toList();
                  final pending = entries.where((e) => !isSent(e)).toList();

                  DateTime _parseDate(dynamic val) {
                    if (val == null) return DateTime.fromMillisecondsSinceEpoch(0);
                    try {
                      if (val is Timestamp) return val.toDate();
                      if (val is DateTime) return val;
                      final s = val.toString();
                      return DateTime.parse(s);
                    } catch (_) {
                      return DateTime.fromMillisecondsSinceEpoch(0);
                    }
                  }

                  DateTime _entryDate(Map<String, dynamic> e) {
                    // prefer sentDate, then date, then requestDate
                    final candidates = [
                      e['sentDate'],
                      e['sent_date'],
                      e['sentAt'],
                      e['dateSent'],
                      e['date'],
                      e['requestDate'],
                      e['request_date'],
                    ];
                    for (final c in candidates) {
                      if (c != null) return _parseDate(c);
                    }
                    return DateTime.fromMillisecondsSinceEpoch(0);
                  }

                  // sort newest -> oldest
                  sent.sort((a, b) => _entryDate(b).compareTo(_entryDate(a)));
                  pending.sort((a, b) => _entryDate(b).compareTo(_entryDate(a)));

                  // If both lists empty, show message
                  if (sent.isEmpty && pending.isEmpty) {
                    return const Center(child: Text('No kitchen requests'));
                  }

                  // Two tables stacked vertically, each scrollable and taking available height
                  return Column(
                    children: [
                      // Sent requests table header
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0, left: 12.0, right: 12.0),
                        child: Row(
                          children: const [
                            Text('Sent Requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Container(
                                color: Colors.white,
                                child: SingleChildScrollView(
                                  // vertical
                                  child: SingleChildScrollView(
                                    // horizontal
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                      child: DataTable(
                                        columnSpacing: 16,
                                        horizontalMargin: 12,
                                        columns: const [
                                          DataColumn(label: Text('Name')),
                                          DataColumn(label: Text('Category')),
                                          DataColumn(label: Text('Request Date')),
                                          DataColumn(label: Text('Sent Date')),
                                          DataColumn(label: Text('Quantity')),
                                        ],
                                        rows: sent
                                            .map(
                                              (e) => DataRow(
                                                cells: [
                                                  DataCell(Text((getField(e, ['name', 'item', 'product'])?.toString() ?? '—'))),
                                                  DataCell(Text((getField(e, ['category', 'cat'])?.toString() ?? '—'))),
                                                  DataCell(Text(formatDate(getField(e, ['requestDate', 'request_date', 'date'])))),
                                                  DataCell(Text(formatDate(getField(e, ['sentDate', 'sent_date', 'sentAt', 'dateSent'])))),
                                                  DataCell(Text((getField(e, ['sentQty', 'sent_qty', 'quantity', 'qty'])?.toString() ?? '—'))),
                                                ],
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // Pending requests table header
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, left: 12.0, right: 12.0),
                        child: Row(
                          children: const [
                            Text('Pending Requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Container(
                                color: Colors.white,
                                child: SingleChildScrollView(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                      child: DataTable(
                                        columnSpacing: 16,
                                        horizontalMargin: 12,
                                        columns: const [
                                          DataColumn(label: Text('Name')),
                                          DataColumn(label: Text('Category')),
                                          DataColumn(label: Text('Request Date')),
                                        ],
                                        rows: pending
                                            .map(
                                              (e) => DataRow(
                                                cells: [
                                                  DataCell(Text((getField(e, ['name', 'item', 'product'])?.toString() ?? '—'))),
                                                  DataCell(Text((getField(e, ['category', 'cat'])?.toString() ?? '—'))),
                                                  DataCell(Text(formatDate(getField(e, ['requestDate', 'request_date', 'date'])))),
                                                ],
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Model for raw_components document
class ComponentModel {
  final String id;
  final String name;
  final String? category;
  final String? requestDate;

  ComponentModel({
    required this.id,
    required this.name,
    this.category,
    this.requestDate,
  });

  factory ComponentModel.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ComponentModel(
      id: doc.id,
      name: data['name'] as String? ?? '—',
      category: data['category'] as String?,
      requestDate: data['requestDate'] as String?,
    );
  }
}
