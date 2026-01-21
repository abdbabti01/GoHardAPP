import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/running_provider.dart';

/// Full-screen active running interface with live map
class ActiveRunScreen extends StatefulWidget {
  final int runId;

  const ActiveRunScreen({super.key, required this.runId});

  @override
  State<ActiveRunScreen> createState() => _ActiveRunScreenState();
}

class _ActiveRunScreenState extends State<ActiveRunScreen> {
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RunningProvider>().loadRun(widget.runId);
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _updatePolylines(List<LatLng> points) {
    if (points.isEmpty) return;

    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: AppColors.accentCoral,
          width: 5,
        ),
      );
    });

    // Move camera to follow user
    if (_mapController != null && points.isNotEmpty) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(points.last));
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _handleFinish() async {
    final provider = context.read<RunningProvider>();

    final shouldFinish = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Finish Run'),
            content: Text(
              'Distance: ${provider.currentDistance.toStringAsFixed(2)} km\n'
              'Duration: ${_formatDuration(provider.elapsedTime)}\n\n'
              'Do you want to save this run?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context, null);
                  await provider.discardRun();
                  if (mounted) {
                    Navigator.pop(this.context);
                  }
                },
                child: Text('Discard', style: TextStyle(color: context.error)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (shouldFinish == true && mounted) {
      final success = await provider.finishRun();
      if (success && mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final provider = context.read<RunningProvider>();
        if (provider.hasActiveRun) {
          await _handleFinish();
        } else {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.scaffoldBackground,
        body: Consumer<RunningProvider>(
          builder: (context, provider, child) {
            final routePoints =
                provider.routePoints
                    .map((p) => LatLng(p.latitude, p.longitude))
                    .toList();

            // Update polylines when route changes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updatePolylines(routePoints);
            });

            return Stack(
              children: [
                // Map
                _buildMap(context, routePoints),

                // Timer overlay at top
                _buildTimerOverlay(context, provider),

                // Stats and controls at bottom
                _buildBottomPanel(context, provider),

                // Back button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  child: _buildBackButton(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMap(BuildContext context, List<LatLng> routePoints) {
    final initialPosition =
        routePoints.isNotEmpty
            ? routePoints.last
            : const LatLng(37.7749, -122.4194); // Default to SF

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initialPosition, zoom: 16),
      style: context.isDarkMode ? _darkMapStyle : null,
      onMapCreated: (controller) {
        _mapController = controller;
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      polylines: _polylines,
      markers:
          routePoints.isNotEmpty
              ? {
                Marker(
                  markerId: const MarkerId('start'),
                  position: routePoints.first,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                ),
              }
              : {},
    );
  }

  Widget _buildTimerOverlay(BuildContext context, RunningProvider provider) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            _formatDuration(provider.elapsedTime),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              fontFamily: 'SpaceGrotesk',
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context, RunningProvider provider) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(
                      context,
                      provider.currentDistance.toStringAsFixed(2),
                      'km',
                      'Distance',
                    ),
                    Container(width: 1, height: 40, color: context.border),
                    _buildStatColumn(
                      context,
                      provider.formattedPace,
                      '/km',
                      'Pace',
                    ),
                    Container(width: 1, height: 40, color: context.border),
                    _buildStatColumn(
                      context,
                      ((provider.currentDistance * 60).round()).toString(),
                      'cal',
                      'Calories',
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Pause/Resume button
                    _buildControlButton(
                      context,
                      icon:
                          provider.isTimerRunning
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      label: provider.isTimerRunning ? 'Pause' : 'Resume',
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        if (provider.isTimerRunning) {
                          provider.pauseRun();
                        } else {
                          provider.resumeRun();
                        }
                      },
                      isPrimary: true,
                      color: context.accent,
                    ),

                    // Stop button
                    _buildControlButton(
                      context,
                      icon: Icons.stop_rounded,
                      label: 'Finish',
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        _handleFinish();
                      },
                      isPrimary: false,
                      color: context.accentCoral,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    String value,
    String unit,
    String label,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
                height: 1,
              ),
            ),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                unit,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isPrimary ? 80 : 64,
            height: isPrimary ? 80 : 64,
            decoration: BoxDecoration(
              color: isPrimary ? color : color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              boxShadow:
                  isPrimary
                      ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                      : null,
            ),
            child: Icon(
              icon,
              size: isPrimary ? 40 : 32,
              color: isPrimary ? Colors.white : color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.surface.withValues(alpha: 0.95),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
      ),
    );
  }

  // Dark map style JSON
  static const String _darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#1d1d1d"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#8a8a8a"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#1d1d1d"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#2d2d2d"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#6a6a6a"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0d1117"}]}
]
''';
}
