import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_shop/core/constants/app_colors.dart';
import 'package:quickeats_shop/models/order.dart';
import 'package:quickeats_shop/viewmodels/order_queue_viewmodel.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<OrderQueueViewModel>(
      builder: (context, vm, _) {
        final order = vm.allOrders.where((o) => o.id == widget.orderId).firstOrNull;
        if (order == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Order not found')));
        }

        final statusColor = AppColors.forStatus(order.status.value);
        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            title: Text('#${order.shortId}'),
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 12, color: statusColor),
                      const SizedBox(width: 8),
                      Text(order.status.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: statusColor)),
                      const Spacer(),
                      Text(order.waitTimeFormatted, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Pickup code
                if (order.pickupCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: Column(
                      children: [
                        Text('PICKUP CODE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        Text(order.pickupCode, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 4)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Items
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      ...order.items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(6)),
                              child: Center(child: Text('${item.quantity}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(item.itemName, style: TextStyle(fontSize: 14, color: AppColors.textPrimary))),
                            Text('LKR ${(item.subtotal / 100).toStringAsFixed(2)}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ),
                      )),
                      const Divider(),
                      Row(
                        children: [
                          Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text(order.formattedTotal, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons: a new order is accepted or rejected; an accepted one
                // can only be completed.
                if (order.status.nextShopAction != null)
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _advance(vm, order),
                      style: FilledButton.styleFrom(
                        backgroundColor: statusColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(order.status.nextActionLabel, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),

                if (order.status.canReject)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _reject(vm, order),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Reject Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _advance(OrderQueueViewModel vm, Order order) async {
    setState(() => _busy = true);
    final ok = await vm.updateStatus(order.id, order.status.nextShopAction!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _showError(vm.error ?? 'Failed to update the order');
  }

  Future<void> _reject(OrderQueueViewModel vm, Order order) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _RejectDialog());
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await vm.rejectOrder(order.id, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _showError(vm.error ?? 'Failed to reject the order');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Asks for a rejection reason: one of the common reasons, or "Other", which opens
/// [_OtherReasonDialog] to type one. Pops with the reason, or null when cancelled.
/// It pops with its own context: the detail screen's context belongs to the shell's
/// nested navigator, so popping that would close the screen and leave the dialog open.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  static const _commonReasons = [
    'Item is out of stock',
    'Shop is too busy right now',
    'Shop is closing soon',
  ];

  String? _selected;

  Future<void> _other() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _OtherReasonDialog());
    if (reason != null && mounted) Navigator.pop(context, reason);
  }

  Widget _option(String label, {required bool selected, required VoidCallback onTap, Widget? trailing}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.error : null,
      ),
      title: Text(label),
      trailing: trailing,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject Order'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Why are you rejecting this order?'),
          const SizedBox(height: 8),
          for (final reason in _commonReasons)
            _option(reason, selected: _selected == reason, onTap: () => setState(() => _selected = reason)),
          _option('Other', selected: false, onTap: _other, trailing: const Icon(Icons.edit_outlined, size: 20)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

/// Asks for a rejection reason in the shop's own words; pops with the trimmed reason,
/// or null when cancelled (back to the list of common reasons).
class _OtherReasonDialog extends StatefulWidget {
  const _OtherReasonDialog();
  @override
  State<_OtherReasonDialog> createState() => _OtherReasonDialogState();
}

class _OtherReasonDialogState extends State<_OtherReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason.text.trim();
    return AlertDialog(
      title: const Text('Other reason'),
      content: TextField(
        controller: _reason,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: 'Reason for rejection', border: OutlineInputBorder()),
        maxLines: 3,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: reason.isEmpty ? null : () => Navigator.pop(context, reason),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
