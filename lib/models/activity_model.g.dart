// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ActivityModel _$ActivityModelFromJson(Map<String, dynamic> json) =>
    ActivityModel(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      actorId: json['actor_id'] as String?,
      action: json['action'] as String,
      oldValue: json['old_value'] as String?,
      newValue: json['new_value'] as String?,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      actorName: readEmbeddedName(json, 'actor_name') as String?,
      ticketNumber: _readTicketNumber(json, 'ticket_number') as String?,
      ticketSubject: _readTicketSubject(json, 'ticket_subject') as String?,
    );
