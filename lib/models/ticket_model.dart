import 'package:json_annotation/json_annotation.dart';

import 'json_helpers.dart';

part 'ticket_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class TicketModel {
  final String id;
  final String ticketNumber;
  final String subject;
  final String description;
  final String category;
  final String? subcategory;
  final String priority;
  final String status;
  final String reporterId;
  final String? assignedToId;
  final String? resolution;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;

  /// Filled when the query embeds `reporter:profiles!tickets_reporter_id_fkey(full_name)`.
  @JsonKey(readValue: readEmbeddedName)
  final String? reporterName;

  /// Filled when the query embeds `assignee:profiles!tickets_assigned_to_id_fkey(full_name)`.
  @JsonKey(readValue: readEmbeddedName)
  final String? assigneeName;

  const TicketModel({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    required this.description,
    required this.category,
    this.subcategory,
    required this.priority,
    required this.status,
    required this.reporterId,
    this.assignedToId,
    this.resolution,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
    this.closedAt,
    this.reporterName,
    this.assigneeName,
  });

  bool get isFinished => status == 'resolved' || status == 'closed';

  factory TicketModel.fromJson(Map<String, dynamic> json) =>
      _$TicketModelFromJson(json);
}
