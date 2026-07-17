class AppConfig {
  static const String appName = 'BULB VPN';
  static const String appVersion = '1.0.0';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.bulbvpn.com/v1',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration serverRefreshInterval = Duration(minutes: 5);

  static const int freeServerLimit = 3;
  static const int freeDataLimitMB = 500;
  static const Duration freeSessionLimit = Duration(hours: 1);

  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-App-Version': appVersion,
  };
}
