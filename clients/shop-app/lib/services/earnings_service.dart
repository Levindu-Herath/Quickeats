import 'package:intl/intl.dart';
import 'package:quickeats_shop/core/constants/api_constants.dart';
import 'package:quickeats_shop/core/network/api_client.dart';
import 'package:quickeats_shop/models/earnings.dart';

class EarningsService {
  final ApiClient _apiClient;

  EarningsService({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Earnings for [day] as a local calendar day: the phone's UTC offset is sent so the
  /// server counts orders from local midnight to midnight.
  Future<ShopEarnings> getDailyEarnings(String shopId, DateTime day) async {
    final response = await _apiClient.dio.get(ApiConstants.shopEarnings(shopId), queryParameters: {
      'date': DateFormat('yyyy-MM-dd').format(day),
      'tzOffset': day.timeZoneOffset.inMinutes,
    });
    return ShopEarnings.fromJson(response.data['data']);
  }
}
