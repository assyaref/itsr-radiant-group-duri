// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comment_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CommentModel _$CommentModelFromJson(Map<String, dynamic> json) => CommentModel(
  id: json['id'] as String,
  ticketId: json['ticket_id'] as String,
  authorId: json['author_id'] as String,
  content: json['content'] as String,
  isInternal: json['is_internal'] as bool,
  createdAt: DateTime.parse(json['created_at'] as String),
  editedAt: json['edited_at'] == null
      ? null
      : DateTime.parse(json['edited_at'] as String),
  deletedAt: json['deleted_at'] == null
      ? null
      : DateTime.parse(json['deleted_at'] as String),
  authorName: readEmbeddedName(json, 'author_name') as String?,
);
