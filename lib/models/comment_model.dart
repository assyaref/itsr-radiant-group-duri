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
    this.authorName,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) =>
      _$CommentModelFromJson(json);
}
