import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_shop/core/constants/app_colors.dart';
import 'package:quickeats_shop/core/di/service_locator.dart';
import 'package:quickeats_shop/core/router/app_router.dart';
import 'package:quickeats_shop/services/auth_service.dart';
import 'package:quickeats_shop/viewmodels/auth_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/order_queue_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/menu_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/earnings_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/settings_viewmodel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupServiceLocator();
  runApp(const QuickEatsShopApp());
}

class QuickEatsShopApp extends StatelessWidget {
  const QuickEatsShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: getIt<AuthService>()),
        ChangeNotifierProvider(create: (_) => getIt<AuthViewModel>()),
        ChangeNotifierProvider(create: (_) => getIt<OrderQueueViewModel>()),
        ChangeNotifierProvider(create: (_) => getIt<MenuViewModel>()),
        ChangeNotifierProvider(create: (_) => getIt<EarningsViewModel>()),
        ChangeNotifierProvider(create: (_) => getIt<SettingsViewModel>()),
      ],
      child: MaterialApp.router(
        title: 'QuickEats Shop',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: AppColors.primary,
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.surface,
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
          ),
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
