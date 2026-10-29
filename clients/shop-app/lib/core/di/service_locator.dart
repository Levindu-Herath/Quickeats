import 'package:get_it/get_it.dart';
import 'package:quickeats_shop/core/network/api_client.dart';
import 'package:quickeats_shop/core/network/ws_client.dart';
import 'package:quickeats_shop/services/auth_service.dart';
import 'package:quickeats_shop/services/order_service.dart';
import 'package:quickeats_shop/services/menu_service.dart';
import 'package:quickeats_shop/services/account_service.dart';
import 'package:quickeats_shop/services/earnings_service.dart';
import 'package:quickeats_shop/viewmodels/earnings_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/settings_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/auth_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/order_queue_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/menu_viewmodel.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // ── Singletons (created once, live forever) ──
  
  // Auth service — must be initialized before anything else
  final authService = AuthService();
  await authService.init();
  getIt.registerSingleton<AuthService>(authService);

  // API client (depends on auth for interceptor)
  getIt.registerSingleton<ApiClient>(ApiClient(authService: authService));

  // WebSocket client
  getIt.registerSingleton<WSClient>(WSClient());

  // ── Services (stateless, singleton is fine) ──
  getIt.registerSingleton<OrderService>(OrderService(apiClient: getIt<ApiClient>()));
  getIt.registerSingleton<MenuService>(MenuService(apiClient: getIt<ApiClient>()));
  getIt.registerSingleton<AccountService>(AccountService(apiClient: getIt<ApiClient>()));
  getIt.registerSingleton<EarningsService>(EarningsService(apiClient: getIt<ApiClient>()));

  // ── ViewModels (factories — new instance each time, disposed with the widget) ──
  getIt.registerFactory<AuthViewModel>(() => AuthViewModel(authService: getIt<AuthService>()));

  getIt.registerFactory<OrderQueueViewModel>(() => OrderQueueViewModel(
    orderService: getIt<OrderService>(),
    authService: getIt<AuthService>(),
    wsClient: getIt<WSClient>(),
  ));

  getIt.registerFactory<MenuViewModel>(() => MenuViewModel(
    menuService: getIt<MenuService>(),
    authService: getIt<AuthService>(),
  ));

  getIt.registerFactory<EarningsViewModel>(() => EarningsViewModel(
    earningsService: getIt<EarningsService>(),
    authService: getIt<AuthService>(),
  ));

  getIt.registerFactory<SettingsViewModel>(() => SettingsViewModel(accountService: getIt<AccountService>()));
}
