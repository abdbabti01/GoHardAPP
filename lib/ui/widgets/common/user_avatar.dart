import 'package:flutter/material.dart';

import '../../../core/constants/api_config.dart';
import '../../../core/theme/theme_colors.dart';

/// Circular avatar for a user, backed by their server profile photo.
///
/// Give it the raw [photoUrl] exactly as it arrives from the API (a relative
/// path like `/uploads/profiles/user_5_20240101.jpg` or an absolute URL);
/// [ApiConfig.getPhotoUrl] resolves it. When [photoUrl] is null/empty, or the
/// image fails to load, it falls back to the brand-gradient circle with the
/// first letter of [fallbackText] (or a person icon when that is empty too) -
/// matching the app's existing avatar styling.
///
/// Kept deliberately small so every profile/social surface renders the same
/// avatar instead of re-deriving the `NetworkImage(ApiConfig.getPhotoUrl(...))`
/// dance locally.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.photoUrl,
    this.fallbackText,
    this.radius = 28,
  });

  final String? photoUrl;
  final String? fallbackText;
  final double radius;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  /// When the last load of the current URL failed. Null = not failed. A
  /// failure is treated as transient: after [_retryAfter] any rebuild (a
  /// provider notify, a navigation) re-attempts the image instead of staying
  /// on the fallback forever.
  DateTime? _failedAt;
  static const Duration _retryAfter = Duration(seconds: 20);

  String? get _resolvedUrl {
    final raw = widget.photoUrl;
    if (raw == null || raw.isEmpty) return null;
    final resolved = ApiConfig.getPhotoUrl(raw);
    return resolved.isEmpty ? null : resolved;
  }

  bool get _inFailedState {
    final failedAt = _failedAt;
    if (failedAt == null) return false;
    return DateTime.now().difference(failedAt) < _retryAfter;
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A replaced photo (new server URL) must get a fresh load attempt rather
    // than staying stuck on the previous failure.
    if (oldWidget.photoUrl != widget.photoUrl) {
      _failedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label =
        (widget.fallbackText ?? '').trim().isEmpty
            ? 'Profile photo'
            : 'Profile photo for ${widget.fallbackText!.trim()}';
    return Semantics(label: label, image: true, child: _buildAvatar(context));
  }

  Widget _buildAvatar(BuildContext context) {
    final url = _resolvedUrl;
    final showImage = url != null && !_inFailedState;
    final diameter = widget.radius * 2;

    if (showImage) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.15),
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, __) {
          if (mounted) setState(() => _failedAt = DateTime.now());
        },
      );
    }

    final fallback = (widget.fallbackText ?? '').trim();
    final initial = fallback.isEmpty ? null : fallback[0].toUpperCase();

    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: context.primaryGradient,
      ),
      child:
          initial != null
              ? Text(
                initial,
                style: TextStyle(
                  fontSize: widget.radius * 0.8,
                  fontWeight: FontWeight.w600,
                  color: context.textOnPrimary,
                ),
              )
              : Icon(
                Icons.person,
                size: widget.radius,
                color: context.textOnPrimary,
              ),
    );
  }
}
