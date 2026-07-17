import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _keyProtocol = 'vpn_protocol';
  static const _keyAutoConnect = 'auto_connect';
  static const _keyKillSwitch = 'kill_switch';
  static const _keyDarkMode = 'dark_mode';
  static const _keyLastServerId = 'last_server_id';
  static const _keyFavorites = 'favorite_servers';
  static const _keyPrivateKey = 'wireguard_private_key';
  static const _keyAuthToken = 'auth_token';
  static const _keyUserEmail = 'user_email';
  static const _keyAutoReconnect = 'auto_reconnect';
  static const _keyOnboardingComplete = 'onboarding_complete';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get protocol => _prefs?.getString(_keyProtocol) ?? 'WireGuard';
  Future<void> setProtocol(String value) async => (await _getPrefs()).setString(_keyProtocol, value);

  bool get autoConnect => _prefs?.getBool(_keyAutoConnect) ?? false;
  Future<void> setAutoConnect(bool value) async => (await _getPrefs()).setBool(_keyAutoConnect, value);

  bool get killSwitch => _prefs?.getBool(_keyKillSwitch) ?? false;
  Future<void> setKillSwitch(bool value) async => (await _getPrefs()).setBool(_keyKillSwitch, value);

  bool get darkMode => _prefs?.getBool(_keyDarkMode) ?? true;
  Future<void> setDarkMode(bool value) async => (await _getPrefs()).setBool(_keyDarkMode, value);

  bool get autoReconnect => _prefs?.getBool(_keyAutoReconnect) ?? false;
  Future<void> setAutoReconnect(bool value) async => (await _getPrefs()).setBool(_keyAutoReconnect, value);

  String? get lastServerId => _prefs?.getString(_keyLastServerId);
  Future<void> setLastServerId(String? value) async {
    final p = await _getPrefs();
    if (value != null) {
      p.setString(_keyLastServerId, value);
    } else {
      p.remove(_keyLastServerId);
    }
  }

  List<String> get favorites => _prefs?.getStringList(_keyFavorites) ?? [];
  Future<void> setFavorites(List<String> value) async => (await _getPrefs()).setStringList(_keyFavorites, value);

  String? get privateKey => _prefs?.getString(_keyPrivateKey);
  Future<void> setPrivateKey(String? value) async {
    final p = await _getPrefs();
    if (value != null) {
      p.setString(_keyPrivateKey, value);
    } else {
      p.remove(_keyPrivateKey);
    }
  }

  int getInt(String key) => _prefs?.getInt(key) ?? 0;
  Future<void> setInt(String key, int value) async => (await _getPrefs()).setInt(key, value);

  String? getString(String key) => _prefs?.getString(key);
  Future<void> setString(String key, String value) async => (await _getPrefs()).setString(key, value);

  List<String>? getStringList(String key) => _prefs?.getStringList(key);
  Future<void> setStringList(String key, List<String> value) async => (await _getPrefs()).setStringList(key, value);

  String? get authToken => _prefs?.getString(_keyAuthToken);
  Future<void> setAuthToken(String? value) async {
    final p = await _getPrefs();
    if (value != null) {
      p.setString(_keyAuthToken, value);
    } else {
      p.remove(_keyAuthToken);
    }
  }

  Future<void> clearAuthToken() async {
    (await _getPrefs()).remove(_keyAuthToken);
  }

  String? get userEmail => _prefs?.getString(_keyUserEmail);
  Future<void> setUserEmail(String? value) async {
    final p = await _getPrefs();
    if (value != null) {
      p.setString(_keyUserEmail, value);
    } else {
      p.remove(_keyUserEmail);
    }
  }

  bool get onboardingComplete => _prefs?.getBool(_keyOnboardingComplete) ?? false;
  Future<void> setOnboardingComplete(bool value) async => (await _getPrefs()).setBool(_keyOnboardingComplete, value);

  Future<void> addFavorite(String serverId) async {
    final list = favorites;
    if (!list.contains(serverId)) {
      list.add(serverId);
      await setFavorites(list);
    }
  }

  Future<void> removeFavorite(String serverId) async {
    final list = favorites;
    list.remove(serverId);
    await setFavorites(list);
  }
}
