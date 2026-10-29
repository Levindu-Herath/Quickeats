import 'package:flutter/foundation.dart';
import 'package:quickeats_shop/models/earnings.dart';
import 'package:quickeats_shop/services/account_service.dart';
import 'package:quickeats_shop/services/auth_service.dart';
import 'package:quickeats_shop/services/earnings_service.dart';

class EarningsViewModel extends ChangeNotifier {
  final EarningsService _earningsService;
  final AuthService _authService;

  EarningsViewModel({required EarningsService earningsService, required AuthService authService})
    : _earningsService = earningsService, _authService = authService;

  DateTime _day = _dateOnly(DateTime.now());
  ShopEarnings? _earnings;
  bool _isLoading = false;
  String? _error;
  int _request = 0; // only the latest request may update the screen
  String? _shopId; // whose earnings are shown, so another login doesn't see them

  DateTime get day => _day;
  ShopEarnings? get earnings => _earnings;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isToday => _day == _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> load() async {
    final shopId = _authService.shopId;
    if (shopId == null) return;
    if (shopId != _shopId) {
      _shopId = shopId;
      _earnings = null;
      _day = _dateOnly(DateTime.now());
    }
    final request = ++_request;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final earnings = await _earningsService.getDailyEarnings(shopId, _day);
      if (request != _request) return;
      _earnings = earnings;
    } catch (e) {
      if (request != _request) return;
      _error = apiErrorMessage(e, 'Couldn\'t load earnings');
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Shows [day]; days after today aren't allowed.
  Future<void> selectDay(DateTime day) async {
    final d = _dateOnly(day);
    if (d == _day || d.isAfter(_dateOnly(DateTime.now()))) return;
    _day = d;
    _earnings = null;
    await load();
  }

  Future<void> previousDay() => selectDay(DateTime(_day.year, _day.month, _day.day - 1));
  Future<void> nextDay() => selectDay(DateTime(_day.year, _day.month, _day.day + 1));
}
