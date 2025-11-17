import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:kitchenms/widget/custom_appBar';
import 'package:kitchenms/screens/request_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

// Model for an order document
class OrderModel {
  final String id;
  final int queueIndex; // 1-based index in queue
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double tax;
  final double total;
  final String? tableName;
  final String? userName;
  final String? status;
  final Timestamp? timestamp;

  OrderModel({
    required this.id,
    required this.queueIndex,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.tableName,
    this.userName,
    this.status,
    this.timestamp,
  });

  factory OrderModel.fromDoc(int queueIndex, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final items = <Map<String, dynamic>>[];
    if (data['items'] is List) {
      for (var it in data['items']) {
        if (it is Map) items.add(Map<String, dynamic>.from(it));
      }
    }
    return OrderModel(
      id: doc.id,
      queueIndex: queueIndex,
      items: items,
      subtotal: (data['subtotal'] is num) ? (data['subtotal'] as num).toDouble() : 0.0,
      tax: (data['tax'] is num) ? (data['tax'] as num).toDouble() : 0.0,
      total: (data['total'] is num) ? (data['total'] as num).toDouble() : 0.0,
      tableName: data['tableName'] as String?,
      userName: data['userName'] as String?,
      status: data['status'] as String?,
      timestamp: data['timestamp'] as Timestamp?,
    );
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Set<String> _held = {};

  // Helper: update order status in Firestore
  Future<void> _setOrderStatus(String docId, String status) async {
    await FirebaseFirestore.instance
        .collection('orders')
        .doc(docId)
        .update({'status': status});
  }

  void _showOrderDetails(OrderModel order) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Order ${order.queueIndex}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Table: ${order.tableName ?? '—'}'),
                const SizedBox(height: 8),
                Text('User: ${order.userName ?? '—'}'),
                const SizedBox(height: 8),
                const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...order.items.map((it) => Text('${it['name']} x${it['qty']} — ${it['total']}')),
                const SizedBox(height: 12),
                Text('Subtotal: ${order.subtotal}'),
                Text('Tax: ${order.tax}'),
                Text('Total: ${order.total}'),
                const SizedBox(height: 12),
                Text('Status: ${order.status ?? 'pending'}'),
              ],
            ),
          ),
          actions: [
            if (order.status != 'in progress')
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _setOrderStatus(order.id, 'in progress');
                },
                child: const Text('Start (In Progress)'),
              ),
            if (order.status == 'in progress' || order.status == 'done' || order.status == null)
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _setOrderStatus(order.id, 'done');
                },
                child: const Text('Mark Done'),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
  }

  // Order actions are now handled via Firestore and the order details dialog.

  // time formatting removed — header shows time elsewhere if needed

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffe6eef7),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RequestScreen()),
          );
        },
        child: const Icon(Icons.request_page),
      ),
      body: Column(
        children: [
        custom_appBar(),
          const SizedBox(height: 10),
          _buildStatusHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('orders')
                    .orderBy('timestamp', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  final docs = snapshot.data!.docs;
                  final orders = docs
                      .asMap()
                      .entries
                      .map((e) => OrderModel.fromDoc(e.key + 1, e.value))
                      .toList();

                  final todo = orders.where((o) => o.status == null || o.status == 'pending').toList();
                  final inProgress = orders.where((o) => o.status == 'in progress').toList();
                  final done = orders.where((o) => o.status == 'done').toList();

                  return Row(
                    children: [
                      Expanded(
                        child: OrdersColumn(
                          title: 'to do',
                          color: Colors.red,
                          orders: todo,
                          held: _held,
                          onItemTap: (order) => _showOrderDetails(order),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: OrdersColumn(
                          title: 'in process',
                          color: Colors.yellow,
                          orders: inProgress,
                          held: _held,
                          onItemTap: (order) => _showOrderDetails(order),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: OrdersColumn(
                          title: 'done',
                          color: Colors.green,
                          orders: done,
                          held: _held,
                          onItemTap: (order) => _showOrderDetails(order),
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

  // Header UI moved into main dashboard build; kept minimal here.

  // ----------------------------------------------------------
  // STATUS LABELS (red–yellow–green)
  // ----------------------------------------------------------
  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          StatusLabel(color: Colors.red, text: "to do"),
          SizedBox(width: 40),
          StatusLabel(color: Colors.yellow, text: "in process"),
          SizedBox(width: 40),
          StatusLabel(color: Colors.green, text: "done"),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------
// STATUS LABEL WIDGET
// ----------------------------------------------------------
class StatusLabel extends StatelessWidget {
  final Color color;
  final String text;

  const StatusLabel({super.key, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(radius: 8, backgroundColor: color),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 16)),
      ],
    );
  }
}

// ----------------------------------------------------------
// ORDERS COLUMN WIDGET
// ----------------------------------------------------------
class OrdersColumn extends StatelessWidget {
  final String title;
  final Color color;
  final List<OrderModel> orders;
  final Set<String> held;
  final void Function(OrderModel order) onItemTap;

  const OrdersColumn({
    super.key,
    required this.title,
    required this.color,
    required this.orders,
    required this.held,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                    for (var order in orders)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onItemTap(order),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(radius: 10, backgroundColor: color),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Order ${order.queueIndex}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                if (held.contains(order.id)) ...[
                                  const Icon(
                                    Icons.pause_circle_filled,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                const Icon(Icons.more_vert),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
            ),
          ),
        ],
      ),
    );

  }
}
