import '../data/services/supabase_client_service.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/calendar/data/calendar_repository.dart';
import '../features/fitbit/data/fitbit_repository.dart';
import '../features/markets/data/market_repository.dart';
import '../features/routines/data/routine_repository.dart';
import '../features/tasks/data/task_repository.dart';

class AppDependencies {
  const AppDependencies({
    required this.supabaseClientService,
    required this.authController,
    required this.routineRepository,
    required this.calendarRepository,
    required this.fitbitRepository,
    required this.marketRepository,
    required this.taskRepository,
  });

  final SupabaseClientService supabaseClientService;
  final AuthController authController;
  final RoutineRepository routineRepository;
  final CalendarRepository calendarRepository;
  final FitbitRepository fitbitRepository;
  final MarketRepository marketRepository;
  final TaskRepository taskRepository;

  Future<void> dispose() async {
    authController.dispose();
    calendarRepository.dispose();
    fitbitRepository.dispose();
    marketRepository.dispose();
    await supabaseClientService.dispose();
  }
}
