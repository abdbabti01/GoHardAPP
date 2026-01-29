import 'package:json_annotation/json_annotation.dart';

part 'user_search_result.g.dart';

@JsonSerializable()
class UserSearchResult {
  final int userId;
  final String username;
  final String name;
  final String? profilePhotoUrl;

  UserSearchResult({
    required this.userId,
    required this.username,
    required this.name,
    this.profilePhotoUrl,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      _$UserSearchResultFromJson(json);
  Map<String, dynamic> toJson() => _$UserSearchResultToJson(this);
}
