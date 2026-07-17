import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/imported_server.dart';
import '../models/subscription.dart';

class ServerStorageService {
  static const String _key = 'imported_servers';

  Future<List<ImportedServer>> loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => ImportedServer.fromJson(e)).toList();
  }

  Future<void> saveServers(List<ImportedServer> servers) async {
    final prefs = await SharedPreferences.getInstance();
    final json = servers.map((s) => s.toJson()).toList();
    await prefs.setString(_key, jsonEncode(json));
  }

  Future<void> addServer(ImportedServer server) async {
    final servers = await loadServers();
    servers.add(server);
    await saveServers(servers);
  }

  Future<void> removeServer(String id) async {
    final servers = await loadServers();
    servers.removeWhere((s) => s.id == id);
    await saveServers(servers);
  }

  Future<void> toggleFavorite(String id) async {
    final servers = await loadServers();
    final index = servers.indexWhere((s) => s.id == id);
    if (index != -1) {
      servers[index] = servers[index].copyWith(isFavorite: !servers[index].isFavorite);
      await saveServers(servers);
    }
  }

  static const String _subscriptionsKey = 'subscriptions';

  Future<List<Subscription>> loadSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_subscriptionsKey);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => Subscription.fromJson(e)).toList();
  }

  Future<void> saveSubscriptions(List<Subscription> subscriptions) async {
    final prefs = await SharedPreferences.getInstance();
    final json = subscriptions.map((s) => s.toJson()).toList();
    await prefs.setString(_subscriptionsKey, jsonEncode(json));
  }

  Future<void> addSubscription(Subscription subscription) async {
    final subscriptions = await loadSubscriptions();
    subscriptions.add(subscription);
    await saveSubscriptions(subscriptions);
  }

  Future<void> removeSubscription(String id) async {
    final subscriptions = await loadSubscriptions();
    subscriptions.removeWhere((s) => s.id == id);
    await saveSubscriptions(subscriptions);
  }

  Future<void> updateSubscription(Subscription subscription) async {
    final subscriptions = await loadSubscriptions();
    final index = subscriptions.indexWhere((s) => s.id == subscription.id);
    if (index != -1) {
      subscriptions[index] = subscription;
      await saveSubscriptions(subscriptions);
    }
  }
}
