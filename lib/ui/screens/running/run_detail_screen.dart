import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/running_provider.dart';
import '../../../data/models/run_session.dart';
import '../../../data/repositories/running_repository.dart';
import '../../widgets/running/run_stats_row.dart';
import '../../widgets/community/share_run_dialog.dart';

/// Screen showing detailed view of a single run with route map
class RunDetailScreen extends StatefulWidget {
  final int runId;

  const RunDetailScreen({super.key, required this.runId});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  RunSession? _run;
  bool _isLoading = true;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _loadRun();
  }

  Future<void> _loadRun() async {
    setState(() => _isLoading = true);

    final repository = context.read<RunningRepository>();
    final run = await repository.getRunSession(widget.runId);

    setState(() {
      _run = run;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _showShareDialog(BuildContext context, RunSession run) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ShareRunDialog(run: run),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Run shared with friends!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Run'),
            content: const Text(
              'Are you sure you want to delete this run? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: context.error),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (shouldDelete == true && mounted) {
      final repository = context.read<RunningRepository>();
      await repository.deleteRun(widget.runId);

      // Reload dashboard data
      if (mounted) {
        context.read<RunningProvider>().loadDashboardData();
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _run == null
              ? _buildNotFound(context)
              : _buildContent(context),
    );
  }

  Widget _buildNotFound(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'Run not found',
            style: TextStyle(fontSize: 18, color: context.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final run = _run!;
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final hasRoute = run.route.isNotEmpty;

    return CustomScrollView(
      slivers: [
        // App bar with map
        SliverAppBar(
          expandedHeight: hasRoute ? 300 : 120,
          pinned: true,
          backgroundColor: context.scaffoldBackground,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.surface.withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (run.status == 'completed')
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.surface.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.share, color: context.textPrimary),
                ),
                tooltip: 'Share with friends',
                onPressed: () => _showShareDialog(context, run),
              ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.surface.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_outline_rounded, color: context.error),
              ),
              onPressed: _handleDelete,
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background:
                hasRoute
                    ? _buildRouteMap(context, run)
                    : Container(
                      color: context.surfaceElevated,
                      child: Center(
                        child: Icon(
                          Icons.directions_run_rounded,
                          size: 64,
                          color: context.textTertiary,
                        ),
                      ),
                    ),
          ),
        ),

        // Content
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and date
                Text(
                  run.name ?? 'Run',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${dateFormat.format(run.date)} at ${timeFormat.format(run.startedAt ?? run.date)}',
                  style: TextStyle(fontSize: 14, color: context.textSecondary),
                ),

                const SizedBox(height: 24),

                // Main stats cards
                Row(
                  children: [
                    Expanded(
                      child: RunStatsCard(
                        label: 'Distance',
                        value: (run.distance ?? 0).toStringAsFixed(2),
                        unit: 'km',
                        icon: Icons.straighten_rounded,
                        iconColor: context.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RunStatsCard(
                        label: 'Duration',
                        value: run.formattedDuration,
                        icon: Icons.timer_outlined,
                        iconColor: context.accentBlue,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: RunStatsCard(
                        label: 'Avg Pace',
                        value: run.formattedPace,
                        unit: '/km',
                        icon: Icons.speed_rounded,
                        iconColor: context.accentCoral,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RunStatsCard(
                        label: 'Calories',
                        value: (run.calories ?? 0).toString(),
                        unit: 'cal',
                        icon: Icons.local_fire_department_rounded,
                        iconColor: context.accentAmber,
                      ),
                    ),
                  ],
                ),

                // Route points count
                if (hasRoute) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.route_rounded,
                            size: 20,
                            color: context.accent,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Route Recorded',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                '${run.route.length} GPS points tracked',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.check_circle_rounded, color: context.accent),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteMap(BuildContext context, RunSession run) {
    final routePoints =
        run.route.map((p) => LatLng(p.latitude, p.longitude)).toList();

    if (routePoints.isEmpty) {
      return Container(color: context.surfaceElevated);
    }

    // Calculate bounds for camera
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLng = routePoints.first.longitude;
    double maxLng = routePoints.first.longitude;

    for (final point in routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: center, zoom: 15),
      style: context.isDarkMode ? _darkMapStyle : null,
      onMapCreated: (controller) {
        _mapController = controller;

        // Fit bounds with padding
        final bounds = LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        );
        controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
      },
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      scrollGesturesEnabled: false,
      zoomGesturesEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      polylines: {
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: AppColors.accentCoral,
          width: 4,
        ),
      },
      markers: {
        Marker(
          markerId: const MarkerId('start'),
          position: routePoints.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: routePoints.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      },
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
