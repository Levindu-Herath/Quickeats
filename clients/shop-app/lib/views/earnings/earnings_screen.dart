import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_shop/core/constants/app_colors.dart';
import 'package:quickeats_shop/models/earnings.dart';
import 'package:quickeats_shop/viewmodels/earnings_viewmodel.dart';

/// The shop's earnings for one day: what it keeps after the platform fee, how its
/// orders went, the last seven days, busiest hours, best sellers and the day's orders.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: loading notifies listeners, which must not happen mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<EarningsViewModel>().load(); });
  }

  Future<void> _pickDay(EarningsViewModel vm) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.day,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) vm.selectDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Earnings', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => context.read<EarningsViewModel>().load()),
        ],
      ),
      body: Consumer<EarningsViewModel>(builder: (context, vm, _) {
        final e = vm.earnings;
        return Column(children: [
          _DayBar(vm: vm, onPick: () => _pickDay(vm)),
          if (vm.isLoading && e != null) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(vm, e)),
        ]);
      }),
    );
  }

  Widget _body(EarningsViewModel vm, ShopEarnings? e) {
    if (e == null && vm.isLoading) return const Center(child: CircularProgressIndicator());
    if (e == null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        title: vm.error ?? 'Couldn\'t load earnings',
        action: OutlinedButton.icon(onPressed: vm.load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
      );
    }
    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        _SummaryCard(e: e, isToday: vm.isToday),
        const SizedBox(height: 12),
        _OrderStats(e: e),
        const _Section('Last 7 days'),
        _WeekChart(e: e, selected: vm.day, onSelect: vm.selectDay),
        if (!e.hasOrders) ...[
          const SizedBox(height: 24),
          _Message(
            icon: Icons.receipt_long_outlined,
            title: vm.isToday ? 'No orders yet today' : 'No orders on this day',
            subtitle: vm.isToday ? 'Earnings show up here as customers pay for orders.' : null,
          ),
        ] else ...[
          if (e.paidOrders > 0) ...[
            const _Section('Busiest hours'),
            _HourChart(hourly: e.hourly),
          ],
          if (e.topItems.isNotEmpty) ...[
            const _Section('Best sellers'),
            _TopItems(items: e.topItems),
          ],
          _Section('Orders (${e.orders.length})'),
          _OrderList(orders: e.orders),
        ],
      ]),
    );
  }
}

/// "‹  Today, Thu 29 Oct  ›" — arrows step a day, the middle opens a date picker.
class _DayBar extends StatelessWidget {
  final EarningsViewModel vm;
  final VoidCallback onPick;
  const _DayBar({required this.vm, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final isYesterday = vm.day.year == yesterday.year && vm.day.month == yesterday.month && vm.day.day == yesterday.day;
    final label = vm.isToday ? 'Today' : isYesterday ? 'Yesterday' : DateFormat('EEEE').format(vm.day);
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous day', onPressed: vm.previousDay),
        Expanded(child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPick,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                const Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.primary),
              ]),
              Text(DateFormat('d MMMM yyyy').format(vm.day), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
        )),
        IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Next day', onPressed: vm.isToday ? null : vm.nextDay),
      ]),
    );
  }
}

/// What the shop keeps for the day, and how it gets there from total sales.
class _SummaryCard extends StatelessWidget {
  final ShopEarnings e;
  final bool isToday;
  const _SummaryCard({required this.e, required this.isToday});

  @override
  Widget build(BuildContext context) {
    const light = TextStyle(color: Colors.white70, fontSize: 13);
    const value = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isToday ? 'Earned today' : 'Earned this day', style: light),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(formatLkr(e.netEarnings), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
        ),
        Text('from ${e.paidOrders} paid ${e.paidOrders == 1 ? 'order' : 'orders'}', style: light),
        const SizedBox(height: 14),
        const Divider(color: Colors.white24, height: 1),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Total sales', style: light)),
          Text(formatLkr(e.grossSales), style: value),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Expanded(child: Text('Platform fee (5%)', style: light)),
          Text('− ${formatLkr(e.platformFee)}', style: value),
        ]),
        if (e.pendingEarnings > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.hourglass_top, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('${formatLkr(e.pendingEarnings)} is from orders not picked up yet',
                style: const TextStyle(color: Colors.white, fontSize: 12))),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Order counts and averages in a grid of small tiles.
