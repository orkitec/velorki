// The web side of a conditional export: what uses it is the same import on
// the phone side, which is the side dart_code_linter follows.
// ignore_for_file: unused-code

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

import 'cloudkit_web.dart';

final Logger _log = Logger('velorki.sync.cloudkit');

/// Apple's library, loaded from Apple's CDN as its licence asks (never
/// bundled), and only once the rider picks iCloud.
const String _script = 'https://cdn.apple-cloudkit.com/ck/2/cloudkit.js';

/// The element CloudKit JS would draw its sign-out button into; the app
/// draws its own, so the element is never on the page.
const String _signOutButtonId = 'velorki-apple-sign-out-button';

/// [CloudKitWeb] over CloudKit JS in this browser. [environment] is
/// `development` or `production`, [apiToken] that environment's web token.
CloudKitWeb createCloudKitWeb({
  required String apiToken,
  required String environment,
}) => _CloudKitJs(apiToken, environment);

const String _buttonView = 'velorki-apple-sign-in';
bool _buttonRegistered = false;

/// Apple's sign-in button, as CloudKit JS draws it (220 by 42 points) into
/// an element of the page; a click opens Apple's sign-in popup.
Widget appleSignInButton(CloudKitWeb api) {
  if (!_buttonRegistered) {
    _buttonRegistered = true;
    ui_web.platformViewRegistry.registerViewFactory(
      _buttonView,
      (int _) => web.HTMLDivElement()
        ..id = cloudKitSignInButtonId
        ..style.width = '100%'
        ..style.height = '100%',
    );
  }
  return SizedBox(
    width: 220,
    height: 42,
    child: HtmlElementView(
      viewType: _buttonView,
      onPlatformViewCreated: (_) => unawaited(_whenOnPage(api)),
    ),
  );
}

