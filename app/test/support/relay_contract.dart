/// What the relay's contract documents for `POST /ai/plan`, copied out of
/// `web/openapi.yaml` so it reaches a device build, where that file is not.
///
/// The relay's own contract tests (`web/test/contract`) replay these same
/// examples byte for byte against the real handler; the app's
/// `relay_contract_test.dart` holds every copy here equal to the yaml. So
/// what [MockRelay] answers with is what the relay is proven to send, and an
/// edit to either side fails a test until the other follows.
///
/// No Flutter, no `dart:io`: imported by the widget tests and by
/// `integration_test/` alike.
library;

/// The `text/event-stream` examples of the 200 response, by name, exactly as
/// the yaml holds them: a block scalar, so one trailing newline where the
/// wire has a blank line. [onTheWire] adds it.
const Map<String, String> documentedPlanStreams = <String, String>{
  'plan': r''': open

event: route_request
data: {"distance_km":65,"loop":true,"start":{"use_current":true},"via":["Uetliberg"],"surface":"mixed","hills":"seek","traffic_tolerance":"low","stops":["cafe"],"profile_hint":"trekking","notes":"Hügelige Runde ab deinem Standort.","confidence":0.8}

event: done
data: {"usage":{"in":412,"out":96},"model":"some-model"}
''',
  'describe': r''': open

event: text
data: {"delta":"Diese Runde führt "}

event: done
data: {"usage":{"in":300,"out":110},"model":"some-model"}
''',
  'route': r''': open

event: route_advice
data: {"answer":"Americana, a café right by the road at 14.2 km, is about halfway.","findings":[{"kind":"food","place_id":"p1","text":"Americana, a café 6 m off the route.","fix":{"type":"add_stop","place_id":"p1"}}]}

event: done
data: {"usage":{"in":980,"out":120},"model":"some-model"}
''',
  'failure': r''': open

event: error
data: {"error":{"code":"invalid_request","message":"The proposed route was not usable: distance_km Too small: expected number to be >=5"}}
''',
};

/// The documented stream [name] as it goes over the wire: every frame, the
/// last one included, ends with a blank line.
String onTheWire(String name) {
  final value = documentedPlanStreams[name];
  if (value == null) {
    throw ArgumentError.value(name, 'name', 'no documented stream');
  }
  return '$value\n';
}

/// One documented error response of `POST /ai/plan`.
class DocumentedError {
  /// Creates the response.
  const DocumentedError({
    required this.component,
    required this.status,
    required this.body,
    this.headers = const <String, String>{},
  });

  /// Its name under `components/responses` in the yaml.
  final String component;

  /// The status `/ai/plan` lists it under.
  final int status;

  /// The example body, as JSON.
  final String body;

  /// Headers the component documents and the example implies.
  final Map<String, String> headers;
}

/// 400, the body did not validate.
const DocumentedError invalidRequest = DocumentedError(
  component: 'InvalidRequest',
  status: 400,
  body:
      '{"error":{"code":"invalid_request",'
      '"message":"redirect_uri is not allowed."}}',
);

/// 401, no or no entitled bearer.
const DocumentedError notEntitled = DocumentedError(
  component: 'NotEntitled',
  status: 401,
  body:
      '{"error":{"code":"not_entitled",'
      '"message":"An active Velorki subscription is required."}}',
);

/// 403, no `X-AI-Consent: 1`.
const DocumentedError consentRequired = DocumentedError(
  component: 'ConsentRequired',
  status: 403,
  body:
      '{"error":{"code":"consent_required",'
      '"message":"AI features require the rider to consent first."}}',
);

/// 429, with the `Retry-After` header the component documents.
const DocumentedError rateLimited = DocumentedError(
  component: 'RateLimited',
  status: 429,
  body:
      '{"error":{"code":"rate_limited",'
      '"message":"Too many requests. Please slow down.","retry_after_s":6}}',
  headers: <String, String>{'retry-after': '6'},
);

/// 503, a budget is spent or the model is not configured.
const DocumentedError unavailable = DocumentedError(
  component: 'Unavailable',
  status: 503,
  body:
      '{"error":{"code":"unavailable",'
      '"message":"Strava is not configured on this server."}}',
);

/// Every documented error response of `POST /ai/plan`.
const List<DocumentedError> documentedErrors = <DocumentedError>[
  invalidRequest,
  notEntitled,
  consentRequired,
  rateLimited,
  unavailable,
];

/// The message the relay's `error` event carries when the model ran past
/// `LLM_TIMEOUT_S` (`web/src/app/(api)/ai/plan/route.ts`); not an example in
/// the yaml, so the contract test finds it in the handler instead.
const String relayDeadlineMessage = 'The AI took too long to answer.';
