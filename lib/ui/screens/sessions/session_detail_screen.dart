import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../providers/sessions_provider.dart';
import '../../../data/models/session.dart';
import '../../../data/repositories/session_sync_diagnostics.dart';
import '../../../core/theme/theme_colors.dart';
import '../../widgets/sessions/status_badge.dart';
import '../../widgets/community/share_workout_dialog.dart';

/// Navigation arguments for [SessionDetailScreen]. [localId] is the
/// unambiguous `LocalSession.localId` for the session being opened - the
/// caller must obtain it via `SessionsProvider.localIdFor(session)` at the
/// point it still holds the live `Session` instance (e.g. at the moment the
/// card/tile was tapped), never derive it from the public `sessionId`.
/// `null` when the entry point genuinely has no way to know it (e.g. it
/// only ever had a bare id from outside the current session list) - in that
/// case the screen omits the sync-issue affordance entirely rather than
/// guess via `sessionId`.
class SessionDetailArgs {
  final int sessionId;
  final int? localId;

  const SessionDetailArgs({required this.sessionId, this.localId});
}

/// Session detail screen for viewing completed workout
/// Matches SessionDetailPage.xaml from MAUI app
class SessionDetailScreen extends StatefulWidget {
  final int sessionId;

  /// The unambiguous `LocalSession.localId` for this session, if the caller
  /// had one available at navigation time - see [SessionDetailArgs]. Never
  /// derived from [sessionId]; when `null`, no sync-issue affordance is
  /// shown, rather than guessing which row [sessionId] refers to.
  final int? localId;

