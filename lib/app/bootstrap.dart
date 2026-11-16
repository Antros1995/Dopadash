import '../core/config/app_config.dart';
import '../core/storage/auth_session_store.dart';
import '../core/storage/key_value_store_factory.dart';
import '../data/services/supabase_client_service.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/calendar/data/calendar_repository.dart';
import '../features/fitbit/data/fitbit_repository.dart';
import '../features/markets/data/market_repository.dart';
import '../features/routines/data/routine_repository.dart';
import '../features/tasks/data/task_repository.dart';
import 'dependencies.dart';

abstract final class AppBootstrap {
  static Future<AppDependencies> initialize() async {
    final config = AppConfig.fromEnvironment();
    final sessionStore = AuthSessionStore(createKeyValueStore());
    final clientService = SupabaseClientService.create(
      config: config,
      sessionStore: sessionStore,
    );
    try {
      final authBootstrap = await clientService.initialize();
      final authRepository = SupabaseAuthRepository(
        clientService.client,
        authRedirectUrl: config.authRedirectUrl,
      );
      return AppDependencies(
        supabaseClientService: clientService,
        authController: AuthController(
          repository: authRepository,
          initialPasswordRecovery: authBootstrap.isPasswordRecovery,
        ),
        routineRepository: SupabaseRoutineRepository(clientService.client),
        calendarRepository: PersonalAgentCalendarRepository(
          supabase: clientService.client,
          apiBaseUrl: config.personalAgentApiUrl,
        ),
        fitbitRepository: PersonalAgentFitbitRepository(
          supabase: clientService.client,
          apiBaseUrl: config.personalAgentApiUrl,
        ),
        marketRepository: PersonalAgentMarketRepository(
          supabase: clientService.client,
          apiBaseUrl: config.personalAgentApiUrl,
        ),
        taskRepository: SupabaseTaskRepository(clientService.client),
      );
    } on Object {
      await clientService.dispose();
      rethrow;
    }
  }
}
