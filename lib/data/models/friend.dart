import 'package:json_annotation/json_annotation.dart';

part 'friend.g.dart';

@JsonSerializable()
class Friend {
  final int userId;
  final String username;
  final String name;
  final String? profilePhotoUrl;
  final DateTime friendsSince;

  Friend({
    required this.userId,
    required this.username,
    required this.name,
    this.profilePhotoUrl,
    required this.friendsSince,
  });

  factory Friend.fromJson(Map<String, dynamic> json) => _$FriendFromJson(json);
  Map<String, dynamic> toJson() => _$FriendToJson(this);
}