  const SessionDetailScreen({super.key, required this.sessionId, this.localId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  Session? _session;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<SessionsProvider>();
      final session = await provider.getSessionById(widget.sessionId);

      if (mounted) {
        setState(() {
          _session = session;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Details'),
        actions: [
          if (_session != null && _session!.status == 'completed')
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share with friends',
              onPressed: () => _showShareDialog(context),
            ),
          if (widget.localId != null)
            _SyncIssueAction(localId: widget.localId!),
        ],
      ),
      body: _buildBody(),
    );
  }

  Future<void> _showShareDialog(BuildContext context) async {
    if (_session == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ShareWorkoutDialog(session: _session!),
    );

    if (result == true && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Workout shared with friends!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Error Loading Workout',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadSession,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_session == null) {
      return const Center(child: Text('Session not found'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session header card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Responsive header: the formatted date can be an
                  // arbitrarily long English weekday/month string (e.g.
                  // "Wednesday, September 30, 2026"), and StatusBadge's own
                  // natural width also grows with text scale (its longest
                  // label, "In Progress", can itself approach or exceed a
                  // narrow screen's width at a large text scale). A Row
                  // (even with the date Expanded) cannot help once the
                  // BADGE alone doesn't fit - the badge has no flex and
                  // must never be truncated (status is essential
                  // semantics). Wrap solves both: each child is measured
                  // against the FULL available width independently, so
                  // neither is ever squeezed by the other - they share a
                  // line when there's room and stack onto separate lines
                  // otherwise, with no overflow possible either way.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Semantics(
                        label: DateFormat(
                          'EEEE, MMMM d, yyyy',
                        ).format(_session!.date),
                        child: ExcludeSemantics(
                          child: Text(
                            DateFormat(
                              'EEEE, MMMM d, yyyy',
                            ).format(_session!.date),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      StatusBadge(status: _session!.status),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Session stats. Wrap (not Row) so three self-contained
                  // stat items never overflow at narrow widths or an
                  // increased text scale - they simply flow onto a second
                  // line instead, exactly like the header fix above.
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      if (_session!.duration != null && _session!.duration! > 0)
                        _buildStatItem(
                          context,
                          Icons.timer,
                          'Duration',
                          _formatDuration(_session!.duration!),
                        ),
                      _buildStatItem(
                        context,
                        Icons.fitness_center,
                        'Exercises',
                        '${_session!.exercises.length}',
                      ),
                      _buildStatItem(
                        context,
                        Icons.repeat,
                        'Total Sets',
                        '${_getTotalSets()}',
                      ),
                    ],
                  ),

                  // Notes
                  if (_session!.notes != null &&
                      _session!.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.note_outlined,
                          size: 20,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _session!.notes!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Exercises list
          if (_session!.exercises.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No exercises logged',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                ),
              ),
            )
          else
            Text(
              'Exercises',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),

          const SizedBox(height: 12),

          // Exercise cards
          ..._session!.exercises.map((exercise) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Exercise details
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        if (exercise.exerciseSets.isNotEmpty)
                          _buildDetailChip(
                            context,
                            Icons.repeat,
                            '${exercise.exerciseSets.length} sets',
                          ),
                        if (exercise.duration != null && exercise.duration! > 0)
                          _buildDetailChip(
                            context,
                            Icons.timer,
                            _formatDuration(exercise.duration!),
                          ),
                      ],
                    ),

                    // Exercise notes
                    if (exercise.notes != null &&
                        exercise.notes!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        exercise.notes!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            // Flexible so a large text scale never overflows this stat
            // item's own icon+label row; the label is a short, fixed,
            // known string, but its full text stays available in
            // semantics even if the visual text ever needs to ellipsize.
            Flexible(
              child: Semantics(
                label: label,
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildDetailChip(BuildContext context, IconData icon, String text) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }

  int _getTotalSets() {
    return _session!.exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.exerciseSets.length,
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }
}

/// Conditional, tooltipped AppBar action showing this session's retained
/// sync diagnostics, if any - passive only. Reacts to
/// [SessionsProvider]'s live joined snapshot (never a stale one-shot copy):
/// rebuilds whenever the provider notifies, so a diagnostic that clears
/// (successful background sync) or a new one that appears is reflected
/// without leaving the screen. Opens a read-only dialog with no retry,
/// discard, keep-local, use-server, delete, or reset control; dismissing it
/// mutates nothing.
class _SyncIssueAction extends StatelessWidget {
  /// The unambiguous `LocalSession.localId` for the session being viewed -
  /// never the ambiguous public `sessionId`. Resolved by the caller via
  /// `SessionsProvider.localIdFor(session)` before navigating here.
  final int localId;

  const _SyncIssueAction({required this.localId});

  @override
  Widget build(BuildContext context) {
    // Select a value-comparable record, not the SessionSyncDiagnostics
    // object itself - it declares no `==`/`hashCode` (deliberately, so the
    // provider's identity-keyed diagnostics map stays collision-safe - see
    // SessionsProvider.diagnosticsFor), which would make a raw-object
    // select() rebuild on every watch emission regardless of an actual
    // change.
    final selected = context
        .select<SessionsProvider, (SessionSyncState, DateTime?)?>((p) {
          final d = p.diagnosticsForLocalId(localId);
          return d == null ? null : (d.state, d.lastAttemptAt);
        });
    if (selected == null) return const SizedBox.shrink();
    final diagnostics = SessionSyncDiagnostics(
      state: selected.$1,
      lastAttemptAt: selected.$2,
    );

    final isConflict = diagnostics.isConflict;
    final color = isConflict ? context.error : context.warning;

    return IconButton(
      icon: Icon(
        isConflict ? Icons.warning_rounded : Icons.sync_problem_rounded,
        color: color,
      ),
      tooltip: diagnostics.state.shortLabel,
      onPressed: () => _showSyncIssueDialog(context, diagnostics),
    );
  }

  void _showSyncIssueDialog(
    BuildContext context,
    SessionSyncDiagnostics diagnostics,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(diagnostics.state.shortLabel),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(diagnostics.state.friendlyMessage),
                if (diagnostics.lastAttemptAt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    // A conflict's timestamp is when it was detected, not a
                    // retry attempt - it is explicitly excluded from the
                    // retry loop, so calling it an "attempt" would wrongly
                    // imply retrying is still happening.
                    '${diagnostics.isConflict ? 'Detected' : 'Last attempt'}: '
                    '${_formatLastAttempt(diagnostics.lastAttemptAt!)}',
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(color: dialogContext.textSecondary),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  String _formatLastAttempt(DateTime lastAttempt) {
    final local = lastAttempt.toLocal();
    return DateFormat('MMM d, yyyy \'at\' h:mm a').format(local);
  }
}
