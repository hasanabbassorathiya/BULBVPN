import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';

class ImportServerScreen extends StatefulWidget {
  const ImportServerScreen({super.key});

  @override
  State<ImportServerScreen> createState() => _ImportServerScreenState();
}

class _ImportServerScreenState extends State<ImportServerScreen> {
  int _selectedMode = 0;
  final _urlController = TextEditingController();
  final _configController = TextEditingController();
  bool _loading = false;
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _configController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      _showSnackBar('Clipboard is empty');
      return;
    }
    await _importConfigOrSubscription(text);
  }

  Future<void> _importConfigOrSubscription(String text) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final vpn = context.read<VPNProvider>();
    final success = await vpn.importConfig(text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      _showSnackBar('Server imported successfully');
      Navigator.pop(context);
    } else {
      final subSuccess = await vpn.importSubscription(text);
      if (!mounted) return;
      setState(() => _loading = false);
      if (subSuccess) {
        _showSnackBar('Subscription imported successfully');
        Navigator.pop(context);
      } else {
        _showSnackBar('Failed to parse config or subscription');
      }
    }
  }

  Future<void> _importSubscription() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showSnackBar('Enter a subscription URL');
      return;
    }
    setState(() => _loading = true);
    final vpn = context.read<VPNProvider>();
    final success = await vpn.importSubscription(url);
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      _showSnackBar('Subscription imported successfully');
      Navigator.pop(context);
    } else {
      _showSnackBar('Failed to fetch subscription');
    }
  }

  Future<void> _importConfig() async {
    final config = _configController.text.trim();
    if (config.isEmpty) {
      _showSnackBar('Enter server config');
      return;
    }
    await _importConfigOrSubscription(config);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.bgCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_new,
                        color: colors.textPrimary, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Import Server',
                    style: AppTypography.displayMedium(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Add V2Ray, Xray, or Shadowsocks servers',
                style: AppTypography.bodyMedium(context),
              ),
              const SizedBox(height: AppSpacing.xxl),
              _buildPasteButton(colors),
              const SizedBox(height: AppSpacing.xxl),
              _buildSegmentedToggle(colors),
              const SizedBox(height: AppSpacing.lg),
              if (_selectedMode == 0) _buildSubscriptionMode(colors),
              if (_selectedMode == 1) _buildConfigMode(colors),
              if (_selectedMode == 2) _buildScanQRMode(colors),
              const SizedBox(height: AppSpacing.huge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasteButton(AppSemanticColors colors) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : _pasteFromClipboard,
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Icon(Icons.paste, size: 20, color: Colors.black),
        label: Text(
          _loading ? 'Importing...' : 'Paste from Clipboard',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: colors.card,
          disabledForegroundColor: colors.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildSegmentedToggle(AppSemanticColors colors) {
    final labels = ['Subscription URL', 'Server Config', 'Scan QR'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final active = _selectedMode == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedMode = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: active
                      ? Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                        )
                      : null,
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.primary : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSubscriptionMode(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Subscription URL',
                style: AppTypography.titleMedium(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Paste a subscription link to import multiple servers at once',
            style: AppTypography.labelSmall(context),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'https://example.com/subscribe',
              hintStyle: TextStyle(color: colors.textMuted),
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: colors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: colors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _importSubscription,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: colors.card,
                disabledForegroundColor: colors.textMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Import Subscription',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigMode(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.dns, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Server Configuration',
                style: AppTypography.titleMedium(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Paste vmess://, vless://, trojan://, ss:// URIs or raw JSON',
            style: AppTypography.labelSmall(context),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _configController,
            maxLines: 8,
            minLines: 5,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: 'vmess://eyJhZGRyZXNz...\nvless://uuid@host...',
              hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: colors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: colors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.all(AppSpacing.lg),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _importConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: colors.card,
                disabledForegroundColor: colors.textMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Import Config',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanQRMode(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.qr_code_scanner,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Scan QR Code',
                style: AppTypography.titleMedium(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Scan a QR code containing a VPN config or subscription URL',
            style: AppTypography.labelSmall(context),
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 280,
              child: MobileScanner(
                controller: _scannerController,
                onDetect: (capture) {
                  final code = capture.barcodes.first.rawValue;
                  if (code != null && !_loading) {
                    _importConfigOrSubscription(code);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