class _OrderStats extends StatelessWidget {
  final ShopEarnings e;
  const _OrderStats({required this.e});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _StatTile(icon: Icons.check_circle_outline, color: AppColors.secondary, label: 'Completed', value: '${e.completedOrders}'),
      _StatTile(icon: Icons.timelapse, color: AppColors.statusConfirmed, label: 'In progress', value: '${e.inProgressOrders}'),
      _StatTile(icon: Icons.shopping_basket_outlined, color: AppColors.statusPreparing, label: 'Items sold', value: '${e.itemsSold}'),
      _StatTile(icon: Icons.block, color: AppColors.error, label: 'Rejected', value: '${e.rejectedOrders}',
        note: e.rejectedSales > 0 ? '${formatLkr(e.rejectedSales)} refunded' : null),
      _StatTile(icon: Icons.cancel_outlined, color: AppColors.textSecondary, label: 'Cancelled', value: '${e.cancelledOrders}'),
      _StatTile(icon: Icons.receipt_outlined, color: AppColors.primary, label: 'Avg. order', value: formatLkr(e.averageOrder)),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 8.0;
      final columns = c.maxWidth >= 420 ? 3 : 2;
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: width, child: t)]);
    });
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  final String? note;
  const _StatTile({required this.icon, required this.color, required this.label, required this.value, this.note});

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(12),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        FittedBox(
          fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        if (note != null) Text(note!, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.error)),
      ])),
    ]),
  );
}

/// Net earnings for the last seven days; tapping a bar shows that day.
class _WeekChart extends StatelessWidget {
  final ShopEarnings e;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _WeekChart({required this.e, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final best = e.week.fold<int>(0, (m, d) => math.max(m, d.netEarnings));
    final total = e.week.fold<int>(0, (s, d) => s + d.netEarnings);
    final orders = e.week.fold<int>(0, (s, d) => s + d.orders);
    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(formatLkr(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        Text('$orders paid ${orders == 1 ? 'order' : 'orders'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]),
      const SizedBox(height: 14),
      SizedBox(
        height: 130,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in e.week)
            Expanded(child: _WeekBar(
              day: d,
              fraction: best == 0 ? 0 : d.netEarnings / best,
              selected: d.date.year == selected.year && d.date.month == selected.month && d.date.day == selected.day,
              onTap: () => onSelect(d.date),
            )),
        ]),
      ),
    ]));
  }
}

class _WeekBar extends StatelessWidget {
  final DaySales day;
  final double fraction;
  final bool selected;
  final VoidCallback onTap;
  const _WeekBar({required this.day, required this.fraction, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.25);
    return Tooltip(
      message: '${DateFormat('EEE d MMM').format(day.date)}: ${formatLkr(day.netEarnings)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (day.netEarnings > 0)
              FittedBox(child: Text(_compact(day.netEarnings),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: selected ? AppColors.primary : AppColors.textSecondary))),
            const SizedBox(height: 4),
            Flexible(child: FractionallySizedBox(
              heightFactor: math.max(fraction, 0.03),
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
            )),
            const SizedBox(height: 6),
            Text(DateFormat('E').format(day.date).substring(0, 2),
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }

  /// 123456 cents -> "1.2k" (rupees), short enough to fit above a bar.
  static String _compact(int cents) {
    final rupees = cents / 100;
    if (rupees >= 1000) return '${(rupees / 1000).toStringAsFixed(rupees >= 10000 ? 0 : 1)}k';
    return rupees.toStringAsFixed(0);
  }
}

/// Paid orders per hour, across the hours the shop had orders (plus one either side).
class _HourChart extends StatelessWidget {
  final List<HourSales> hourly;
  const _HourChart({required this.hourly});

