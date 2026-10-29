import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_customer/core/constants/app_colors.dart';
import 'package:quickeats_customer/viewmodels/cart_viewmodel.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Future<void> _confirmClear(BuildContext context, CartViewModel cart) async {
    final count = cart.itemCount;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Clear cart?'),
      content: Text('This removes ${count == 1 ? 'the item' : 'all $count items'}'
        '${cart.shopName != null ? ' from ${cart.shopName}' : ''} from your cart.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(c, true),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.error), child: const Text('Clear'))],
    ));
    if (ok == true) cart.clear();
  }

  @override Widget build(BuildContext context) {
    return Consumer<CartViewModel>(builder: (_, cart, __) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart', style: TextStyle(fontWeight: FontWeight.w700)), backgroundColor: AppColors.white, elevation: 0,
          actions: [if (!cart.isEmpty) TextButton(onPressed: () => _confirmClear(context, cart), child: const Text('Clear', style: TextStyle(color: AppColors.error)))]),
        body: cart.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textMuted), const SizedBox(height: 12),
              const Text('Your cart is empty', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(onPressed: () => context.go('/shops'), child: const Text('Browse Shops')),
            ]))
          : Column(children: [
              if (cart.shopName != null) Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), color: AppColors.primaryLight,
                child: Text('From: ${cart.shopName}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.primary))),
              Expanded(child: ListView.builder(
                padding: const EdgeInsets.all(16), itemCount: cart.items.length,
                itemBuilder: (_, i) {
                  final item = cart.items[i];
                  return Card(margin: const EdgeInsets.only(bottom: 8), elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
                    child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.menuItem.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(item.formattedSubtotal, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ])),
                      Container(decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.remove, size: 18), onPressed: () => cart.updateQuantity(item.menuItem.id, item.quantity - 1), constraints: const BoxConstraints(minWidth: 36, minHeight: 36), padding: EdgeInsets.zero),
                        Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(icon: const Icon(Icons.add, size: 18), onPressed: () => cart.updateQuantity(item.menuItem.id, item.quantity + 1), constraints: const BoxConstraints(minWidth: 36, minHeight: 36), padding: EdgeInsets.zero),
                      ])),
                    ])),
                  );
                },
              )),
              Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.border))),
                child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const Spacer(), Text(cart.formattedTotal, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary))]),
                  const SizedBox(height: 12),
                  SizedBox(height: 50, child: FilledButton(onPressed: () => context.push('/checkout'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Proceed to Checkout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
                ]))),
            ]),
      );
    });
  }
}
