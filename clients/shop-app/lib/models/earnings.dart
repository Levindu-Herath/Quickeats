import 'package:intl/intl.dart';
import 'package:quickeats_shop/core/constants/order_status.dart';

final _money = NumberFormat('#,##0.00');

/// Formats cents as "LKR 1,234.50".
String formatLkr(int cents) => 'LKR ${_money.format(cents / 100)}';

/// One day of the shop's earnings, in the shop's local time. Amounts are in cents.
/// Only paid orders that weren't cancelled or rejected earn; the shop keeps 95%.
class ShopEarnings {
  final DateTime date;
  final int grossSales;
  final int platformFee;
  final int netEarnings;
  final int pendingEarnings; // part of netEarnings from orders not picked up yet
  final int paidOrders;
  final int completedOrders;
  final int inProgressOrders;
  final int rejectedOrders;
  final int cancelledOrders;
  final int rejectedSales;
  final int averageOrder;
  final int itemsSold;
  final List<ItemSales> topItems;
  final List<HourSales> hourly; // 24 entries, hours 0-23
  final List<DaySales> week; // the 7 days ending on [date], oldest first
  final List<EarningOrder> orders; // newest first

  ShopEarnings({
    required this.date, required this.grossSales, required this.platformFee, required this.netEarnings,
    required this.pendingEarnings, required this.paidOrders, required this.completedOrders,
    required this.inProgressOrders, required this.rejectedOrders, required this.cancelledOrders,
    required this.rejectedSales, required this.averageOrder, required this.itemsSold,
    required this.topItems, required this.hourly, required this.week, required this.orders,
  });

  factory ShopEarnings.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
      (json[key] as List<dynamic>? ?? []).map((e) => f(e as Map<String, dynamic>)).toList();
    return ShopEarnings(
      date: DateTime.parse(json['date']),
      grossSales: json['grossSales'] ?? 0,
      platformFee: json['platformFee'] ?? 0,
      netEarnings: json['netEarnings'] ?? 0,
      pendingEarnings: json['pendingEarnings'] ?? 0,
      paidOrders: json['paidOrders'] ?? 0,
      completedOrders: json['completedOrders'] ?? 0,
      inProgressOrders: json['inProgressOrders'] ?? 0,
      rejectedOrders: json['rejectedOrders'] ?? 0,
      cancelledOrders: json['cancelledOrders'] ?? 0,
      rejectedSales: json['rejectedSales'] ?? 0,
      averageOrder: json['averageOrder'] ?? 0,
      itemsSold: json['itemsSold'] ?? 0,
      topItems: list('topItems', ItemSales.fromJson),
      hourly: list('hourly', HourSales.fromJson),
      week: list('week', DaySales.fromJson),
      orders: list('orders', EarningOrder.fromJson),
    );
  }

  bool get hasOrders => orders.isNotEmpty;
}

class ItemSales {
  final String itemName;
  final int quantity;
  final int sales;
  ItemSales({required this.itemName, required this.quantity, required this.sales});
  factory ItemSales.fromJson(Map<String, dynamic> json) =>
    ItemSales(itemName: json['itemName'] ?? '', quantity: json['quantity'] ?? 0, sales: json['sales'] ?? 0);
}

class HourSales {
  final int hour;
  final int orders;
  final int sales;
  HourSales({required this.hour, required this.orders, required this.sales});
  factory HourSales.fromJson(Map<String, dynamic> json) =>
    HourSales(hour: json['hour'] ?? 0, orders: json['orders'] ?? 0, sales: json['sales'] ?? 0);
}

class DaySales {
  final DateTime date;
  final int orders;
  final int netEarnings;
  DaySales({required this.date, required this.orders, required this.netEarnings});
  factory DaySales.fromJson(Map<String, dynamic> json) =>
    DaySales(date: DateTime.parse(json['date']), orders: json['orders'] ?? 0, netEarnings: json['netEarnings'] ?? 0);
}

class EarningOrder {
  final String id;
  final OrderStatus status;
  final String pickupCode;
  final int totalAmount;
  final int netAmount; // 0 when the order didn't earn
  final int itemCount;
  final String rejectReason;
  final DateTime createdAt;

  EarningOrder({
    required this.id, required this.status, required this.pickupCode, required this.totalAmount,
    required this.netAmount, required this.itemCount, required this.rejectReason, required this.createdAt,
  });

  factory EarningOrder.fromJson(Map<String, dynamic> json) => EarningOrder(
    id: json['id'] ?? '',
    status: OrderStatus.fromString(json['status'] ?? ''),
    pickupCode: json['pickupCode'] ?? '',
    totalAmount: json['totalAmount'] ?? 0,
    netAmount: json['netAmount'] ?? 0,
    itemCount: json['itemCount'] ?? 0,
    rejectReason: json['rejectReason'] ?? '',
    createdAt: (DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now()).toLocal(),
  );

  String get shortId => id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
  bool get earned => netAmount > 0;
}
