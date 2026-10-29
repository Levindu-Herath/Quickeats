import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

class ApiConstants {
  // Release builds default to the deployed API so a plain `flutter build apk` works on real phones.
  // Debug default: web runs on the host itself; the Android emulator reaches the host via 10.0.2.2.
  // Point at the deployed API without editing code:
  //   flutter run --dart-define=API_BASE_URL=http://13.63.249.122
  static const String _host = kIsWeb ? 'localhost' : '10.0.2.2';
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kReleaseMode ? 'http://13.63.249.122' : 'http://$_host:8000',
  );
  // WebSocket goes through the Kong gateway like every other call (http→ws, https→wss).
  static final String wsUrl = '${baseUrl.replaceFirst('http', 'ws')}/ws';

  static const String login = '/api/v1/auth/login';
  static const String register = '/api/v1/auth/register';
  static const String registerShop = '/api/v1/auth/register-shop';
  static const String refresh = '/api/v1/auth/refresh';

  // Organisations & profile
  static String organisation(String code) => '/api/v1/organisations/${Uri.encodeComponent(code)}';
  static const String me = '/api/v1/users/me';
  static const String mePassword = '/api/v1/users/me/password';
  static const String meOrganisations = '/api/v1/users/me/organisations';
  static String shop(String shopId) => '/api/v1/shops/$shopId';

  static const String shops = '/api/v1/shops';
  static String shopMenu(String shopId) => '/api/v1/shops/$shopId/menu';
  static String createMenuItem(String shopId) => '/api/v1/shops/$shopId/menu-items';
  static String menuItem(String itemId) => '/api/v1/menu-items/$itemId';
  static String updateStock(String itemId) => '/api/v1/menu-items/$itemId/stock';

  static String shopOrders(String shopId) => '/api/v1/shops/$shopId/orders';
  static String orderById(String id) => '/api/v1/orders/$id';
  static String updateOrderStatus(String id) => '/api/v1/orders/$id/status';
  static String rejectOrder(String id) => '/api/v1/orders/$id/reject';

  static String shopEarnings(String shopId) => '/api/v1/shops/$shopId/earnings';
}