  @override
  Widget build(BuildContext context) {
    final active = hourly.where((h) => h.orders > 0).toList();
    final first = math.max(0, active.first.hour - 1);
    final last = math.min(23, active.last.hour + 1);
    final hours = hourly.where((h) => h.hour >= first && h.hour <= last).toList();
    final most = active.fold<int>(0, (m, h) => math.max(m, h.orders));
    final peak = active.reduce((a, b) => b.orders > a.orders ? b : a);
    String hourLabel(int h) => DateFormat('ha').format(DateTime(2000, 1, 1, h)).toLowerCase();

    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), children: [
        const TextSpan(text: 'Busiest at '),
        TextSpan(text: '${hourLabel(peak.hour)}–${hourLabel((peak.hour + 1) % 24)}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        TextSpan(text: ' with ${peak.orders} ${peak.orders == 1 ? 'order' : 'orders'}'),
      ])),
      const SizedBox(height: 12),
      SizedBox(
        height: 90,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final h in hours)
            Expanded(child: Tooltip(
              message: '${hourLabel(h.hour)}: ${h.orders} ${h.orders == 1 ? 'order' : 'orders'}, ${formatLkr(h.sales)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (h.orders > 0) Text('${h.orders}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Flexible(child: FractionallySizedBox(
                    heightFactor: most == 0 ? 0.03 : math.max(h.orders / most, 0.03),
                    child: Container(decoration: BoxDecoration(
                      color: h.orders == most ? AppColors.statusPreparing : AppColors.statusPreparing.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4))),
                  )),
                  const SizedBox(height: 4),
                  FittedBox(child: Text(hourLabel(h.hour), style: const TextStyle(fontSize: 10, color: AppColors.textMuted))),
                ]),
              ),
            )),
        ]),
      ),
    ]));
  }
}

class _TopItems extends StatelessWidget {
  final List<ItemSales> items;
  const _TopItems({required this.items});

  @override
  Widget build(BuildContext context) {
    final most = items.first.quantity;
    return _Card(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Column(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: i == 0 ? AppColors.warning : AppColors.surfaceAlt,
              child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: i == 0 ? Colors.white : AppColors.textSecondary)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(items[i].itemName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: items[i].quantity / most, minHeight: 5,
                  backgroundColor: AppColors.surfaceAlt, color: AppColors.secondary),
              ),
            ])),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${items[i].quantity} sold', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(formatLkr(items[i].sales), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ]),
        ),
      ],
    ]));
  }
}

class _OrderList extends StatelessWidget {
  final List<EarningOrder> orders;
  const _OrderList({required this.orders});

  @override
  Widget build(BuildContext context) => _Card(padding: EdgeInsets.zero, child: Column(children: [
    for (var i = 0; i < orders.length; i++) ...[
      if (i > 0) const Divider(height: 1),
      _OrderRow(order: orders[i]),
    ],
  ]));
}

class _OrderRow extends StatelessWidget {
  final EarningOrder order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(order.status.value);
    final details = [
      DateFormat('h:mm a').format(order.createdAt),
      if (order.itemCount > 0) '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
      if (order.pickupCode.isNotEmpty && order.earned) 'Code ${order.pickupCode}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('#${order.shortId}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(order.status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(details, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (order.rejectReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(order.rejectReason, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textMuted)),
            ),
        ])),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (order.earned) ...[
            Text('+ ${formatLkr(order.netAmount)}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.secondary)),
            Text('of ${formatLkr(order.totalAmount)}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ] else
            Text(formatLkr(order.totalAmount), style: const TextStyle(
              color: AppColors.textMuted, decoration: TextDecoration.lineThrough)),
        ]),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const _Message({required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 56, color: AppColors.textMuted),
      const SizedBox(height: 12),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ],
      if (action != null) ...[const SizedBox(height: 16), action!],
    ]),
  ));
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: AppColors.textSecondary)));
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding, clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: child);
}
