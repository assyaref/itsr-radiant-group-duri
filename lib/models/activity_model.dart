import 'package:json_annotation/json_annotation.dart';

import 'json_helpers.dart';

part 'activity_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ActivityModel {
  final String id;
  final String ticketId;

  /// Null when the action was performed by the system (service role).
  final String? actorId;
  final String action;
  final String? oldValue;
  final String? newValue;
  final String? note;
  final DateTime createdAt;

  /// Filled when the query embeds `actor:profiles(full_name)`.
  @JsonKey(readValue: readEmbeddedName)
  final String? actorName;

  /// Present when the query embeds `ticket:tickets(ticket_number,subject)`.
  @JsonKey(readValue: _readTicketNumber)
  final String? ticketNumber;
  @JsonKey(readValue: _readTicketSubject)
  final String? ticketSubject;

  const ActivityModel({
    required this.id,
    required this.ticketId,
    this.actorId,
    required this.action,
    this.oldValue,
    this.newValue,
    this.note,
    required this.createdAt,
    this.actorName,
    this.ticketNumber,
    this.ticketSubject,
  });

  static const String actionCreated = 'created';
  static const String actionAssigned = 'assigned';
  static const String actionStatusChanged = 'status_changed';
  static const String actionPriorityChanged = 'priority_changed';
  static const String actionCategoryChanged = 'category_changed';
  static const String actionResolved = 'resolved';
  static const String actionReopened = 'reopened';
  static const String actionClosed = 'closed';

  factory ActivityModel.fromJson(Map<String, dynamic> json) =>
      _$ActivityModelFromJson(json);
}

Object? _readTicketNumber(Map<dynamic, dynamic> json, String key) =>
    json['ticket'] is Map ? json['ticket']['ticket_number'] : null;

Object? _readTicketSubject(Map<dynamic, dynamic> json, String key) =>
    json['ticket'] is Map ? json['ticket']['subject'] : null;
