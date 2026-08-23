/// Network camera (MJPEG rig stream) tests — pure Dart: the frame parser
/// against synthetic byte streams, and the client against http's
/// MockClient.streaming. No hardware, no network.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokemon_strategy_app/src/recognition/network_camera.dart';

/// A tiny fake JPEG: SOI + APP0-ish filler + EOI. [seed] varies the body so
/// frames are distinguishable; body bytes stay < 0x80 so no fake markers.
Uint8List fakeJpeg(int seed, {int bodyLen = 64}) {
  final b = BytesBuilder();
  b.add([0xFF, 0xD8, 0xFF, 0xE0]);
  for (var i = 0; i < bodyLen; i++) {
    b.addByte((seed + i) % 0x7F);
  }
  b.add([0xFF, 0xD9]);
  return b.toBytes();
}

List<int> boundary() =>
    '\r\n--frame\r\nContent-Type: image/jpeg\r\n\r\n'.codeUnits;

void main() {
  group('normalizeStreamUrl', () {
    test('bare IP gets rig defaults', () {
      expect(normalizeStreamUrl('192.168.4.2').toString(),
          'http://192.168.4.2:81/stream');
    });
    test('host with port keeps port, gets /stream', () {
      expect(normalizeStreamUrl('192.168.4.2:8080').toString(),
          'http://192.168.4.2:8080/stream');
    });
    test('full URL passes through', () {
      expect(normalizeStreamUrl('http://10.0.0.5:8080/video').toString(),
          'http://10.0.0.5:8080/video');
    });
    test('blank is null', () {
      expect(normalizeStreamUrl('   '), isNull);
    });
  });

  group('MjpegFrameParser', () {
    test('extracts frames delivered with multipart boundaries', () {
      final f1 = fakeJpeg(1), f2 = fakeJpeg(2);
      final stream = <int>[...boundary(), ...f1, ...boundary(), ...f2];
      final parser = MjpegFrameParser();
      final out = <Uint8List>[];
      out.addAll(parser.add(stream));
      expect(out, hasLength(2));
      expect(out[0], equals(f1));
      expect(out[1], equals(f2));
    });

    test('reassembles frames split across arbitrary chunk sizes', () {
      final f1 = fakeJpeg(3), f2 = fakeJpeg(4, bodyLen: 200);
      final stream = <int>[...boundary(), ...f1, ...boundary(), ...f2];
      for (final chunkSize in [1, 2, 3, 7, 13, 50]) {
        final parser = MjpegFrameParser();
        final out = <Uint8List>[];
        for (var i = 0; i < stream.length; i += chunkSize) {
          final end =
              (i + chunkSize < stream.length) ? i + chunkSize : stream.length;
          out.addAll(parser.add(stream.sublist(i, end)));
        }
        expect(out, hasLength(2), reason: 'chunkSize $chunkSize');
        expect(out[0], equals(f1), reason: 'chunkSize $chunkSize');
        expect(out[1], equals(f2), reason: 'chunkSize $chunkSize');
      }
    });

    test('survives a marker split exactly at a chunk boundary', () {
      final f = fakeJpeg(5);
      final parser = MjpegFrameParser();
      // Split between the 0xFF and 0xD9 of the EOI marker.
      final head = f.sublist(0, f.length - 1);
      final tail = f.sublist(f.length - 1);
      expect(parser.add(head), isEmpty);
      final out = parser.add(tail);
      expect(out, hasLength(1));
      expect(out.single, equals(f));
    });

    test('drops garbage that never becomes a frame', () {
      final parser = MjpegFrameParser(maxBuffer: 512);
      final junk = List<int>.filled(600, 0x20);
      expect(parser.add(junk), isEmpty);
      // After the reset it still parses a clean frame.
      final f = fakeJpeg(6);
      expect(parser.add(f).single, equals(f));
    });
  });

  group('NetworkCameraClient', () {
    test('emits each frame from a streamed response', () async {
      final f1 = fakeJpeg(7), f2 = fakeJpeg(8);
      final chunks = <List<int>>[
        boundary(),
        f1.sublist(0, 10),
        f1.sublist(10),
        boundary(),
        f2,
      ];
      final client = NetworkCameraClient(
        clientFactory: () => MockClient.streaming((request, _) async {
          expect(request.url.toString(), 'http://rig.local:81/stream');
          return http.StreamedResponse(Stream.fromIterable(chunks), 200);
        }),
      );
      final frames =
          await client.frames(Uri.parse('http://rig.local:81/stream')).toList();
      expect(frames, hasLength(2));
      expect(frames[0], equals(f1));
      expect(frames[1], equals(f2));
    });

    test('non-200 surfaces as a NetworkCameraException', () async {
      final client = NetworkCameraClient(
        clientFactory: () => MockClient.streaming((request, _) async =>
            http.StreamedResponse(const Stream.empty(), 404)),
      );
      expect(
        client.frames(Uri.parse('http://rig.local:81/stream')).toList(),
        throwsA(isA<NetworkCameraException>()),
      );
    });
  });
}
