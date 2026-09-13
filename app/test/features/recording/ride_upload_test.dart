import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';

final DateTime _uploadedAt = DateTime.utc(2026, 9, 12, 12, 30);

RideUpload _upload({
  String status = RideUploadStatus.done,
  String? uploadId,
  String? activityId = '77',
  String? url = 'https://www.strava.com/activities/77',
  String? message,
}) => RideUpload(
  status: status,
  uploadedAt: _uploadedAt,
  uploadId: uploadId,
  activityId: activityId,
  url: url,
  message: message,
);

void main() {
  group('RideUploadStatus', () {
    test('the three values are what the column stores', () {
      expect(RideUploadStatus.pending, 'pending');
      expect(RideUploadStatus.done, 'done');
      expect(RideUploadStatus.failed, 'failed');
    });
  });

  group('RideUpload', () {
    test('an upload with an activity can be opened on the service', () {
      final upload = _upload();

      expect(upload.isDone, isTrue);
      expect(upload.isFailed, isFalse);
    });

    test('a finished upload without an activity cannot be opened', () {
      // The service said done but named no activity: there is no page to go
      // to, so the detail screen must offer the upload again.
      expect(_upload(activityId: null).isDone, isFalse);
      expect(_upload(activityId: '').isDone, isFalse);
    });

    test('an upload still being processed is neither done nor failed', () {
      final upload = _upload(
        status: RideUploadStatus.pending,
        uploadId: 'job-9',
        activityId: null,
        url: null,
      );

      expect(upload.isDone, isFalse);
      expect(upload.isFailed, isFalse);
      expect(upload.uploadId, 'job-9');
    });

    test('a rejected upload is reported as failed', () {
      final upload = _upload(
        status: RideUploadStatus.failed,
        activityId: null,
        url: null,
        message: 'duplicate of activity 12',
      );

      expect(upload.isFailed, isTrue);
      expect(upload.isDone, isFalse);
      expect(upload.message, 'duplicate of activity 12');
    });

    test('an activity id alone is not a finished upload', () {
      expect(_upload(status: RideUploadStatus.pending).isDone, isFalse);
      expect(_upload(status: RideUploadStatus.failed).isDone, isFalse);
    });

    test('a full record survives the uploads column', () {
      final upload = _upload(
        status: RideUploadStatus.failed,
        uploadId: 'job-9',
        message: 'rate limited',
      );

      expect(RideUpload.fromJson(upload.toJson()), upload);
    });

    test('the fields the service never sent are left out', () {
      final json = _upload(url: null).toJson();

      expect(json.containsKey('upload_id'), isFalse);
      expect(json.containsKey('url'), isFalse);
      expect(json.containsKey('message'), isFalse);
      expect(json['activity_id'], '77');
    });

    test('the upload time is written and read back as UTC', () {
      final upload = RideUpload(
        status: RideUploadStatus.done,
        uploadedAt: _uploadedAt.toLocal(),
        activityId: '77',
      );

      expect(upload.toJson()['uploaded_at'], '2026-09-12T12:30:00.000Z');
      expect(RideUpload.fromJson(upload.toJson()).uploadedAt.isUtc, isTrue);
    });

    test('a record from an older app counts as done at the epoch', () {
      // Neither field was written before; treating it as done keeps the
      // "Open on Strava" link working for rides uploaded back then.
      final upload = RideUpload.fromJson(const <String, Object?>{
        'activity_id': '77',
      });

      expect(upload.status, RideUploadStatus.done);
      expect(
        upload.uploadedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(upload.isDone, isTrue);
    });

    test('an unreadable time falls back to the epoch', () {
      final upload = RideUpload.fromJson(const <String, Object?>{
        'status': 'done',
        'uploaded_at': 'last tuesday',
        'activity_id': '77',
      });

      expect(
        upload.uploadedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('two records of the same upload are the same record', () {
      expect(_upload(), _upload());
      expect(_upload().hashCode, _upload().hashCode);
      expect(_upload(), isNot(_upload(activityId: '78')));
      expect(_upload(), isNot(_upload(status: RideUploadStatus.pending)));
    });

    test('toString names the status and the activity', () {
      expect(_upload().toString(), 'RideUpload(done, activity: 77)');
    });
  });

  group('encodeRideUploads / decodeRideUploads', () {
    test('every service keeps its own record', () {
      final uploads = <String, RideUpload>{
        'strava': _upload(),
        'rwgps': _upload(
          activityId: '9001',
          url: 'https://ridewithgps.com/trips/9001',
        ),
      };

      final decoded = decodeRideUploads(encodeRideUploads(uploads));

      expect(decoded, hasLength(2));
      expect(decoded['strava'], uploads['strava']);
      expect(decoded['rwgps']!.activityId, '9001');
    });

    test('a ride that was never uploaded has no records', () {
      expect(encodeRideUploads(const <String, RideUpload>{}), '{}');
      expect(decodeRideUploads('{}'), isEmpty);
      expect(decodeRideUploads(null), isEmpty);
      expect(decodeRideUploads(''), isEmpty);
    });

    test('an unreadable column yields no records rather than an error', () {
      expect(decodeRideUploads('not json'), isEmpty);
      expect(decodeRideUploads('[1, 2]'), isEmpty);
    });

    test('an entry that is not a record is skipped', () {
      final decoded = decodeRideUploads(
        jsonEncode(<String, Object?>{
          'strava': 77,
          'rwgps': <String, Object?>{'status': 'done', 'activity_id': '9001'},
        }),
      );

      expect(decoded.keys, <String>['rwgps']);
    });

    test('a pending record is replaced by the finished one', () {
      final pending = <String, RideUpload>{
        'strava': _upload(
          status: RideUploadStatus.pending,
          uploadId: 'job-9',
          activityId: null,
          url: null,
        ),
      };
      final stored = decodeRideUploads(encodeRideUploads(pending));
      expect(stored['strava']!.isDone, isFalse);

      final finished = <String, RideUpload>{...stored, 'strava': _upload()};

      final decoded = decodeRideUploads(encodeRideUploads(finished));
      expect(decoded, hasLength(1));
      expect(decoded['strava']!.isDone, isTrue);
      expect(decoded['strava']!.uploadId, isNull);
    });
  });
}
