/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:serverpod/serverpod.dart' as _i1;

/// Uma resposta de triagem. Não é tabela: é serializada dentro de
/// TriageSession.answers como JSON.
abstract class TriageAnswer
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  TriageAnswer._({
    required this.question,
    required this.answer,
  });

  factory TriageAnswer({
    required String question,
    required String answer,
  }) = _TriageAnswerImpl;

  factory TriageAnswer.fromJson(Map<String, dynamic> jsonSerialization) {
    return TriageAnswer(
      question: jsonSerialization['question'] as String,
      answer: jsonSerialization['answer'] as String,
    );
  }

  String question;

  String answer;

  /// Returns a shallow copy of this [TriageAnswer]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TriageAnswer copyWith({
    String? question,
    String? answer,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TriageAnswer',
      'question': question,
      'answer': answer,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'TriageAnswer',
      'question': question,
      'answer': answer,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _TriageAnswerImpl extends TriageAnswer {
  _TriageAnswerImpl({
    required String question,
    required String answer,
  }) : super._(
         question: question,
         answer: answer,
       );

  /// Returns a shallow copy of this [TriageAnswer]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TriageAnswer copyWith({
    String? question,
    String? answer,
  }) {
    return TriageAnswer(
      question: question ?? this.question,
      answer: answer ?? this.answer,
    );
  }
}
