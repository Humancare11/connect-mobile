import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/utils/call_stats_sample.dart';

void main() {
  CallStatsEntry e(String id, String type, Map<dynamic, dynamic> v) => CallStatsEntry(id, type, v);

  List<CallStatsEntry> relayReport({num bytes = 0, num lost = 0, num received = 1000}) => [
        e('T', 'transport', {'selectedCandidatePairId': 'P'}),
        e('P', 'candidate-pair', {'localCandidateId': 'L', 'remoteCandidateId': 'R', 'currentRoundTripTime': 0.12}),
        e('L', 'local-candidate', {'candidateType': 'relay'}),
        e('R', 'remote-candidate', {'candidateType': 'srflx'}),
        e('IV', 'inbound-rtp', {'kind': 'video', 'packetsReceived': received, 'packetsLost': lost, 'bytesReceived': bytes, 'jitter': 0.012, 'frameWidth': 640, 'frameHeight': 480}),
        e('OV', 'outbound-rtp', {'kind': 'video', 'bytesSent': bytes / 2}),
      ];

  test('relay on either end of the chosen pair is reported as relay', () {
    final r = buildCallStatsSample(relayReport(lost: 20, received: 980), null, 1000);
    expect(r.sample['iceType'], 'relay');
    expect(r.sample['rtt'], 120);
    expect(r.sample['jitter'], 12);
    expect(r.sample['resolution'], '640x480');
    expect(r.sample['packetLoss'], 0.02);
    expect(r.sample.containsKey('bitrateKbps'), isFalse);
  });

  test('bitrate and interval loss come from the previous snapshot', () {
    final first = buildCallStatsSample(relayReport(), null, 0);
    final second = buildCallStatsSample(relayReport(bytes: 500000, lost: 10, received: 1990), first.snapshot, 10000);
    expect(second.sample['bitrateKbps'], 400);
    expect(second.sample['outKbps'], 200);
    expect(second.sample['packetLoss'], 0.01);
  });

  test('a direct pair is never relay; an empty report is just "unknown"', () {
    final direct = [
      e('P', 'candidate-pair', {'selected': true, 'localCandidateId': 'L', 'remoteCandidateId': 'R', 'currentRoundTripTime': 0.02}),
      e('L', 'local-candidate', {'candidateType': 'host'}),
      e('R', 'remote-candidate', {'candidateType': 'srflx'}),
    ];
    expect(buildCallStatsSample(direct, null, 0).sample['iceType'], 'host');
    expect(buildCallStatsSample(const [], null, 0).sample, {'quality': 'unknown'});
  });

  test('quality buckets', () {
    expect(classifyCallQuality(rtt: 50, packetLoss: 0), 'good');
    expect(classifyCallQuality(rtt: 300, packetLoss: 0), 'weak');
    expect(classifyCallQuality(rtt: 50, packetLoss: 0.2), 'poor');
    expect(classifyCallQuality(), 'unknown');
  });
}
