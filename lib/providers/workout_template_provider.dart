import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/workout_template.dart';
import '../data/repositories/workout_template_repository.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/user_session_epoch.dart';

/// Provider for workout templates management.
///
/// ## Session-epoch guard
///
/// Every async method and the connectivity-restored callback captures a
/// [UserSessionToken] before its first await and rechecks
/// `_sessionEpoch.isCurrent(token)` after every await - including inside
/// catch/finally - before touching any list, loading flag, error field,
/// filter, or calling `notifyListeners()`. A result, error, or
/// finally-cleanup from a session that has since ended is dropped.
///
/// ## Per-load request generations
///
/// The three independent load paths - the owner list ([loadTemplates]), the
/// community list ([loadCommunityTemplates]) and the selected-template detail
/// ([loadTemplateById]) - each own a monotonically increasing request id
/// ([_ownerListRequestId] / [_communityRequestId] / [_selectedTemplateRequestId]).
/// Each load captures its id at entry and, after every await, commits its
/// result only if that id is still the latest. So an older request that
/// completes last (slow network, a connectivity-triggered refresh overtaken
/// by a manual pull-to-refresh, template A's detail resolving after template
/// B's) can never overwrite the newer request's result. [clear] bumps all
/// three ids, invalidating every pending load.
class WorkoutTemplateProvider extends ChangeNotifier {
  final WorkoutTemplateRepository _repository;
  final ConnectivityService _connectivity;
  final UserSessionEpoch _sessionEpoch;

  List<WorkoutTemplate> _templates = [];
  List<WorkoutTemplate> _communityTemplates = [];
  WorkoutTemplate? _selectedTemplate;
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<bool>? _connectivitySubscription;

  // Latest-request-wins generations, one per independent load path.
  int _ownerListRequestId = 0;
  int _communityRequestId = 0;
  int _selectedTemplateRequestId = 0;

  // Filter state
  String? _selectedCategory;
  bool _showActiveOnly = true;

