// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'program.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Program _$ProgramFromJson(Map<String, dynamic> json) => Program(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      title: json['title'] as String,
      description: json['description'] as String?,
      goalId: (json['goalId'] as num?)?.toInt(),
      totalWeeks: (json['totalWeeks'] as num).toInt(),
      currentWeek: (json['currentWeek'] as num).toInt(),
      currentDay: (json['currentDay'] as num).toInt(),
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
      isActive: json['isActive'] as bool,
      isCompleted: json['isCompleted'] as bool,
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      programStructure: json['programStructure'] as String?,
      workouts: (json['workouts'] as List<dynamic>?)
          ?.map((e) => ProgramWorkout.fromJson(e as Map<String, dynamic>))
          .toList(),
      goal: json['goal'] == null
          ? null
          : Goal.fromJson(json['goal'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ProgramToJson(Program instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'userId': instance.userId,
    'title': instance.title,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('description', instance.description);
  writeNotNull('goalId', instance.goalId);
  val['totalWeeks'] = instance.totalWeeks;
  val['currentWeek'] = instance.currentWeek;
  val['currentDay'] = instance.currentDay;
  val['startDate'] = instance.startDate.toIso8601String();
  writeNotNull('endDate', instance.endDate?.toIso8601String());
  val['isActive'] = instance.isActive;
  val['isCompleted'] = instance.isCompleted;
  writeNotNull('completedAt', instance.completedAt?.toIso8601String());
  val['createdAt'] = instance.createdAt.toIso8601String();
  writeNotNull('programStructure', instance.programStructure);
  writeNotNull('workouts', instance.workouts);
  writeNotNull('goal', instance.goal);
  return val;
}
