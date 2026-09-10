import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../data/models/profile_update_request.dart';
import '../../../data/models/user.dart';
import '../../../core/enums/profile_enums.dart';
import '../../../core/utils/image_format.dart';
import '../../../core/utils/unit_converter.dart';
import '../../../routes/route_names.dart';
import '../../widgets/common/user_avatar.dart';

/// Edit profile screen for updating user account information.
///
/// Physical measurements (height, weight, body fat, activity level) are NOT
/// edited here - Body Metrics owns those and their history. This screen shows
/// the current height read-only and links to Body Metrics for changes, so the
/// profile never keeps a second, competing editable copy.
///
/// Photo and profile fields are two SEPARATE server endpoints. Picking a photo
/// only stages a local draft; nothing is uploaded until Save. Save is not
/// atomic across the two calls - if one half fails, the successful half is
/// kept, the failed half's draft is retained, and the message says which part
/// did not save (never "success").
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  static final RegExp _usernamePattern = RegExp(r'^[A-Za-z0-9_]{1,30}$');

  // Controllers
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _favoriteExercisesController = TextEditingController();

  // Form values
  DateTime? _dateOfBirth;
  Gender? _gender;
  ExperienceLevel? _experienceLevel;
  FitnessGoal? _primaryGoal;
  UnitPreference _unitPreference = UnitPreference.metric;
  String? _themePreference;

  /// Locally picked, NOT-yet-uploaded photo. Cleared once the server has
  /// accepted it (or the screen is left). Never rendered as a committed photo.
  File? _selectedImage;

  /// A server-side username error to show inline under the field (taken /
  /// invalid). Cleared on the next edit or save attempt.
  String? _usernameServerError;

  /// Controllers/fields are seeded from the loaded profile exactly once, the
  /// first time it is available - a later background refresh must not clobber
  /// what the user is currently typing.
  bool _hydrated = false;

  /// Guards the pick sequence so a double tap cannot open two pickers.
  bool _photoActionInProgress = false;

  /// Guards Save so a double tap cannot start two save passes.
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    // Nothing else guarantees the profile is loaded when this screen opens
    // (it is cleared on logout and only re-fetched by a couple of screens),
    // so fields could otherwise initialise blank right after login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ProfileProvider>();
      if (provider.currentUser == null && !provider.isLoading) {
        provider.loadUserProfile();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _favoriteExercisesController.dispose();
    super.dispose();
  }

  /// Seed the form from [user] on first availability only.
  void _hydrateFromUser(User user) {
    if (_hydrated) return;
    _hydrated = true;

    _unitPreference = UnitPreference.fromString(user.unitPreference);
    _nameController.text = user.name;
    _usernameController.text = user.username;
    _bioController.text = user.bio ?? '';
    _favoriteExercisesController.text = user.favoriteExercises ?? '';
    // Date of birth is a calendar date - strip any time/zone so display and
    // re-save never shift it a day for users off UTC.
    final dob = user.dateOfBirth;
    _dateOfBirth = dob == null ? null : DateTime(dob.year, dob.month, dob.day);
    _gender = Gender.fromString(user.gender);
    _experienceLevel = ExperienceLevel.fromString(user.experienceLevel);
    _primaryGoal = FitnessGoal.fromString(user.primaryGoal);
    _themePreference = user.themePreference;
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_photoActionInProgress || _saving) return;
    _photoActionInProgress = true;
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image == null || !mounted) return;

      // Verify the ACTUAL bytes, not the extension/MIME the picker reports:
      // an iPhone HEIC selection is not guaranteed to be transcoded to JPEG,
      // and the server only stores JPEG/PNG. Reject here with a clear message
      // rather than letting it become a confusing server 400.
      final format = await detectImageFormat(File(image.path));
      if (!mounted) return;
      if (!format.isServerSupported) {
        _showError(
          format == DetectedImageFormat.heic
              ? 'That photo is in HEIC/HEIF format, which is not supported. '
                  'In iOS Settings > Camera > Formats choose "Most Compatible", '
                  'or pick a JPEG/PNG image.'
              : 'That image is ${format.label}, which is not supported. '
                  'Please choose a JPEG or PNG.',
        );
        return;
      }

      // Draft only - uploaded on Save, not now.
      setState(() {
        _selectedImage = File(image.path);
      });
    } catch (e) {
      if (mounted) {
        _showError('Could not select that image. Please try again.');
      }
    } finally {
      _photoActionInProgress = false;
    }
  }

  void _discardDraftPhoto() {
    setState(() => _selectedImage = null);
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take a Photo'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                if (_selectedImage != null)
                  ListTile(
                    leading: const Icon(Icons.close),
                    title: const Text('Discard picked photo'),
                    onTap: () {
                      Navigator.pop(context);
                      _discardDraftPhoto();
                    },
                  ),
              ],
            ),
          ),
    );
  }

  Future<void> _selectDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select Date of Birth',
    );

    if (picked != null && mounted) {
      // Keep only the calendar date (picker already returns local midnight).
      setState(
        () => _dateOfBirth = DateTime(picked.year, picked.month, picked.day),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// Save is two independent server writes (photo, then fields). Neither is
  /// rolled back if the other fails; the message reflects exactly what landed.
  Future<void> _saveProfile() async {
    if (_saving || !_hydrated) return;
    final user = context.read<ProfileProvider>().currentUser;
    if (user == null) return;

    setState(() {
      _saving = true;
      _usernameServerError = null;
    });

    final provider = context.read<ProfileProvider>();
    final auth = context.read<AuthProvider>();
    // Captured under the CURRENT session, before any await, so a username
    // reconciliation that lands after the session changed is rejected.
    final authToken = auth.captureSessionToken();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (!_formKey.currentState!.validate()) return;

      // ---- 1. Photo (only if one was picked this session) ------------------
      final photoAttempted = _selectedImage != null;
      bool photoOk = true;
      String? photoFailure;
      if (photoAttempted) {
        photoOk = await provider.uploadProfilePhoto(_selectedImage!);
        if (!mounted) return;
        if (photoOk) {
          setState(() => _selectedImage = null);
        } else {
          switch (provider.photoError) {
            case PhotoUploadError.conflict:
              // Someone else changed the photo. Refresh authoritative state
              // and let the user decide - never silently overwrite.
              await provider.loadUserProfile();
              if (!mounted) return;
              photoFailure =
                  'Your profile photo was changed on another device. '
                  'Tap Save again to upload this one.';
              break;
            case PhotoUploadError.tooLarge:
              photoFailure = 'That image is too large. Pick a smaller one.';
              break;
            case PhotoUploadError.validation:
              photoFailure =
                  'The server rejected that image. Pick a JPEG or PNG.';
              break;
            case PhotoUploadError.network:
            case PhotoUploadError.none:
              photoFailure = 'Photo upload failed. Check your connection.';
              break;
          }
        }
      }

      // ---- 2. Profile fields --------------------------------------------
      final trimmedUsername = _usernameController.text.trim();
      final usernameChanged =
          trimmedUsername.isNotEmpty && trimmedUsername != user.username;

      final request = ProfileUpdateRequest(
        name: _nameController.text.trim(),
        // Omitted => unchanged. Only sent when actually different.
        username: usernameChanged ? trimmedUsername : null,
        bio:
            _bioController.text.trim().isEmpty
                ? null
                : _bioController.text.trim(),
        dateOfBirth: _dateOfBirth,
        gender: _gender?.serverValue,
        experienceLevel: _experienceLevel?.serverValue,
        primaryGoal: _primaryGoal?.serverValue,
        unitPreference: _unitPreference.serverValue,
        themePreference: _themePreference,
        favoriteExercises:
            _favoriteExercisesController.text.trim().isEmpty
                ? null
                : _favoriteExercisesController.text.trim(),
      );

      final fieldsOk = await provider.updateProfile(request);
      if (!mounted) return;

      String? fieldsFailure;
      if (fieldsOk) {
        if (usernameChanged) {
          // Reconcile the handle everywhere it is cached (AuthProvider +
          // secure storage). Safe to call even if this screen has since been
          // disposed - it is a plain provider method, and AuthProvider drops
          // it if `authToken`'s session is no longer current.
          auth.applyUpdatedUsername(trimmedUsername, authToken);
        }
      } else {
        switch (provider.fieldsError) {
          case ProfileFieldsError.usernameTaken:
            setState(
              () => _usernameServerError = 'That username is already taken.',
            );
            fieldsFailure = 'Username already taken.';
            break;
          case ProfileFieldsError.validation:
            if (usernameChanged) {
              setState(
                () =>
                    _usernameServerError =
                        'Invalid username. Use 1-30 letters, numbers or _.',
              );
              fieldsFailure = 'That username is not valid.';
            } else {
              fieldsFailure =
                  provider.errorMessage ?? 'Some details could not be saved.';
            }
            break;
          case ProfileFieldsError.network:
          case ProfileFieldsError.none:
            fieldsFailure =
                'Could not save your details. Check your connection.';
            break;
        }
      }

      // ---- 3. Compose the outcome -------------------------------------
      if (photoOk && fieldsOk) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
        navigator.pop();
        return;
      }

      // Partial (or total) failure: name what DID land, then what did not, and
      // stay on the screen with the failed half's draft retained for retry.
      final parts = <String>[];
      if (photoAttempted && photoOk && !fieldsOk) {
        parts.add('Your photo was saved.');
      }
      if (photoAttempted && !photoOk && fieldsOk) {
        parts.add('Your details were saved.');
      }
      if (photoAttempted && !photoOk && photoFailure != null) {
        parts.add(photoFailure);
      }
      if (!fieldsOk && fieldsFailure != null) parts.add(fieldsFailure);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty
                ? 'Some changes could not be saved.'
                : parts.join(' '),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final user = provider.currentUser;
    final busy = provider.isUpdating || provider.isUploadingPhoto || _saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          if (busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (user != null)
            TextButton(
              onPressed: _saveProfile,
              child: const Text('Save', style: TextStyle(fontSize: 16)),
            ),
        ],
      ),
      body: _buildBody(provider, user),
    );
  }

  Widget _buildBody(ProfileProvider provider, User? user) {
    if (user == null) {
      if (provider.errorMessage != null && !provider.isLoading) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(provider.errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => provider.loadUserProfile(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    _hydrateFromUser(user);

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPhotoSection(provider, user),
            const SizedBox(height: 24),

            _buildSectionHeader('Personal Details'),
            const SizedBox(height: 16),
            _buildPersonalDetailsCard(),
            const SizedBox(height: 24),

            _buildSectionHeader('Body Measurements'),
            const SizedBox(height: 16),
            _buildBodyMeasurementsCard(user),
            const SizedBox(height: 24),

            _buildSectionHeader('Fitness Profile'),
            const SizedBox(height: 16),
            _buildFitnessProfileCard(),
            const SizedBox(height: 24),

            _buildSectionHeader('Bio & Social'),
            const SizedBox(height: 16),
            _buildBioCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection(ProfileProvider provider, User user) {
    final hasDraft = _selectedImage != null;
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              if (hasDraft)
                CircleAvatar(
                  radius: 60,
                  backgroundImage: FileImage(_selectedImage!),
                  onBackgroundImageError: (_, __) {
                    // The picked temp file vanished before render (OS cleanup /
                    // external delete) - fall back rather than show a red error
                    // box, and drop the now-unusable draft.
                    if (mounted) setState(() => _selectedImage = null);
                  },
                )
              else
                UserAvatar(
                  photoUrl: user.profilePhotoUrl,
                  fallbackText: user.name,
                  radius: 60,
                ),
              Positioned(
                bottom: 0,
                right: 0,
                // A ≥48 dp tap target for the camera control (the 40 px badge
                // circle alone clips below the accessibility minimum).
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: const Icon(Icons.camera_alt, size: 20),
                      color: Colors.white,
                      tooltip: 'Change profile photo',
                      onPressed:
                          (provider.isUploadingPhoto || _saving)
                              ? null
                              : _showImagePickerOptions,
                    ),
                  ),
                ),
              ),
              if (provider.isUploadingPhoto)
                Positioned.fill(
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.black54,
                    child: const CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
          if (hasDraft) ...[
            const SizedBox(height: 8),
            Text(
              'New photo - not saved yet',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            TextButton(
              onPressed: _saving ? null : _discardDraftPhoto,
              child: const Text('Discard'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildPersonalDetailsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'Your display name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                helperText:
                    'Letters, numbers and _ (1-30). Blank keeps current.',
                prefixIcon: const Icon(Icons.alternate_email),
                errorText: _usernameServerError,
              ),
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) {
                if (_usernameServerError != null) {
                  setState(() => _usernameServerError = null);
                }
              },
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return null; // unchanged
                if (!_usernamePattern.hasMatch(v)) {
                  return 'Use 1-30 letters, numbers or _';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _selectDateOfBirth,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of Birth',
                  prefixIcon: Icon(Icons.cake),
                ),
                child: Text(
                  _dateOfBirth != null
                      ? '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}'
                      : 'Select date',
                  style: TextStyle(
                    color: _dateOfBirth != null ? null : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Gender>(
              value: _gender,
              decoration: const InputDecoration(
                labelText: 'Gender',
                prefixIcon: Icon(Icons.wc),
              ),
              items:
                  Gender.values
                      .map(
                        (gender) => DropdownMenuItem(
                          value: gender,
                          child: Text(gender.displayName),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _gender = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyMeasurementsCard(User user) {
    final hasHeight = user.height != null;
    final displayHeight =
        hasHeight
            ? UnitConverter.formatHeight(
              user.height,
              _unitPreference.serverValue,
            )
            : 'Not set';

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.height),
            title: const Text('Height'),
            subtitle: const Text('Tracked in Body Metrics'),
            trailing: Text(
              displayHeight,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: hasHeight ? null : Theme.of(context).disabledColor,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.monitor_weight_outlined),
            title: const Text('Manage measurements'),
            subtitle: const Text(
              'Update height, weight and body fat with history',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.pushNamed(context, RouteNames.bodyMetrics);
              // Body Metrics is the source of truth for derived measurements;
              // pull the fresh profile so this screen's read-only height
              // reflects any change made over there.
              if (mounted) {
                context.read<ProfileProvider>().loadUserProfile();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFitnessProfileCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<ExperienceLevel>(
              value: _experienceLevel,
              decoration: const InputDecoration(
                labelText: 'Experience Level',
                prefixIcon: Icon(Icons.star),
              ),
              items:
                  ExperienceLevel.values
                      .map(
                        (level) => DropdownMenuItem(
                          value: level,
                          child: Text(level.displayName),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _experienceLevel = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<FitnessGoal>(
              value: _primaryGoal,
              decoration: const InputDecoration(
                labelText: 'Primary Goal',
                prefixIcon: Icon(Icons.track_changes),
              ),
              items:
                  FitnessGoal.values
                      .map(
                        (goal) => DropdownMenuItem(
                          value: goal,
                          child: Text(goal.displayName),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _primaryGoal = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBioCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: _bioController,
              decoration: const InputDecoration(
                labelText: 'Bio',
                prefixIcon: Icon(Icons.info),
                hintText: 'Tell us about yourself...',
              ),
              maxLines: 4,
              maxLength: 500,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _favoriteExercisesController,
              decoration: const InputDecoration(
                labelText: 'Favorite Exercises',
                prefixIcon: Icon(Icons.favorite),
                hintText: 'e.g., Squats, Deadlifts, Bench Press',
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
