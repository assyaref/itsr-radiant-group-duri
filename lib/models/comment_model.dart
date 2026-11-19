import 'package:json_annotation/json_annotation.dart';

import 'json_helpers.dart';

part 'comment_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class CommentModel {
  final String id;
  final String ticketId;
  final String authorId;
  final String content;
  final bool isInternal;
  final DateTime createdAt;

  /// Set when the author edited the text.
  final DateTime? editedAt;

  /// Set when the comment was deleted (its text is then erased server-side).
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;

  /// Filled when the query embeds `author:profiles(full_name)`.
  @JsonKey(readValue: readEmbeddedName)
  final String? authorName;

  const CommentModel({
    required this.id,
    required this.ticketId,
    required this.authorId,
    required this.content,
    required this.isInternal,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
    this.authorName,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) =>
      _$CommentModelFromJson(json);
}
