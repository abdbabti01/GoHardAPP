import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/services/health_service.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../core/enums/profile_enums.dart';
import '../../../data/models/profile_update_request.dart';
import '../../widgets/common/loading_indicator.dart';

/// Settings screen for managing app preferences
/// Currently focuses on notification settings
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: Consumer2<SettingsProvider, ProfileProvider>(
        builder: (context, settings, profile, _) {
          if (settings.isLoading || profile.isLoading) {
            return const Center(child: PremiumLoader());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Health Integration Section (iOS/Android only)
              if (Platform.isIOS || Platform.isAndroid) ...[
                _buildSectionHeader(context, 'Health Integration'),
                const SizedBox(height: 8),
                _buildHealthCard(context),
                const SizedBox(height: 24),
              ],

              // Notifications Section
              _buildSectionHeader(context, 'Notifications'),
              const SizedBox(height: 8),
              _buildNotificationCard(context, settings),
              const SizedBox(height: 24),

              // Preferences Section
              _buildSectionHeader(context, 'Preferences'),
              const SizedBox(height: 8),
              _buildPreferencesCard(context, profile),
              const SizedBox(height: 24),

              // Appearance Section
              _buildSectionHeader(context, 'Appearance'),
              const SizedBox(height: 8),
              _buildAccentColorCard(context, settings),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    SettingsProvider settings,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Morning Reminder
            _buildNotificationToggle(
              context,
              title: 'Morning Reminder',
              subtitle:
                  'Daily workout reminder at ${settings.morningReminderTime.formatted}',
              enabled: settings.morningReminderEnabled,
              onChanged: (value) {
                settings.setMorningReminderEnabled(value);
              },
            ),
            if (settings.morningReminderEnabled) ...[
              const SizedBox(height: 8),
              _buildTimePicker(
                context,
                label: 'Morning Time',
                time: settings.morningReminderTime,
                onTimeSelected: (time) {
                  settings.setMorningReminderTime(time);
                },
              ),
            ],
            const Divider(height: 32),

            // Evening Reminder
            _buildNotificationToggle(
              context,
              title: 'Evening Reminder',
              subtitle:
                  'Reminder to complete your workout at ${settings.eveningReminderTime.formatted}',
              enabled: settings.eveningReminderEnabled,
              onChanged: (value) {
                settings.setEveningReminderEnabled(value);
              },
            ),
            if (settings.eveningReminderEnabled) ...[
              const SizedBox(height: 8),
              _buildTimePicker(
                context,
                label: 'Evening Time',
                time: settings.eveningReminderTime,
                onTimeSelected: (time) {
                  settings.setEveningReminderTime(time);
                },
              ),
            ],
            const Divider(height: 32),

            // Smart Nutrition Reminder
            _buildNotificationToggle(
              context,
              title: 'Smart Nutrition Reminder',
              subtitle:
                  settings.nutritionReminderEnabled
                      ? 'Reminds at ${settings.nutritionReminderTime.formatted} if goals not met'
                      : 'Get reminded only when nutrition goals are under 80%',
              enabled: settings.nutritionReminderEnabled,
              onChanged: (value) {
                settings.setNutritionReminderEnabled(value);
              },
            ),
            if (settings.nutritionReminderEnabled) ...[
              const SizedBox(height: 8),
              _buildTimePicker(
                context,
                label: 'Reminder Time',
                time: settings.nutritionReminderTime,
                onTimeSelected: (time) {
                  settings.setNutritionReminderTime(time);
                },
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This smart reminder only notifies you if you\'re under 80% of your calorie goal.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationToggle(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(subtitle),
      value: enabled,
      onChanged: onChanged,
      activeColor: Theme.of(context).primaryColor,
    );
  }

  Widget _buildTimePicker(
    BuildContext context, {
    required String label,
    required TimeOfDay time,
    required ValueChanged<TimeOfDay> onTimeSelected,
  }) {
    return InkWell(
      onTap: () async {
        final selectedTime = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                timePickerTheme: TimePickerThemeData(
                  backgroundColor: Theme.of(context).cardColor,
                  hourMinuteShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              child: child!,
            );
          },
        );

        if (selectedTime != null) {
          onTimeSelected(selectedTime);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const Spacer(),
            Text(
              time.formatted,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_drop_down, color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCard(BuildContext context) {
    final healthService = HealthService.instance;

    return ListenableBuilder(
      listenable: healthService,
      builder: (context, _) {
        final platformName = Platform.isIOS ? 'Apple Health' : 'Google Fit';
        final platformIcon =
            Platform.isIOS ? Icons.favorite : Icons.monitor_heart;

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Health integration toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(platformIcon, color: context.accent),
                  title: Text(
                    platformName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    healthService.isEnabled
                        ? 'Connected - syncing workouts automatically'
                        : 'Sync workouts with $platformName',
                  ),
                  value: healthService.isEnabled,
                  activeColor: context.accent,
                  onChanged: (value) async {
                    if (value) {
                      final success = await healthService.enable();
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not connect to $platformName. Please check permissions in Settings.',
                            ),
                            action: SnackBarAction(
                              label: 'OK',
                              onPressed: () {},
                            ),
                          ),
                        );
                      }
                    } else {
                      await healthService.disable();
                    }
                  },
                ),

                // Health summary when connected
                if (healthService.isEnabled && healthService.isAuthorized) ...[
                  const Divider(height: 32),
                  FutureBuilder<HealthSummary>(
                    future: healthService.getHealthSummary(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.accent,
                            ),
                          ),
                        );
                      }

                      final summary = snapshot.data!;
                      return Row(
                        children: [
                          Expanded(
                            child: _buildHealthStat(
                              context,
                              icon: Icons.directions_walk,
                              value: '${summary.stepsToday}',
                              label: 'Steps Today',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildHealthStat(
                              context,
                              icon: Icons.local_fire_department,
                              value: '${summary.activeCaloriesToday}',
                              label: 'Active Cal',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],

                // Info text
                const SizedBox(height: 16),
                Text(
                  'When enabled, completed workouts will automatically sync to $platformName.',
                  style: TextStyle(fontSize: 12, color: context.textTertiary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHealthStat(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: context.accent, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: context.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard(BuildContext context, ProfileProvider profile) {
    final user = profile.currentUser;
    if (user == null) {
      // Trigger profile load if not loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (profile.currentUser == null && !profile.isLoading) {
          profile.loadUserProfile();
        }
      });
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              children: [
                const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(height: 8),
                Text(
                  'Loading preferences...',
                  style: TextStyle(color: context.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentUnitPreference = UnitPreference.fromString(
      user.unitPreference,
    );
    final currentThemePreference = user.themePreference;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unit Preference
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Unit System',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              subtitle: Text(
                'Currently using ${currentUnitPreference.displayName} units',
              ),
              secondary: const Icon(Icons.straighten),
              value: currentUnitPreference == UnitPreference.imperial,
              onChanged: (value) async {
                final newPreference = value ? 'Imperial' : 'Metric';
                final request = ProfileUpdateRequest(
                  unitPreference: newPreference,
                );
                await profile.updateProfile(request);
              },
            ),
            const Divider(height: 32),

            // Theme Preference
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette),
              title: const Text(
                'Theme',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              subtitle: Text('Current: ${currentThemePreference ?? 'System'}'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildThemeOption(
                    context,
                    profile,
                    'Light',
                    Icons.light_mode,
                    currentThemePreference == 'Light',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildThemeOption(
                    context,
                    profile,
                    'Dark',
                    Icons.dark_mode,
                    currentThemePreference == 'Dark',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildThemeOption(
                    context,
                    profile,
                    'System',
                    Icons.settings_suggest,
                    currentThemePreference == 'System' ||
                        currentThemePreference == null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    ProfileProvider profile,
    String theme,
    IconData icon,
    bool isSelected,
  ) {
    // Use accent color for selected state - visible in both light and dark mode
    final selectedColor = context.accent;

    return InkWell(
      onTap: () async {
        final request = ProfileUpdateRequest(themePreference: theme);
        await profile.updateProfile(request);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? selectedColor.withValues(alpha: 0.15)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? selectedColor : context.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? selectedColor : context.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              theme,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? selectedColor : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentColorCard(
    BuildContext context,
    SettingsProvider settings,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.color_lens, color: context.accent),
                const SizedBox(width: 12),
                const Text(
                  'Accent Color',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose your preferred accent color throughout the app',
              style: TextStyle(fontSize: 14, color: context.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children:
                  AccentColorTheme.values.map((colorTheme) {
                    final isSelected = settings.accentColor == colorTheme;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right:
                              colorTheme != AccentColorTheme.values.last
                                  ? 12
                                  : 0,
                        ),
                        child: _buildAccentColorOption(
                          context,
                          settings,
                          colorTheme,
                          isSelected,
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentColorOption(
    BuildContext context,
    SettingsProvider settings,
    AccentColorTheme colorTheme,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () async {
        await settings.setAccentColor(colorTheme);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? colorTheme.primary.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorTheme.primary : context.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 36 : 28,
              height: isSelected ? 36 : 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorTheme.dark, colorTheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow:
                    isSelected
                        ? [
                          BoxShadow(
                            color: colorTheme.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                        : null,
              ),
              child:
                  isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
            ),
            const SizedBox(height: 8),
            Text(
              colorTheme.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? colorTheme.primary : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