/// CloudKit JS finds the button's element by its id: asked to draw once
/// the element is on the page.
Future<void> _whenOnPage(CloudKitWeb api) async {
  for (var i = 0; i < 40; i++) {
    if (web.document.getElementById(cloudKitSignInButtonId) != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  try {
    await api.showSignIn();
  } on Object catch (e) {
    _log.info('no sign-in button: $e');
  }
}

class _CloudKitJs implements CloudKitWeb {
  _CloudKitJs(this._apiToken, this._environment);

  final String _apiToken;
  final String _environment;

  Future<JSObject>? _container;
  final StreamController<String?> _users =
      StreamController<String?>.broadcast();
  Future<String?>? _firstUser;
  String? _user;

  String get _sessionKey => 'velorki.cloudkit.session.$_environment';

  // --- Session --------------------------------------------------------------

  /// The session token, kept in local storage (CloudKit JS would keep it in
  /// a cookie): signed in once, a later visit is too until it runs out.
  String? get _session {
    try {
      return web.window.localStorage.getItem(_sessionKey);
    } on Object {
      return _memorySession;
    }
  }

  set _session(String? token) {
    _memorySession = token;
    try {
      if (token == null) {
        web.window.localStorage.removeItem(_sessionKey);
      } else {
        web.window.localStorage.setItem(_sessionKey, token);
      }
    } on Object {
      // No storage (a private window): the session lasts this visit.
    }
  }

  String? _memorySession;

  // --- Loading --------------------------------------------------------------

  Future<JSObject> _ready() => _container ??= _load().catchError((Object e) {
    _container = null;
    throw e;
  });

  Future<JSObject> _load() async {
    if (!globalContext.has('CloudKit')) {
      final script = web.HTMLScriptElement()
        ..src = _script
        ..async = true;
      final loaded = Completer<void>();
      script
        ..onload = ((web.Event _) => loaded.complete()).toJS
        ..onerror = ((web.Event _) => loaded.completeError(
          const CloudKitException(
            CkError('NETWORK_ERROR', reason: 'cloudkit.js did not load'),
          ),
        )).toJS;
      web.document.head!.append(script);
      await loaded.future;
    }
    final cloudKit = globalContext['CloudKit']! as JSObject;
    final store = JSObject()
      ..['getToken'] = ((JSString _) => _session?.toJS).toJS
      ..['putToken'] = ((JSString _, JSAny? token) {
        final value = token.dartify();
        _session = value is String ? value : null;
      }).toJS;
    final dark = web.window.matchMedia('(prefers-color-scheme: dark)').matches;
    final config =
        <String, Object?>{
              'containers': [
                {
                  'containerIdentifier': cloudKitContainer,
                  'apiTokenAuth': {
                    'apiToken': _apiToken,
                    'persist': true,
                    'signInButton': {
                      'id': cloudKitSignInButtonId,
                      'theme': dark ? 'white' : 'black',
                    },
                    'signOutButton': {'id': _signOutButtonId},
                  },
                  'environment': _environment,
                },
              ],
            }.jsify()!
            as JSObject;
    config['services'] = JSObject()..['authTokenStore'] = store;
    cloudKit.callMethod('configure'.toJS, config);
    final container =
        cloudKit.callMethod('getDefaultContainer'.toJS)! as JSObject;
    unawaited(_watchSignIns(container));
    unawaited(_watchSignOuts(container));
    return container;
  }

  Future<void> _watchSignIns(JSObject container) async {
    while (true) {
      try {
        final identity =
            await (container.callMethod('whenUserSignsIn'.toJS)!
                    as JSPromise<JSObject?>)
                .toDart;
        _signedIn(_recordNameOf(identity));
      } on Object catch (e) {
        // A sign-in popup that failed or was closed: CloudKit JS draws its
        // button again, and waits for the next.
        _log.info('sign-in failed: ${_errorOf(e)}');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _watchSignOuts(JSObject container) async {
    while (true) {
      await (container.callMethod('whenUserSignsOut'.toJS)! as JSPromise)
          .toDart;
      _user = null;
      _users.add(null);
    }
  }

  void _signedIn(String? user) {
    if (user == null || user == _user) return;
    _user = user;
    _users.add(user);
  }

  static String? _recordNameOf(JSObject? identity) {
    final name = identity?['userRecordName'].dartify();
    return name is String ? name : null;
  }

  // --- Auth -----------------------------------------------------------------

  @override
  Stream<String?> get users => _users.stream;

  @override
  Future<String?> userRecordName() async {
    if (_user != null) return _user;
    return _firstUser ??= _setUpAuth().whenComplete(() => _firstUser = null);
  }

  Future<String?> _setUpAuth() async {
    final container = await _ready();
    try {
      final identity =
          await (container.callMethod('setUpAuth'.toJS)!
                  as JSPromise<JSObject?>)
              .toDart;
      final user = _recordNameOf(identity);
      _signedIn(user);
      return user;
    } on Object catch (e) {
      throw CloudKitException(_errorOf(e));
    }
  }

  @override
  Future<void> showSignIn() async {
    if (_user != null) return;
    await _setUpAuth();
  }

  @override
  Future<void> signOut() async {
    final container = await _ready();
    container.callMethod('signOut'.toJS);
    _session = null;
    _user = null;
  }

  // --- Records --------------------------------------------------------------

  JSObject get _zone => {'zoneName': cloudKitZone}.jsify()! as JSObject;

  Future<JSObject> _database() async =>
      (await _ready())['privateCloudDatabase']! as JSObject;

  @override
  Future<List<CkResult>> modify(List<CkWrite> writes) async {
    final batch =
        (await _database()).callMethod(
              'newRecordsBatch'.toJS,
              JSObject()..['zoneID'] = _zone,
            )!
            as JSObject;
    for (final write in writes) {
      switch (write) {
        case CkDelete(:final name):
          batch.callMethod(
            'forceDelete'.toJS,
            [
              {'recordName': name},
            ].jsify(),
          );
        case CkSave(:final name, :final type, :final changeTag):
          final record =
              {
                    'recordName': name,
                    'recordType': type,
                    'recordChangeTag': ?changeTag,
                    'fields': {
                      for (final MapEntry(:key, :value) in write.fields.entries)
                        key: {'value': value.value, 'type': value.type},
                    },
                  }.jsify()!
                  as JSObject;
          if (write.body case final body?) {
            // A Blob, which CloudKit JS uploads and swaps for its receipt.
            final blob = web.Blob(
              [body.toJS].toJS,
              web.BlobPropertyBag(type: 'application/gzip'),
            );
            (record['fields']! as JSObject)['body'] = JSObject()
              ..['value'] = blob;
          }
          batch.callMethod(
            (changeTag == null ? 'create' : 'replace').toJS,
            [record].toJS,
          );
      }
    }
    final body = await _body(batch.callMethod('commit'.toJS)! as JSPromise);
    return _results(body['records'], [for (final w in writes) w.name]);
  }

  @override
  Future<List<CkResult>> lookup(List<String> names) async {
    final response =
        (await _database()).callMethod(
              'fetchRecords'.toJS,
              [
                for (final name in names) {'recordName': name},
              ].jsify(),
              JSObject()..['zoneID'] = _zone,
            )!
            as JSPromise;
    return _results((await _body(response))['records'], names);
  }

  @override
  Future<CkZoneChanges> zoneChanges(String? syncToken) async {
    final response =
        (await _database()).callMethod(
              'fetchRecordZoneChanges'.toJS,
              [
                {
                  'zoneID': {'zoneName': cloudKitZone},
                  'syncToken': ?syncToken,
                  'resultsLimit': 100,
                },
              ].jsify(),
            )!
            as JSPromise;
    final zones = (await _body(response))['zones'];
    final zone = zones is List && zones.isNotEmpty ? zones.first : null;
    if (zone is! Map) {
      throw const CloudKitException(CkError('UNEXPECTED_SERVER_RESPONSE'));
    }
    if (zone['serverErrorCode'] case final String code) {
      throw CloudKitException(CkError(code, reason: zone['reason'] as String?));
    }
    return CkZoneChanges(
      records: [
        for (final r in (zone['records'] as List?) ?? const [])
          if (r is Map) _recordOf(r),
      ],
      syncToken: zone['syncToken'] as String? ?? '',
      moreComing: zone['moreComing'] == true,
    );
  }

  @override
  Future<void> createZone() async {
    final response =
        (await _database()).callMethod(
              'saveRecordZones'.toJS,
              [
                {'zoneName': cloudKitZone},
              ].jsify(),
            )!
            as JSPromise;
    final zones = (await _body(response))['zones'];
    final zone = zones is List && zones.isNotEmpty ? zones.first : null;
    if (zone case {'serverErrorCode': final String code}) {
      throw CloudKitException(CkError(code));
    }
  }

  @override
  Future<Uint8List> download(String url) async {
    // CloudKit's asset URL has a placeholder for the file name.
    final href = url.replaceAll(r'${f}', 'body.json.gz');
    try {
      final response = await web.window.fetch(href.toJS).toDart;
      if (!response.ok) {
        throw CloudKitException(
          CkError(
            response.status >= 500 ? 'SERVICE_UNAVAILABLE' : 'NOT_FOUND',
            reason: 'asset ${response.status}',
          ),
        );
      }
      return (await response.arrayBuffer().toDart).toDart.asUint8List();
    } on CloudKitException {
      rethrow;
    } on Object catch (e) {
      throw CloudKitException(CkError('NETWORK_ERROR', reason: '$e'));
    }
  }

  // --- Plumbing ---------------------------------------------------------------

  /// The server's answer as JSON, in the order of the request; a rejected
  /// call as [CloudKitException].
  static Future<Map<String, Object?>> _body(JSPromise promise) async {
    final JSAny? response;
    try {
      response = await promise.toDart;
    } on Object catch (e) {
      throw CloudKitException(_errorOf(e));
    }
    final http = (response as JSObject?)?['httpResponse'] as JSObject?;
    final body = http?['body'];
    final decoded = body == null ? null : jsonDecode(_stringify(body));
    if (decoded is! Map<String, Object?>) {
      throw const CloudKitException(CkError('UNEXPECTED_SERVER_RESPONSE'));
    }
    return decoded;
  }

  static List<CkResult> _results(Object? records, List<String> names) {
    final byName = <String, CkResult>{};
    final list = records is List ? records : const [];
    for (final (i, r) in list.indexed) {
      if (r is! Map) continue;
      final name =
          r['recordName'] as String? ?? (i < names.length ? names[i] : '');
      byName[name] = r['serverErrorCode'] is String
          ? CkResult(
              error: CkError(
                r['serverErrorCode']! as String,
                recordName: name,
                reason: r['reason'] as String?,
              ),
            )
          : CkResult(record: _recordOf(r));
    }
    return [
      for (final name in names)
        byName[name] ??
            CkResult(
              error: CkError('UNEXPECTED_SERVER_RESPONSE', recordName: name),
            ),
    ];
  }

  static CkRecord _recordOf(Map<Object?, Object?> r) {
    final fields = <String, Object?>{};
    String? bodyUrl;
    for (final MapEntry(:key, :value)
        in ((r['fields'] as Map?) ?? const {}).entries) {
      final v = value is Map ? value['value'] : null;
      if (key == 'body') {
        bodyUrl = v is Map ? v['downloadURL'] as String? : null;
      } else if (v is String || v is num) {
        fields['$key'] = v;
      }
    }
    return CkRecord(
      name: r['recordName']! as String,
      type: r['recordType'] as String?,
      changeTag: r['recordChangeTag'] as String?,
      fields: fields,
      bodyUrl: bodyUrl,
      deleted: r['deleted'] == true,
    );
  }

  static CkError _errorOf(Object error) {
    try {
      final json = jsonDecode(_stringify(error as JSAny));
      if (json is Map) {
        final code =
            json['serverErrorCode'] as String? ??
            json['ckErrorCode'] as String? ??
            'UNKNOWN_ERROR';
        return CkError(
          code,
          recordName: json['recordName'] as String?,
          reason: json['reason'] as String?,
        );
      }
    } on Object {
      // Not a CloudKit error.
    }
    return CkError('UNKNOWN_ERROR', reason: '$error');
  }

  static String _stringify(JSAny value) =>
      ((globalContext['JSON']! as JSObject).callMethod(
        'stringify'.toJS,
        value,
      ) as JSString?)?.toDart ??
      'null';
}
