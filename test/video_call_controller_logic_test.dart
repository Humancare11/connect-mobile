// Unit coverage for the pure, mockable-free logic in
// video_call_controller.dart. The controller class itself (offer/answer
// exchange, rebuild guard, pending-offer stash/replay, request-peer-rebuild
// handling) is not exercised here: it's driven entirely by flutter_webrtc's
// native RTCPeerConnection and the SocketService singleton, neither of which
// has a fake/mock available in this codebase, so constructing a testable
// instance would require a substantial mocking layer that doesn't exist yet.
// See the mobile video-call review report for a manual-trace-based
// assessment of that logic instead, and CLAUDE.md-adjacent test notes for a
// suggested follow-up once flutter_webrtc mocks exist.
import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/controllers/video_call_controller.dart';

void main() {
  group('extractDtlsFingerprint', () {
    test('extracts the fingerprint hash from a real-shaped SDP blob', () {
      const sdp = 'v=0\r\n'
          'o=- 123 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=fingerprint:sha-256 AB:CD:EF:01:23:45:67:89\r\n';
      expect(extractDtlsFingerprint(sdp), 'AB:CD:EF:01:23:45:67:89');
    });

    test('returns null for null input', () {
      expect(extractDtlsFingerprint(null), isNull);
    });

    test('returns null when no fingerprint line is present', () {
      expect(extractDtlsFingerprint('v=0\r\ns=-\r\n'), isNull);
    });

    test('is case-insensitive on the "fingerprint" attribute name', () {
      const sdp = 'a=FINGERPRINT:sha-256 11:22:33\r\n';
      expect(extractDtlsFingerprint(sdp), '11:22:33');
    });
  });

  group('deriveConnectionQuality', () {
    test('returns unknown when rtt is missing', () {
      expect(deriveConnectionQuality({}, null), 'unknown');
    });

    test('returns good for a low-rtt, no-history sample', () {
      expect(deriveConnectionQuality({'rtt': 50}, null), 'good');
    });

    test('returns poor when rtt alone exceeds the poor threshold', () {
      expect(deriveConnectionQuality({'rtt': 450}, null), 'poor');
    });

    test('returns weak when rtt alone is in the weak band', () {
      expect(deriveConnectionQuality({'rtt': 250}, null), 'weak');
    });

    test('derives loss ratio from the DELTA since the previous sample, not the cumulative total', () {
      // Cumulative loss ratio here would be huge (990/1000), but nothing was
      // lost in THIS interval, so quality must read good, not poor.
      final previous = {'packetsSent': 900.0, 'packetsLost': 90.0};
      final current = {'rtt': 50, 'packetsSent': 1000, 'packetsLost': 90};
      expect(deriveConnectionQuality(current, previous), 'good');
    });

    test('flags poor when the delta loss ratio in this interval is high', () {
      final previous = {'packetsSent': 100.0, 'packetsLost': 0.0};
      // +100 sent, +20 lost this interval => 20/120 ≈ 0.167 > 0.08 threshold.
      final current = {'rtt': 50, 'packetsSent': 200, 'packetsLost': 20};
      expect(deriveConnectionQuality(current, previous), 'poor');
    });
  });

  group('ChatMessage.fromJson', () {
    test('parses a fully-populated payload', () {
      final msg = ChatMessage.fromJson({
        'senderId': 'u1',
        'senderName': 'Alice',
        'text': 'hello',
        'fileUrl': 'http://x/y.png',
        'fileName': 'y.png',
        'fileType': 'image/png',
        'createdAt': '2026-01-01T00:00:00Z',
      });
      expect(msg.senderId, 'u1');
      expect(msg.senderName, 'Alice');
      expect(msg.text, 'hello');
      expect(msg.fileUrl, 'http://x/y.png');
    });

    test('defaults missing text/sender fields to empty strings rather than throwing', () {
      final msg = ChatMessage.fromJson(const {});
      expect(msg.senderId, '');
      expect(msg.senderName, '');
      expect(msg.text, '');
      expect(msg.fileUrl, isNull);
    });

    test('mints a unique localKey per message so list items keep stable identity', () {
      final a = ChatMessage.fromJson(const {'senderId': 'u1'});
      final b = ChatMessage.fromJson(const {'senderId': 'u1'});
      expect(a.localKey, isNot(equals(b.localKey)));
    });
  });
}
