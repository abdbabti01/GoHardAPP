import 'package:json_annotation/json_annotation.dart';

part 'friendship_status.g.dart';

@JsonSerializable()
class FriendshipStatus {
  final String
  status; // none, friends, pending_outgoing, pending_incoming, self
  final int? friendshipId;

  FriendshipStatus({required this.status, this.friendshipId});

  bool get isFriend => status == 'friends';
  bool get isPendingOutgoing => status == 'pending_outgoing';
  bool get isPendingIncoming => status == 'pending_incoming';
  bool get isNone => status == 'none';
  bool get isSelf => status == 'self';

  factory FriendshipStatus.fromJson(Map<String, dynamic> json) =>
      _$FriendshipStatusFromJson(json);
  Map<String, dynamic> toJson() => _$FriendshipStatusToJson(this);
}