  WorkoutTemplateProvider(
    this._repository,
    this._connectivity,
    this._sessionEpoch,
  ) {
    // This callback can fire at any point, including during a logged-out gap.
    // Capture a token fresh on every invocation and skip if there is no
    // active session.
    _connectivitySubscription = _connectivity.connectivityStream.listen((
      isOnline,
    ) {
      final token = _sessionEpoch.capture();
      if (token == null) return;
      if (isOnline) {
        debugPrint('📡 Connection restored - refreshing templates');
        loadTemplates(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Getters
  List<WorkoutTemplate> get templates => _templates;
  List<WorkoutTemplate> get communityTemplates => _communityTemplates;
  List<WorkoutTemplate> get activeTemplates =>
      _templates.where((t) => t.isActive).toList();
  WorkoutTemplate? get selectedTemplate => _selectedTemplate;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isOnline => _connectivity.isOnline;
  String? get selectedCategory => _selectedCategory;
  bool get showActiveOnly => _showActiveOnly;

  bool _ownerListCurrent(UserSessionToken token, int requestId) =>
      _sessionEpoch.isCurrent(token) && requestId == _ownerListRequestId;

  bool _communityCurrent(UserSessionToken token, int requestId) =>
      _sessionEpoch.isCurrent(token) && requestId == _communityRequestId;

  bool _selectedTemplateCurrent(UserSessionToken token, int requestId) =>
      _sessionEpoch.isCurrent(token) && requestId == _selectedTemplateRequestId;

  /// Load the current user's own templates. Latest call wins.
  Future<void> loadTemplates({bool showLoading = true}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final requestId = ++_ownerListRequestId;

    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final templateList = await _repository.getTemplates(
        activeOnly: _showActiveOnly,
      );
      if (!_ownerListCurrent(token, requestId)) return;
      _templates = templateList;
      debugPrint('✅ Loaded ${_templates.length} templates');
    } catch (e) {
      if (!_ownerListCurrent(token, requestId)) return;
      _errorMessage =
          'Failed to load templates: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Load templates error: $e');
    } finally {
      if (_ownerListCurrent(token, requestId)) {
        if (showLoading) {
          _isLoading = false;
        }
        notifyListeners();
      }
    }
  }

  /// Load community templates. Latest call wins.
  Future<void> loadCommunityTemplates({bool showLoading = true}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final requestId = ++_communityRequestId;

    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final templates = await _repository.getCommunityTemplates(
        category: _selectedCategory,
        limit: 50,
      );
      if (!_communityCurrent(token, requestId)) return;
      _communityTemplates = templates;
      debugPrint('✅ Loaded ${_communityTemplates.length} community templates');
    } catch (e) {
      if (!_communityCurrent(token, requestId)) return;
      _errorMessage =
          'Failed to load community templates: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Load community templates error: $e');
    } finally {
      if (_communityCurrent(token, requestId)) {
        if (showLoading) {
          _isLoading = false;
        }
        notifyListeners();
      }
    }
  }

  /// Load a specific template by its server ID into [selectedTemplate].
  /// Latest call wins, so template A's response arriving after template B's
  /// cannot replace B.
  Future<void> loadTemplateById(int serverId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final requestId = ++_selectedTemplateRequestId;

    try {
      final template = await _repository.getTemplateById(serverId);
      if (!_selectedTemplateCurrent(token, requestId)) return;
      _selectedTemplate = template;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Load template by ID error: $e');
    }
  }

  /// Create a new template. Online only - an offline attempt surfaces an
  /// explicit error and changes nothing.
  Future<WorkoutTemplate?> createTemplate({
    required String name,
    String? description,
    required String exercisesJson,
    required String recurrencePattern,
    String? daysOfWeek,
    int? intervalDays,
    int? estimatedDuration,
    String? category,
    bool isActive = true,
    bool isPublic = false,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final template = await _repository.createTemplate(
        name: name,
        description: description,
        exercisesJson: exercisesJson,
        recurrencePattern: recurrencePattern,
        daysOfWeek: daysOfWeek,
        intervalDays: intervalDays,
        estimatedDuration: estimatedDuration,
        category: category,
        isActive: isActive,
        isPublic: isPublic,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      _templates.insert(0, template);
      _selectedTemplate = template;
      debugPrint('✅ Created template: ${template.name}');
      return template;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to create template: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Create template error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Update an existing template. Online only.
  Future<bool> updateTemplate(WorkoutTemplate template) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = await _repository.updateTemplate(template);
      if (!_sessionEpoch.isCurrent(token)) return false;

      _replaceInList(_templates, updated);
      _replaceInList(_communityTemplates, updated);
      if (_selectedTemplate?.localId == updated.localId) {
        _selectedTemplate = updated;
      }
      debugPrint('✅ Updated template: ${updated.name}');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to update template: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Update template error: $e');
      return false;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Toggle active status of a template. Online only.
  Future<void> toggleActive(WorkoutTemplate template) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    try {
      final updated = await _repository.toggleActive(template);
      if (!_sessionEpoch.isCurrent(token)) return;
      if (updated == null) return;

      _replaceInList(_templates, updated);
      _replaceInList(_communityTemplates, updated);
      if (_selectedTemplate?.localId == updated.localId) {
        _selectedTemplate = updated;
      }
      notifyListeners();
      debugPrint('✅ Toggled active status for template ${updated.localId}');
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage =
          'Failed to toggle active status: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Toggle active error: $e');
      notifyListeners();
    }
  }

  /// Delete a template. Online only.
  Future<bool> deleteTemplate(WorkoutTemplate template) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      final deleted = await _repository.deleteTemplate(template);
      if (!_sessionEpoch.isCurrent(token)) return false;
      if (!deleted) return false;

      _templates.removeWhere((t) => t.localId == template.localId);
      _communityTemplates.removeWhere((t) => t.localId == template.localId);
      if (_selectedTemplate?.localId == template.localId) {
        _selectedTemplate = null;
      }
      notifyListeners();
      debugPrint('✅ Deleted template ${template.localId}');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to delete template: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Delete template error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Increment usage count for a template. Online only - the repository
  /// throws (and writes nothing) when offline. This provider deliberately
  /// does not surface that failure: the count is a best-effort stat bumped
  /// as a side effect of "Use template", and routing it into `_errorMessage`
  /// would replace the whole templates screen with an error view for a tap
  /// that otherwise succeeded. The failure is logged only.
  Future<void> incrementUsageCount(WorkoutTemplate template) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    try {
      await _repository.incrementUsageCount(template);
      if (!_sessionEpoch.isCurrent(token)) return;

      final target = _findByLocalId(template.localId);
      if (target != null) {
        target.usageCount++;
        target.lastUsedAt = DateTime.now();
        notifyListeners();
      }
      debugPrint('✅ Incremented usage count for template ${template.localId}');
    } catch (e) {
      debugPrint('❌ Increment usage count error: $e');
    }
  }

  /// Rate a community template. Online only.
  Future<bool> rateTemplate(WorkoutTemplate template, double rating) async {
    if (!_connectivity.isOnline) {
      _errorMessage = 'Cannot rate template while offline';
      notifyListeners();
      return false;
    }

    final serverId = template.serverId;
    if (serverId == null) return false;

    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      await _repository.rateTemplate(serverId, rating);
      if (!_sessionEpoch.isCurrent(token)) return false;

      await loadTemplateById(serverId);
      debugPrint('✅ Rated template $serverId with $rating stars');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to rate template: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Rate template error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get templates scheduled for a specific date
  Future<List<WorkoutTemplate>> getTemplatesForDate(DateTime date) async {
    try {
      return await _repository.getTemplatesForDate(date);
    } catch (e) {
      debugPrint('❌ Get templates for date error: $e');
      return [];
    }
  }

  /// Get templates scheduled for today
  Future<List<WorkoutTemplate>> getTodayTemplates() async {
    return getTemplatesForDate(DateTime.now());
  }

  /// Set category filter
  void setCategory(String? category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      loadCommunityTemplates();
    }
  }

  /// Toggle active-only filter
  void toggleActiveOnly() {
    _showActiveOnly = !_showActiveOnly;
    loadTemplates();
  }

  /// Clear all filters
  void clearFilters() {
    _selectedCategory = null;
    loadCommunityTemplates();
  }

  /// Set selected template
  void selectTemplate(WorkoutTemplate? template) {
    _selectedTemplate = template;
    notifyListeners();
  }

  /// Refresh all data
  Future<void> refresh() async {
    await loadTemplates();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear all workout-template data (called on logout). Bumps every request
  /// generation so any in-flight load is discarded when it resolves.
  void clear() {
    _ownerListRequestId++;
    _communityRequestId++;
    _selectedTemplateRequestId++;
    _templates = [];
    _communityTemplates = [];
    _selectedTemplate = null;
    _isLoading = false;
    _errorMessage = null;
    _selectedCategory = null;
    _showActiveOnly = true;
    notifyListeners();
    debugPrint('🧹 WorkoutTemplateProvider cleared');
  }

  // === PRIVATE HELPERS ===

  void _replaceInList(List<WorkoutTemplate> list, WorkoutTemplate updated) {
    final index = list.indexWhere((t) => t.localId == updated.localId);
    if (index != -1) {
      list[index] = updated;
    }
  }

  WorkoutTemplate? _findByLocalId(int localId) {
    for (final t in _templates) {
      if (t.localId == localId) return t;
    }
    for (final t in _communityTemplates) {
      if (t.localId == localId) return t;
    }
    return null;
  }
}
