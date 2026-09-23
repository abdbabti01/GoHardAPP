import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/account_deletion_provider.dart';
import '../../widgets/common/premium_bottom_sheet.dart';

/// Explanation → password confirmation → explicit destructive confirmation →
/// delete. Reachable only from Settings (not visually dominant elsewhere),
/// but the destructive action itself is unmissable once here.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleDeletePressed(AccountDeletionProvider provider) async {
    if (provider.isDeleting) return; // belt-and-braces double-submit guard

    if (_passwordController.text.isEmpty) {
      provider.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your password to continue')),
      );
      return;
    }

    final confirmed = await ConfirmationBottomSheet.show(
      context: context,
      title: 'Delete your account?',
      message:
          'This permanently deletes your account and cannot be undone. '
          'Your workouts, nutrition logs, and other data will be gone.',
      confirmLabel: 'Delete Account',
      cancelLabel: 'Keep My Account',
      isDestructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (confirmed != true || !mounted) return;

    final password = _passwordController.text;
    final success = await provider.deleteAccount(password);

    if (!mounted) return;
    if (success) {
      // Navigation to the unauthenticated destination is handled centrally
      // by AuthProvider.onLoggedOut (AccountDeletionProvider calls
      // AuthProvider.logout() internally on success) - the same mechanism
      // the ordinary Logout button and forced session expiration rely on.
      // A second manual navigation here would violate "navigates exactly
      // once".
    } else if (provider.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete Account')),
      body: Consumer<AccountDeletionProvider>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.errorRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.errorRed.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.errorRed,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'This cannot be undone',
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              color: AppColors.errorRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Deleting your account permanently removes:',
                        // textPrimary, not textSecondary: this sits on the
                        // tinted warning background, not the plain surface
                        // color, and textSecondary's contrast against it
                        // fell just short of WCAG AA (4.48:1 vs 4.5:1).
                        style: TextStyle(color: context.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      ..._consequences.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '•  ',
                                style: TextStyle(color: context.textPrimary),
                              ),
                              Expanded(
                                child: Text(
                                  c,
                                  style: TextStyle(color: context.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Enter your password to confirm',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !provider.isDeleting,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      tooltip:
                          _obscurePassword ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed:
                          () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        provider.isDeleting
                            ? null
                            : () => _handleDeletePressed(provider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.errorRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child:
                        provider.isDeleting
                            ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                            : const Text(
                              'Delete Account',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

const _consequences = [
  'All workout, exercise, and program history',
  'Nutrition logs and goals',
  'Running history',
  'Friends, messages, and shared content',
  'Your profile and account credentials',
];
