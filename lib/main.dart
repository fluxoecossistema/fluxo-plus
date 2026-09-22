import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/database/database_factory.dart';
import 'core/update/update_service.dart';
import 'core/security/biometric_service.dart';
import 'core/sync/cloud_backup_gateway.dart';
import 'core/sync/cloud_sync_service.dart';
import 'core/sync/local_backup_store.dart';
import 'core/premium/premium_service.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/accounts/data/account_repository.dart';
import 'features/categories/data/category_repository.dart';
import 'features/goals/data/goal_repository.dart';
import 'features/reports/data/report_repository.dart';
import 'features/transactions/data/transaction_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase(createDatabaseFactory());
  await database.initialize();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  SupabaseClient? supabaseClient;
  if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
    );
    supabaseClient = Supabase.instance.client;
  }

  runApp(
    FluxoApp(
      database: database,
      dashboardRepository: DashboardRepository(database),
      transactionRepository: TransactionRepository(database),
      updateService: UpdateService(),
      accountRepository: AccountRepository(database),
      categoryRepository: CategoryRepository(database),
      goalRepository: GoalRepository(database),
      reportRepository: ReportRepository(database),
      cloudSyncService: CloudSyncService(
        store: DatabaseBackupStore(database),
        gateway: supabaseClient == null
            ? null
            : SupabaseCloudBackupGateway(supabaseClient),
        client: supabaseClient,
      ),
      premiumService: PremiumService(database, supabaseClient),
      biometricService: BiometricService(),
    ),
  );
}
