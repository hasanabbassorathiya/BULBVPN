import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../models/imported_server.dart';
import '../providers/vpn_provider.dart';
import '../screens/import_server_screen.dart';
import '../services/v2ray_config_parser.dart';
import '../widgets/components/app_badge.dart';
import '../widgets/components/app_text_field.dart';
import '../utils/app_utils.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  String _debouncedQuery = '';
  final Set<String> _expandedCountries = {};
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _debouncedQuery = _searchController.text;
      });
    });
  }

  Map<String, List<VpnServer>> _groupByCountry(List<VpnServer> servers) {
    final map = <String, List<VpnServer>>{};
    for (final server in servers) {
      map.putIfAbsent(server.country, () => []).add(server);
    }
    final countries = map.keys.toList()..sort((a, b) => a.compareTo(b));
    final sorted = <String, List<VpnServer>>{};
    for (final c in countries) {
      final list = map[c]!..sort((a, b) => a.ping.compareTo(b.ping));
      sorted[c] = list;
    }
    return sorted;
  }

  List<VpnServer> _getFilteredServers(VPNProvider vpn) {
    List<VpnServer> servers = List.from(vpn.servers);

    switch (vpn.serverFilter) {
      case ServerFilter.favorites:
        servers = servers.where((s) => vpn.isFavorite(s.id)).toList();
        break;
      case ServerFilter.streaming:
        break;
      case ServerFilter.gaming:
        servers = List.from(servers)..sort((a, b) => a.ping.compareTo(b.ping));
        break;
      case ServerFilter.lowPing:
        servers = List.from(servers)..sort((a, b) => a.ping.compareTo(b.ping));
        break;
      default:
        break;
    }

    if (_debouncedQuery.isNotEmpty) {
      final q = _debouncedQuery.toLowerCase();
      servers = servers.where((s) =>
        s.name.toLowerCase().contains(q) ||
        s.country.toLowerCase().contains(q) ||
        s.countryCode.toLowerCase().contains(q)
      ).toList();
    }

    return servers;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;

    return Container(
      decoration: BoxDecoration(gradient: colors.bgGradient),
      child: SafeArea(
        child: Consumer<VPNProvider>(
          builder: (context, vpn, _) {
            return Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(colors, horizontalPad, vpn),
                    _buildCategoryTabs(colors, horizontalPad, vpn),
                    if (_selectedTab != 2) _buildSearchBar(colors, horizontalPad),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: _selectedTab == 2
                          ? _buildImportedServerList(colors, vpn)
                          : _buildServerList(colors, vpn, _groupByCountry(_getFilteredServers(vpn))),
                    ),
                  ],
                ),
                if (_selectedTab != 2 && vpn.selectedServer != null && !vpn.isConnected && !vpn.isConnecting)
                  _buildQuickConnectButton(colors, horizontalPad, vpn),
                if (_selectedTab == 2 && !vpn.isConnected && !vpn.isConnecting)
                  _buildImportFAB(colors, horizontalPad),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(AppSemanticColors colors, double horizontalPad, VPNProvider vpn) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, 12, horizontalPad, 12),
      child: Row(
        children: [
          Text(
            'Servers',
            style: AppTypography.displayMedium(context).copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppBadge(
            label: '${vpn.servers.length}',
            color: AppColors.primary,
            size: AppBadgeSize.small,
          ),
          const Spacer(),
          Consumer<VPNProvider>(
            builder: (context, vpn, _) {
              return GestureDetector(
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await vpn.refreshServers();
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Servers refreshed'), duration: Duration(seconds: 1)),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: Icon(Icons.refresh, color: colors.textMuted, size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(
    AppSemanticColors colors,
    double horizontalPad,
    VPNProvider vpn,
  ) {
    final favCount = vpn.favoriteServers.length;
    final myCount = vpn.importedServers.length;
    final tabs = [
      _TabData('All', Icons.apps, 0),
      _TabData('★ Favorites', Icons.star, 1, count: favCount),
      _TabData('My Servers', Icons.dns, 2, count: myCount),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPad),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isSelected = _selectedTab == tab.filter;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedTab = tab.filter);
              if (tab.filter == 0) vpn.setServerFilter(ServerFilter.all);
              if (tab.filter == 1) vpn.setServerFilter(ServerFilter.favorites);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected ? AppColors.connectedGradient : null,
                color: isSelected ? null : colors.card,
                borderRadius: AppRadius.pillAll,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : colors.cardBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tab.icon, size: 14, color: isSelected ? colors.surface : colors.textMuted),
                  const SizedBox(width: 5),
                  Text(
                    tab.label,
                    style: AppTypography.labelMedium(context).copyWith(
                      color: isSelected ? colors.surface : colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (tab.count != null && tab.count! > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colors.surface.withValues(alpha: 0.25)
                            : colors.cardBorder,
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Text(
                        '${tab.count}',
                        style: AppTypography.labelSmall(context).copyWith(
                          color: isSelected ? colors.surface : colors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(AppSemanticColors colors, double horizontalPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, AppSpacing.sm, horizontalPad, 0),
      child: Semantics(
        label: 'Search servers',
        child: AppTextField(
          controller: _searchController,
          hint: 'Search servers...',
          prefixIcon: Icons.search,
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _debouncedQuery = '');
                  },
                  child: Icon(Icons.close, size: 18, color: colors.textMuted),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildServerList(
    AppSemanticColors colors,
    VPNProvider vpn,
    Map<String, List<VpnServer>> grouped,
  ) {
    if (!vpn.isInitialized && grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: AppSpacing.lg),
            Text('Loading servers...', style: AppTypography.bodyLarge(context).copyWith(color: colors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Text('Fetching from VPN Gate', style: AppTypography.labelSmall(context).copyWith(color: colors.textMuted)),
          ],
        ),
      );
    }

    if (vpn.isInitialized && grouped.isEmpty) {
      if (vpn.serverFilter == ServerFilter.favorites && _debouncedQuery.isEmpty) {
        return _buildEmptyState(
          colors,
          icon: Icons.star_border,
          title: 'No favorite servers yet',
          subtitle: 'Tap the star on any server to add it to your favorites',
        );
      }
      if (_debouncedQuery.isNotEmpty) {
        return _buildEmptyState(
          colors,
          icon: Icons.search_off,
          title: 'No servers match your search',
          subtitle: 'Try a different search term',
        );
      }
      return _buildEmptyState(
        colors,
        icon: Icons.cloud_off,
        title: 'No servers found',
        subtitle: 'Check your internet connection',
        actionLabel: 'Retry',
        onAction: () => vpn.refreshServers(),
      );
    }

    final defaultExpanded = vpn.serverFilter == ServerFilter.favorites ||
        vpn.serverFilter == ServerFilter.lowPing ||
        vpn.serverFilter == ServerFilter.streaming ||
        vpn.serverFilter == ServerFilter.gaming;

    if (defaultExpanded && _expandedCountries.isEmpty) {
      _expandedCountries.addAll(grouped.keys);
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: colors.card,
      onRefresh: () => vpn.refreshServers(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final country = grouped.keys.elementAt(index);
          final countryServers = grouped[country]!;
          final flag = countryServers.first.flag;
          final isExpanded = _expandedCountries.contains(country);

          return _buildCountrySection(
            colors,
            vpn,
            country: country,
            flag: flag,
            servers: countryServers,
            isExpanded: isExpanded,
            onToggle: () {
              setState(() {
                if (isExpanded) {
                  _expandedCountries.remove(country);
                } else {
                  _expandedCountries.add(country);
                }
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(
    AppSemanticColors colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colors.textMuted, size: 56),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              style: AppTypography.headlineMedium(context).copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              style: AppTypography.bodyMedium(context).copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Text(
                    actionLabel,
                    style: AppTypography.labelLarge(context).copyWith(color: colors.surface),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCountrySection(
    AppSemanticColors colors,
    VPNProvider vpn, {
    required String country,
    required String flag,
    required List<VpnServer> servers,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(AppRadius.md),
                bottom: isExpanded ? Radius.zero : const Radius.circular(AppRadius.md),
              ),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Row(
              children: [
                Text(flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    country,
                    style: AppTypography.titleMedium(context).copyWith(color: colors.textPrimary),
                  ),
                ),
                AppBadge(
                  label: '${servers.length}',
                  color: AppColors.primary,
                  size: AppBadgeSize.small,
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, color: colors.textMuted, size: 20),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  decoration: BoxDecoration(
                    color: colors.card.withValues(alpha: 0.5),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(AppRadius.md),
                    ),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: servers.map((server) => _buildServerItem(
                      colors,
                      vpn,
                      server,
                      isFirst: server == servers.first,
                      isLast: server == servers.last,
                    )).toList(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildServerItem(
    AppSemanticColors colors,
    VPNProvider vpn,
    VpnServer server, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isSelected = vpn.selectedServer?.id == server.id;
    final isFav = vpn.isFavorite(server.id);
    final loadPct = (server.load * 100).round();
    final loadColor = loadPct < 50
        ? AppColors.connected
        : loadPct < 80
            ? AppColors.warning
            : AppColors.disconnected;
    final ping = pingColor(server.ping);

    return GestureDetector(
      onTap: () {
        vpn.selectServer(server);
        vpn.connect();
      },
      child: Semantics(
        label: '${server.name}, ${server.country}, ${server.ping} milliseconds',
        button: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
            border: Border(
              top: isFirst ? BorderSide.none : BorderSide(color: colors.cardBorder.withValues(alpha: 0.4)),
            ),
          ),
          child: Row(
            children: [
              Text(server.flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: AppTypography.bodyLarge(context).copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: ping,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${server.ping}ms',
                          style: AppTypography.labelSmall(context).copyWith(
                            color: ping,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: server.load,
                              minHeight: 3,
                              backgroundColor: colors.cardBorder.withValues(alpha: 0.5),
                              valueColor: AlwaysStoppedAnimation<Color>(loadColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$loadPct%',
                          style: AppTypography.labelSmall(context).copyWith(
                            color: colors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: () => vpn.toggleFavorite(server.id),
                child: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  color: isFav ? AppColors.warning : colors.textMuted,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickConnectButton(
    AppSemanticColors colors,
    double horizontalPad,
    VPNProvider vpn,
  ) {
    final server = vpn.selectedServer;
    if (server == null) return const SizedBox.shrink();

    return Positioned(
      left: horizontalPad,
      right: horizontalPad,
      bottom: 16,
      child: GestureDetector(
        onTap: () => vpn.connect(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: AppColors.connectedGradient,
            borderRadius: AppRadius.lgAll,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bolt, color: Colors.white, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Connect to ${server.name}',
                style: AppTypography.labelLarge(context).copyWith(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportedServerList(AppSemanticColors colors, VPNProvider vpn) {
    final servers = vpn.importedServers;
    if (servers.isEmpty) {
      return _buildEmptyState(
        colors,
        icon: Icons.dns_outlined,
        title: 'No servers imported',
        subtitle: 'Tap + to add your own V2Ray/Xray servers',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        return _buildImportedServerCard(colors, vpn, server);
      },
    );
  }

  Widget _buildImportedServerCard(AppSemanticColors colors, VPNProvider vpn, ImportedServer server) {
    final isSelected = vpn.selectedImportedServer?.id == server.id;
    final protoColor = {
      V2RayProtocol.vmess: const Color(0xFF4FC3F7),
      V2RayProtocol.vless: const Color(0xFF66BB6A),
      V2RayProtocol.trojan: const Color(0xFFEF5350),
      V2RayProtocol.shadowsocks: const Color(0xFFFFA726),
      V2RayProtocol.unknown: colors.textMuted,
    }[server.protocol] ?? colors.textMuted;

    return GestureDetector(
      onTap: () {
        vpn.selectImportedServer(server);
        vpn.connectV2Ray(server);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : colors.card,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: isSelected ? AppColors.primary.withValues(alpha: 0.3) : colors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: protoColor.withValues(alpha: 0.15),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                server.protocol.name.toUpperCase(),
                style: AppTypography.labelSmall(context).copyWith(
                  color: protoColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: AppTypography.bodyLarge(context).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${server.address}:${server.port}',
                    style: AppTypography.labelSmall(context).copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => vpn.removeImportedServer(server.id),
              child: Icon(Icons.delete_outline, color: colors.textMuted, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportFAB(AppSemanticColors colors, double horizontalPad) {
    return Positioned(
      right: horizontalPad,
      bottom: 20,
      child: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ImportServerScreen()),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _TabData {
  final String label;
  final IconData icon;
  final int filter;
  final int? count;
  const _TabData(this.label, this.icon, this.filter, {this.count});
}
