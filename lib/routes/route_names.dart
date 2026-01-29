/// Route name constants for the app
/// Centralizes all navigation route names
class RouteNames {
  // Prevent instantiation
  RouteNames._();

  // Auth routes
  static const String login = '/login';
  static const String signup = '/signup';

  // Main app routes
  static const String main = '/main';

  // Session routes
  static const String sessions = '/sessions';
  static const String sessionDetail = '/session-detail';
  static const String activeWorkout = '/active-workout';
  static const String planWorkout = '/plan-workout';

  // Exercise routes
  static const String exercises = '/exercises';
  static const String exerciseDetail = '/exercise-detail';
  static const String addExercise = '/add-exercise';
  static const String logSets = '/log-sets';

  // Profile routes
  static const String editProfile = '/edit-profile';

  // Settings routes
  static const String settings = '/settings';

  // Goals routes
  static const String goals = '/goals';

  // Body metrics routes
  static const String bodyMetrics = '/body-metrics';

  // Analytics routes
  static const String analytics = '/analytics';

  // Chat routes
  static const String chatList = '/chat';
  static const String chatConversation = '/chat/conversation';
  static const String workoutPlanForm = '/chat/workout-plan';
  static const String mealPlanForm = '/chat/meal-plan';

  // Community routes
  static const String community = '/community';

  // Template routes
  static const String templates = '/templates';

  // Program routes
  static const String programs = '/programs';
  static const String programDetail = '/program-detail';
  static const String programWorkout = '/program-workout';

  // Onboarding routes
  static const String onboarding = '/onboarding';

  // Achievement routes
  static const String achievements = '/achievements';

  // Running routes
  static const String activeRun = '/active-run';
  static const String runHistory = '/run-history';
  static const String runDetail = '/run-detail';

  // Nutrition routes
  static const String nutrition = '/nutrition';
  static const String nutritionFoodSearch = '/nutrition/food-search';
  static const String nutritionGoals = '/nutrition/goals';

  // Friends routes
  static const String friends = '/friends';
  static const String friendProfile = '/friend-profile';

  // Messages routes
  static const String messages = '/messages';
  static const String conversation = '/conversation';

  // Initial route (shown when app starts)
  static const String initial = login;
}
