import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../models/imported_server.dart';
import '../models/subscription.dart';
import '../providers/vpn_provider.dart';
import '../screens/import_server_screen.dart';
import '../services/v2ray_config_parser.dart';
import '../widgets/components/app_badge.dart';
import '../widgets/components/app_text_field.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  String _debouncedQuery = '';
  int _selectedTab = 0;
  bool _isPinging = false;
  int _pingProgress = 0;
  int _pingTotal = 0;

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

  List<ImportedServer> _getFilteredServers(VPNProvider vpn) {
    List<ImportedServer> servers = List.from(vpn.importedServers);

    if (_selectedTab == 1) {
      servers = servers.where((s) => vpn.isFavoriteServer(s.id)).toList();
    }

    if (_debouncedQuery.isNotEmpty) {
      final q = _debouncedQuery.toLowerCase();
      servers = servers.where((s) =>
        s.name.toLowerCase().contains(q) ||
        s.address.toLowerCase().contains(q) ||
        s.protocol.name.toLowerCase().contains(q)
      ).toList();
    }

    return servers;
  }

  Future<void> _handlePingAll(VPNProvider vpn) async {
    if (_isPinging) return;
    final servers = vpn.importedServers;
    if (servers.isEmpty) return;

    setState(() {
      _isPinging = true;
      _pingProgress = 0;
      _pingTotal = servers.length;
    });

    for (int i = 0; i < servers.length; i++) {
      await vpn.pingServer(servers[i]);
      if (mounted) {
        setState(() {
          _pingProgress = i + 1;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isPinging = false;
      });
    }
  }

  Color _pingColor(int ping) {
    if (ping <= 0) return Colors.grey;
    if (ping < 100) return const Color(0xFF66BB6A);
    if (ping <= 300) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }

  void _showAddSubscriptionDialog(VPNProvider vpn) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppSemanticColors.of(context).card,
          title: Text('Add Subscription', style: AppTypography.titleLarge(context)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: nameController,
                hint: 'Name',
                prefixIcon: Icons.label_outline,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: urlController,
                hint: 'Subscription URL',
                prefixIcon: Icons.link,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppSemanticColors.of(context).textMuted)),
            ),
            TextButton(
              onPressed: loading ? null : () async {
                if (nameController.text.trim().isEmpty || urlController.text.trim().isEmpty) return;
                setDialogState(() => loading = true);
                final success = await vpn.addSubscription(
                  urlController.text.trim(),
                  nameController.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted && !success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to add subscription')),
                  );
                }
              },
              child: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Add', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSubscriptionDialog(VPNProvider vpn, Subscription sub) {
    final nameController = TextEditingController(text: sub.name);
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppSemanticColors.of(context).card,
          title: Text('Edit Subscription', style: AppTypography.titleLarge(context)),
          content: AppTextField(
            controller: nameController,
            hint: 'Name',
            prefixIcon: Icons.label_outline,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppSemanticColors.of(context).textMuted)),
            ),
            TextButton(
              onPressed: loading ? null : () async {
                if (nameController.text.trim().isEmpty) return;
                setDialogState(() => loading = true);
                await vpn.editSubscription(sub.id, nameController.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Save', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
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
                    if (_selectedTab < 2) _buildSearchBar(colors, horizontalPad),
                    if (_isPinging) _buildPingProgress(colors, horizontalPad),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: _selectedTab == 2
                          ? _buildSubscriptionsList(colors, vpn)
                          : _buildServerList(colors, vpn),
                    ),
                  ],
                ),
                if (vpn.selectedImportedServer != null && !vpn.isConnected && !vpn.isConnecting && _selectedTab < 2)
                  _buildQuickConnectButton(colors, horizontalPad, vpn),
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
            label: '${vpn.importedServers.length}',
            color: AppColors.primary,
            size: AppBadgeSize.small,
          ),
          const Spacer(),
          if (_selectedTab < 2 && vpn.importedServers.isNotEmpty)
            GestureDetector(
              onTap: _isPinging ? null : () => _handlePingAll(vpn),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isPinging ? colors.cardBorder : colors.card,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: colors.cardBorder),
                ),
                child: _isPinging
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: _pingTotal > 0 ? _pingProgress / _pingTotal : null,
                          color: AppColors.primary,
                        ),
                      )
                    : Icon(Icons.speed, color: colors.textMuted, size: 20),
              ),
            ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImportServerScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: colors.cardBorder),
              ),
              child: Icon(Icons.add, color: colors.textMuted, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPingProgress(AppSemanticColors colors, double horizontalPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: _pingTotal > 0 ? _pingProgress / _pingTotal : null,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              'Pinging servers... $_pingProgress/$_pingTotal',
              style: AppTypography.labelMedium(context).copyWith(
                color: colors.textPrimary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(
    AppSemanticColors colors,
    double horizontalPad,
    VPNProvider vpn,
  ) {
    final favCount = vpn.importedServers.where((s) => vpn.isFavoriteServer(s.id)).length;
    final myCount = vpn.importedServers.length;
    final subCount = vpn.subscriptions.length;
    final tabs = [
      _TabData('All', Icons.apps, 0, count: myCount),
      _TabData('★ Favorites', Icons.star, 1, count: favCount),
      _TabData('Subscriptions', Icons.rss_feed, 2, count: subCount),
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

  Widget _buildServerList(AppSemanticColors colors, VPNProvider vpn) {
    final filtered = _getFilteredServers(vpn);

    if (filtered.isEmpty) {
      if (_selectedTab == 1 && _debouncedQuery.isEmpty) {
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
        icon: Icons.dns_outlined,
        title: 'No servers imported',
        subtitle: 'Tap + to add your own V2Ray/Xray servers',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final server = filtered[index];
        return _buildServerCard(colors, vpn, server);
      },
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

  Widget _buildServerCard(AppSemanticColors colors, VPNProvider vpn, ImportedServer server) {
    final isSelected = vpn.selectedImportedServer?.id == server.id;
    final isFav = vpn.isFavoriteServer(server.id);
    final protoColor = {
      V2RayProtocol.vmess: const Color(0xFF4FC3F7),
      V2RayProtocol.vless: const Color(0xFF66BB6A),
      V2RayProtocol.trojan: const Color(0xFFEF5350),
      V2RayProtocol.shadowsocks: const Color(0xFFFFA726),
      V2RayProtocol.unknown: colors.textMuted,
    }[server.protocol] ?? colors.textMuted;

    final pingMs = server.ping;
    final hasPingResult = pingMs > 0;
    final pingDisplay = hasPingResult ? '${pingMs}ms' : '';
    final pingColor = _pingColor(pingMs);

    return GestureDetector(
      onTap: () {
        vpn.selectImportedServer(server);
        vpn.connect();
      },
      child: Semantics(
        label: '${server.name}, ${server.address}:${server.port}, ping ${hasPingResult ? "$pingMs ms" : "untested"}',
        button: true,
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
              if (hasPingResult) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: pingColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    pingDisplay,
                    style: AppTypography.labelSmall(context).copyWith(
                      color: pingColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              GestureDetector(
                onTap: () => vpn.toggleFavoriteServer(server.id),
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

  Widget _buildSubscriptionsList(AppSemanticColors colors, VPNProvider vpn) {
    final subs = vpn.subscriptions;

    if (subs.isEmpty) {
      return _buildEmptyState(
        colors,
        icon: Icons.rss_feed,
        title: 'No subscriptions',
        subtitle: 'Add a subscription URL to import servers automatically',
        actionLabel: 'Add Subscription',
        onAction: () => _showAddSubscriptionDialog(vpn),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: GestureDetector(
            onTap: () => _showAddSubscriptionDialog(vpn),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: AppColors.primary, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Add Subscription',
                    style: AppTypography.labelLarge(context).copyWith(
                      color: AppColors.primary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: subs.length,
            itemBuilder: (context, index) {
              final sub = subs[index];
              return _buildSubscriptionCard(colors, vpn, sub);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionCard(AppSemanticColors colors, VPNProvider vpn, Subscription sub) {
    final lastUpdatedText = sub.lastUpdated != null
        ? _formatRelativeTime(sub.lastUpdated!)
        : 'Never updated';

    return GestureDetector(
      onLongPress: () => _showSubscriptionActions(vpn, sub),
      child: Semantics(
        label: 'Subscription ${sub.name}, ${sub.serverCount} servers',
        button: true,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: colors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(Icons.rss_feed, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.name,
                      style: AppTypography.bodyLarge(context).copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${sub.serverCount} servers · $lastUpdatedText',
                      style: AppTypography.labelSmall(context).copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub.url,
                      style: AppTypography.labelSmall(context).copyWith(
                        color: colors.textMuted,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showSubscriptionActions(vpn, sub),
                child: Icon(Icons.more_vert, color: colors.textMuted, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubscriptionActions(VPNProvider vpn, Subscription sub) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppSemanticColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppSemanticColors.of(context).textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                sub.name,
                style: AppTypography.titleLarge(context).copyWith(
                  color: AppSemanticColors.of(context).textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: Icon(Icons.edit, color: AppColors.primary),
              title: const Text('Edit Name'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditSubscriptionDialog(vpn, sub);
              },
            ),
            ListTile(
              leading: Icon(Icons.refresh, color: AppColors.primary),
              title: const Text('Refresh'),
              onTap: () async {
                Navigator.pop(ctx);
                await vpn.refreshSubscription(sub.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Color(0xFFEF5350)),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteSubscriptionConfirmation(vpn, sub);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteSubscriptionConfirmation(VPNProvider vpn, Subscription sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppSemanticColors.of(context).card,
        title: Text('Delete Subscription', style: AppTypography.titleLarge(context)),
        content: Text(
          'Delete "${sub.name}"? All servers from this subscription will be removed.',
          style: AppTypography.bodyMedium(context).copyWith(
            color: AppSemanticColors.of(context).textMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppSemanticColors.of(context).textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await vpn.removeSubscription(sub.id);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF5350))),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Widget _buildQuickConnectButton(
    AppSemanticColors colors,
    double horizontalPad,
    VPNProvider vpn,
  ) {
    final server = vpn.selectedImportedServer;
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
}

class _TabData {
  final String label;
  final IconData icon;
  final int filter;
  final int? count;
  const _TabData(this.label, this.icon, this.filter, {this.count});
}
