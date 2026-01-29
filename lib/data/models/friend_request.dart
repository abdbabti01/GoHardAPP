import 'package:json_annotation/json_annotation.dart';

part 'friend_request.g.dart';

@JsonSerializable()
class FriendRequest {
  final int friendshipId;
  final int userId;
  final String username;
  final String name;
  final String? profilePhotoUrl;
  final DateTime requestedAt;

  FriendRequest({
    required this.friendshipId,
    required this.userId,
    required this.username,
    required this.name,
    this.profilePhotoUrl,
    required this.requestedAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) =>
      _$FriendRequestFromJson(json);
  Map<String, dynamic> toJson() => _$FriendRequestToJson(this);
}
