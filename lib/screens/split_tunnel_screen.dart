import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';
import '../services/storage_service.dart';

class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});
  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  static const _channel = MethodChannel('app.bulbvpn.com/installed_apps');

  final Set<String> _excludedPackages = {};
  String _searchQuery = '';
  List<Map<String, String>> _installedApps = [];
  bool _loading = true;

  static const List<Map<String, String>> _commonApps = [
    {'package': 'com.android.chrome', 'name': 'Chrome'},
    {'package': 'com.whatsapp', 'name': 'WhatsApp'},
    {'package': 'com.instagram.android', 'name': 'Instagram'},
    {'package': 'com.facebook.katana', 'name': 'Facebook'},
    {'package': 'com.twitter.android', 'name': 'X (Twitter)'},
    {'package': 'com.google.android.youtube', 'name': 'YouTube'},
    {'package': 'com.spotify.music', 'name': 'Spotify'},
    {'package': 'com.netflix.mediaclient', 'name': 'Netflix'},
    {'package': 'com.discord', 'name': 'Discord'},
    {'package': 'com.zhiliaoapp.musically', 'name': 'TikTok'},
    {'package': 'com.google.android.gm', 'name': 'Gmail'},
    {'package': 'com.google.android.apps.maps', 'name': 'Google Maps'},
    {'package': 'com.android.phone', 'name': 'Phone'},
    {'package': 'com.android.mms', 'name': 'Messages'},
    {'package': 'com.slack', 'name': 'Slack'},
    {'package': 'com.microsoft.teams', 'name': 'Teams'},
    {'package': 'com.zoom.videomeetings', 'name': 'Zoom'},
    {'package': 'com.amazon.mShop.android.shopping', 'name': 'Amazon'},
    {'package': 'com.ubercab', 'name': 'Uber'},
    {'package': 'com.grabtaxi.passenger', 'name': 'Grab'},
    {'package': 'org.mozilla.firefox', 'name': 'Firefox'},
    {'package': 'com.opera.browser', 'name': 'Opera'},
    {'package': 'com.brave.browser', 'name': 'Brave'},
    {'package': 'com.viber.voip', 'name': 'Viber'},
    {'package': 'com.skype.raider', 'name': 'Skype'},
    {'package': 'com.tencent.mm', 'name': 'WeChat'},
    {'package': 'jp.naver.line.android', 'name': 'LINE'},
    {'package': 'com.google.android.apps.nbu.files', 'name': 'Files'},
    {'package': 'com.google.android.apps.photos', 'name': 'Google Photos'},
    {'package': 'com.google.android.youtube.music', 'name': 'YouTube Music'},
    {'package': 'com.amazon.avod', 'name': 'Prime Video'},
    {'package': 'com.disney.disneyplus', 'name': 'Disney+'},
    {'package': 'com.hbo.hbonow', 'name': 'HBO Max'},
    {'package': 'com.peacocktv.peacockandroid', 'name': 'Peacock'},
    {'package': 'com.pandora.android', 'name': 'Pandora'},
    {'package': 'com.soundcloud.android', 'name': 'SoundCloud'},
    {'package': 'com.reddit.frontpage', 'name': 'Reddit'},
    {'package': 'com.quora.android', 'name': 'Quora'},
    {'package': 'com.medium.reader', 'name': 'Medium'},
    {'package': 'com.flipkart.android', 'name': 'Flipkart'},
    {'package': 'com.snapchat.android', 'name': 'Snapchat'},
    {'package': 'com.pinterest', 'name': 'Pinterest'},
    {'package': 'com.linkedin.android', 'name': 'LinkedIn'},
    {'package': 'com.ebay.mobile', 'name': 'eBay'},
    {'package': 'com.shopee.id', 'name': 'Shopee'},
    {'package': 'com.lazada.android', 'name': 'Lazada'},
    {'package': 'com.tiktok.lite', 'name': 'TikTok Lite'},
    {'package': 'com.instagram.lite', 'name': 'Instagram Lite'},
    {'package': 'com.facebook.lite', 'name': 'Facebook Lite'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedSelections();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true);

    try {
      final result = await _channel.invokeMethod('getInstalledApps');
      if (result != null && result is List && result.isNotEmpty) {
        _installedApps = result.map<Map<String, String>>((app) {
          return {
            'name': app['name']?.toString() ?? '',
            'package': app['package']?.toString() ?? '',
          };
        }).where((app) => app['name']!.isNotEmpty && app['package']!.isNotEmpty).toList();
      } else {
        _installedApps = List.from(_commonApps);
      }
    } catch (e) {
      _installedApps = List.from(_commonApps);
    }

    _installedApps.sort((a, b) => a['name']!.compareTo(b['name']!));

    if (mounted) setState(() => _loading = false);
  }

  void _loadSavedSelections() {
    final saved = StorageService().getStringList('bypass_packages') ?? [];
    setState(() {
      _excludedPackages.addAll(saved);
    });
  }

  Future<void> _saveSelections() async {
    final packages = _excludedPackages.toList();
    await StorageService().setStringList('bypass_packages', packages);

    if (!mounted) return;
    final vpn = context.read<VPNProvider>();
    vpn.setBypassPackages(packages);

    if (vpn.isConnected) {
      await vpn.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      await vpn.connect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('VPN reconnected with updated split tunneling'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  List<Map<String, String>> get _filteredApps {
    if (_searchQuery.isEmpty) return _installedApps;
    final q = _searchQuery.toLowerCase();
    return _installedApps.where((a) =>
      a['name']!.toLowerCase().contains(q) ||
      a['package']!.toLowerCase().contains(q)
    ).toList();
  }

  void _selectAll() {
    setState(() {
      for (final app in _filteredApps) {
        _excludedPackages.add(app['package']!);
      }
    });
    _saveSelections();
  }

  void _deselectAll() {
    setState(() {
      for (final app in _filteredApps) {
        _excludedPackages.remove(app['package']!);
      }
    });
    _saveSelections();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: colors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(colors),
              _buildSearchBar(colors),
              _buildInfoBar(colors),
              _buildActionButtons(colors),
              Expanded(child: _buildAppList(colors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios, color: colors.textMuted),
        ),
        Expanded(
          child: Text(
            'Split Tunneling',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 48),
      ]),
    );
  }

  Widget _buildSearchBar(AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search apps...',
          hintStyle: TextStyle(color: colors.textMuted),
          prefixIcon: Icon(Icons.search, color: colors.textMuted),
          filled: true,
          fillColor: colors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBar(AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        Icon(Icons.info_outline, color: colors.textMuted, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${_excludedPackages.length} apps excluded from VPN',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ),
      ]),
    );
  }

  Widget _buildActionButtons(AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _selectAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: BorderSide(color: AppColors.warning.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: const Text('Select All', style: TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: _deselectAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textMuted,
              side: BorderSide(color: colors.textMuted.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: const Text('Deselect All', style: TextStyle(fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  Widget _buildAppList(AppSemanticColors colors) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.warning),
      );
    }

    final apps = _filteredApps;
    if (apps.isEmpty) {
      return Center(
        child: Text(
          'No apps found',
          style: TextStyle(color: colors.textMuted, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        final excluded = _excludedPackages.contains(app['package']);
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_getAppIcon(app['package']!), color: colors.textMuted),
          ),
          title: Text(
            app['name']!,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
          subtitle: Text(
            app['package']!,
            style: TextStyle(color: colors.textMuted, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            excluded ? Icons.check_circle : Icons.add_circle_outline,
            color: excluded ? AppColors.warning : colors.textMuted,
          ),
          onTap: () {
            setState(() {
              if (excluded) {
                _excludedPackages.remove(app['package']);
              } else {
                _excludedPackages.add(app['package']!);
              }
            });
            _saveSelections();
          },
        );
      },
    );
  }

  IconData _getAppIcon(String packageName) {
    if (packageName.contains('chrome')) return Icons.language;
    if (packageName.contains('whatsapp')) return Icons.chat;
    if (packageName.contains('instagram')) return Icons.camera_alt;
    if (packageName.contains('facebook')) return Icons.facebook;
    if (packageName.contains('twitter') || packageName.contains('.x.')) return Icons.close;
    if (packageName.contains('youtube')) return Icons.play_circle;
    if (packageName.contains('spotify')) return Icons.music_note;
    if (packageName.contains('netflix')) return Icons.movie;
    if (packageName.contains('discord')) return Icons.headset_mic;
    if (packageName.contains('tiktok') || packageName.contains('musically')) return Icons.video_library;
    if (packageName.contains('gmail') || packageName.contains('.gm.')) return Icons.email;
    if (packageName.contains('maps')) return Icons.location_on;
    if (packageName.contains('phone')) return Icons.phone;
    if (packageName.contains('mms') || packageName.contains('messages')) return Icons.message;
    if (packageName.contains('slack')) return Icons.workspaces;
    if (packageName.contains('teams')) return Icons.groups;
    if (packageName.contains('zoom')) return Icons.videocam;
    if (packageName.contains('amazon')) return Icons.shopping_bag;
    if (packageName.contains('uber')) return Icons.local_taxi;
    if (packageName.contains('grab')) return Icons.local_taxi;
    if (packageName.contains('firefox')) return Icons.language;
    if (packageName.contains('opera')) return Icons.language;
    if (packageName.contains('brave')) return Icons.language;
    if (packageName.contains('viber')) return Icons.phone;
    if (packageName.contains('skype')) return Icons.phone;
    if (packageName.contains('wechat') || packageName.contains('tencent.mm')) return Icons.chat;
    if (packageName.contains('line')) return Icons.chat;
    if (packageName.contains('photos')) return Icons.photo_library;
    if (packageName.contains('prime') || packageName.contains('avod')) return Icons.movie;
    if (packageName.contains('disney')) return Icons.movie;
    if (packageName.contains('hbo')) return Icons.movie;
    if (packageName.contains('reddit')) return Icons.forum;
    if (packageName.contains('snapchat')) return Icons.camera_alt;
    if (packageName.contains('pinterest')) return Icons.push_pin;
    if (packageName.contains('linkedin')) return Icons.work;
    if (packageName.contains('ebay')) return Icons.shopping_cart;
    if (packageName.contains('shopee') || packageName.contains('lazada') || packageName.contains('flipkart')) return Icons.shopping_bag;
    return Icons.android;
  }
}
