/// The relay's contract, read from `web/openapi.yaml` at test time, for the
/// tests that run on the host, where the repository is.
///
/// [OpenApi.check] is a [SchemaCheck] for [MockRelay]: it holds a JSON value
/// to a schema of `components/schemas`, with the keywords the yaml uses
/// (`type`, `required`, `properties`, `additionalProperties: false`,
/// `items`, `enum`, `const`, the bounds, `pattern`, `$ref`, `oneOf`,
/// `allOf` with `if`/`then`). Anything else in a schema fails loudly rather
/// than passing unchecked.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// The parsed `web/openapi.yaml`.
class OpenApi {
  OpenApi._(this.document);

  /// Reads the yaml next to the app: `flutter test` runs in `app/`.
  factory OpenApi.load() => _cached ??= OpenApi._(
    jsonDecode(
      jsonEncode(loadYaml(File('../web/openapi.yaml').readAsStringSync())),
    ) as Map<String, Object?>,
  );

  static OpenApi? _cached;

  /// The whole document, as plain JSON values.
  final Map<String, Object?> document;

  /// What `paths./ai/plan.post` says.
  Map<String, Object?> get aiPlan =>
      _at(document, ['paths', '/ai/plan', 'post']);

  /// The named `text/event-stream` examples of the 200 response.
  Map<String, Object?> get planStreamExamples => _at(aiPlan, [
    'responses',
    '200',
    'content',
    'text/event-stream',
    'examples',
  ]);

  /// The named request body examples.
  Map<String, Object?> get planRequestExamples =>
      _at(aiPlan, ['requestBody', 'content', 'application/json', 'examples']);

  /// `components.responses[name]`.
  Map<String, Object?> response(String name) =>
      _at(document, ['components', 'responses', name]);

  /// What is wrong with [json] as a `components/schemas/[schema]`; empty when
  /// nothing is.
  List<String> check(String schema, Object? json) {
    final problems = <String>[];
    _validate(
      {r'$ref': '#/components/schemas/$schema'},
      json,
      schema,
      problems,
    );
    return problems;
  }

  static Map<String, Object?> _at(
    Map<String, Object?> from,
    List<String> path,
  ) {
    Object? node = from;
    for (final key in path) {
      node = (node! as Map<String, Object?>)[key];
    }
    return node! as Map<String, Object?>;
  }

  Map<String, Object?> _resolve(String ref) {
    if (!ref.startsWith('#/')) throw UnsupportedError('remote \$ref $ref');
    return _at(document, ref.substring(2).split('/'));
  }

  static const Set<String> _annotations = {
    'description',
    'default',
    'examples',
    'example',
    'format',
  };

  void _validate(
    Map<String, Object?> schema,
    Object? value,
    String at,
    List<String> problems,
  ) {
    for (final key in schema.keys) {
      if (_annotations.contains(key)) continue;
      switch (key) {
        case r'$ref':
          _validate(_resolve(schema[key]! as String), value, at, problems);
        case 'type':
          if (!_isType(value, schema[key]! as String)) {
            problems.add('$at is not ${schema[key]}');
            return;
          }
        case 'required':
          if (value is Map) {
            for (final name in schema[key]! as List<Object?>) {
              if (!value.containsKey(name)) problems.add('$at.$name missing');
            }
          }
        case 'properties':
          if (value is Map) {
            final properties = schema[key]! as Map<String, Object?>;
            for (final entry in value.entries) {
              final sub = properties[entry.key];
              if (sub != null) {
                _validate(
                  sub as Map<String, Object?>,
                  entry.value,
                  '$at.${entry.key}',
                  problems,
                );
              }
            }
          }
        case 'additionalProperties':
          final allowed = schema[key];
          if (allowed == false && value is Map) {
            final known =
                (schema['properties'] as Map<String, Object?>? ?? const {}).keys
                    .toSet();
            for (final name in value.keys) {
              if (!known.contains(name)) problems.add('$at.$name not allowed');
            }
          } else if (allowed != true && allowed != false) {
            throw UnsupportedError('additionalProperties: $allowed');
          }
        case 'items':
          if (value is List) {
            for (final (i, item) in value.indexed) {
              _validate(
                schema[key]! as Map<String, Object?>,
                item,
                '$at[$i]',
                problems,
              );
            }
          }
        case 'enum':
          if (!(schema[key]! as List<Object?>).contains(value)) {
            problems.add('$at is $value, not one of ${schema[key]}');
          }
        case 'const':
          if (value != schema[key]) problems.add('$at is not ${schema[key]}');
        case 'minimum':
          if (value is num && value < (schema[key]! as num)) {
            problems.add('$at is $value, below ${schema[key]}');
          }
        case 'maximum':
          if (value is num && value > (schema[key]! as num)) {
            problems.add('$at is $value, above ${schema[key]}');
          }
        case 'minLength':
          if (value is String && value.length < (schema[key]! as int)) {
            problems.add('$at is shorter than ${schema[key]}');
          }
        case 'maxLength':
          if (value is String && value.length > (schema[key]! as int)) {
            problems.add('$at is longer than ${schema[key]}');
          }
        case 'maxItems':
          if (value is List && value.length > (schema[key]! as int)) {
            problems.add('$at has more than ${schema[key]} items');
          }
        case 'pattern':
          if (value is String &&
              !RegExp(schema[key]! as String).hasMatch(value)) {
            problems.add('$at "$value" does not match ${schema[key]}');
          }
        case 'oneOf':
          final matches = [
            for (final option in schema[key]! as List<Object?>)
              if (_matches(option! as Map<String, Object?>, value, at)) option,
          ];
          if (matches.length != 1) {
            problems.add('$at matches ${matches.length} of oneOf');
          }
        case 'allOf':
          for (final part in schema[key]! as List<Object?>) {
            _validate(part! as Map<String, Object?>, value, at, problems);
          }
        case 'if':
          final then = schema['then'] as Map<String, Object?>?;
          if (then != null &&
              _matches(schema[key]! as Map<String, Object?>, value, at)) {
            _validate(then, value, at, problems);
          }
        case 'then':
          break;
        default:
          throw UnsupportedError('schema keyword "$key" at $at');
      }
    }
  }

  bool _matches(Map<String, Object?> schema, Object? value, String at) {
    final problems = <String>[];
    _validate(schema, value, at, problems);
    return problems.isEmpty;
  }

  static bool _isType(Object? value, String type) => switch (type) {
    'object' => value is Map,
    'array' => value is List,
    'string' => value is String,
    'number' => value is num,
    'integer' => value is int || (value is double && value == value.round()),
    'boolean' => value is bool,
    'null' => value == null,
    _ => throw UnsupportedError('type $type'),
  };
}
