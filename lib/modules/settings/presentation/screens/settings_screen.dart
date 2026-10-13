import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:bulbvpn/shared/layout/main_screen_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../providers/settings_provider.dart';
import '../widgets/settings_group_widget.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionStateProvider);

    return MainScreenBackground(
      connectionStatus: connectionState.status,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 393.w),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 28.h),
                    _buildHeaderSection(),
                    SizedBox(height: 32.h),
                    _buildSettingsContent(ref),
                  ],
                ),
              )),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CONFIGURATION',
          style: AppTextStyles.microLabel(),
        ),
        const SizedBox(height: 8),
        Text(
          'Settings',
          style: TextStyle(
            fontSize: 32.sp,
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsContent(WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Column(
      children: settings
          .map((group) => SettingsGroupWidget(
                key: ValueKey(group.id),
                group: group,
                showSeparators: group.id == 'connection_method',
                onToggle: (groupId, itemId) {
                  settingsNotifier.toggleSetting(groupId, itemId);
                },
                onReorder: group.id == 'connection_method'
                    ? (oldIndex, newIndex) {
                        settingsNotifier.reorderConnectionMethodItems(oldIndex, newIndex);
                      }
                    : null,
                onReset: group.id == 'connection_method'
                    ? () {
                        settingsNotifier.resetConnectionMethodToDefault();
                      }
                    : null,
              ))
          .toList(),
    );
  }
}
