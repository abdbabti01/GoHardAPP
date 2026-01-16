import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../core/enums/profile_enums.dart';
import '../../../data/models/profile_update_request.dart';

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
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Notifications Section
              _buildSectionHeader(context, 'Notifications'),
              const SizedBox(height: 8),
              _buildNotificationCard(context, settings),
              const SizedBox(height: 24),

              // Preferences Section
              _buildSectionHeader(context, 'Preferences'),
              const SizedBox(height: 8),
              _buildPreferencesCard(context, profile),
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

  Widget _buildPreferencesCard(BuildContext context, ProfileProvider profile) {
    final user = profile.currentUser;
    if (user == null) return const SizedBox.shrink();

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
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : context.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color:
                  isSelected
                      ? Theme.of(context).primaryColor
                      : context.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              theme,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color:
                    isSelected
                        ? Theme.of(context).primaryColor
                        : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
