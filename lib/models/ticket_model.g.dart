// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ticket_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TicketModel _$TicketModelFromJson(Map<String, dynamic> json) => TicketModel(
  id: json['id'] as String,
  ticketNumber: json['ticket_number'] as String,
  subject: json['subject'] as String,
  description: json['description'] as String,
  category: json['category'] as String,
  subcategory: json['subcategory'] as String?,
  priority: json['priority'] as String,
  status: json['status'] as String,
  reporterId: json['reporter_id'] as String,
  assignedToId: json['assigned_to_id'] as String?,
  resolution: json['resolution'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  resolvedAt: json['resolved_at'] == null
      ? null
      : DateTime.parse(json['resolved_at'] as String),
  closedAt: json['closed_at'] == null
      ? null
      : DateTime.parse(json['closed_at'] as String),
  reporterName: readEmbeddedName(json, 'reporter_name') as String?,
  assigneeName: readEmbeddedName(json, 'assignee_name') as String?,
);
