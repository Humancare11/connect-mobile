/// Builds the compact quality sample sent in `call-stats` (admin-only call
/// report) from `RTCPeerConnection.getStats()` output. Pure: no timers, no
/// socket. Technical numbers only - never audio/video content or levels.
///
/// Mirrors the web client (frontend/src/utils/callStatsSample.js).
library;

/// One stats entry, decoupled from flutter_webrtc's `StatsReport` so this can
/// be tested without the plugin.
class CallStatsEntry {
  const CallStatsEntry(this.id, this.type, this.values);
  final String id;
  final String type;
  final Map<dynamic, dynamic> values;
}

/// Byte/packet counters kept between samples so the next one can be turned
/// into a bitrate and an interval packet-loss figure.
class CallStatsSnapshot {
  const CallStatsSnapshot({
    required this.atMs,
    required this.bytesIn,
    required this.bytesOut,
    required this.packets,
    required this.lost,
  });
  final int atMs;
  final num bytesIn;
  final num bytesOut;
  final num packets;
  final num lost;
}

class CallStatsResult {
  const CallStatsResult(this.sample, this.snapshot);
  final Map<String, dynamic> sample;
  final CallStatsSnapshot snapshot;
}

String classifyCallQuality({num? rtt, num? packetLoss}) {
  if (rtt == null && packetLoss == null) return 'unknown';
  if ((packetLoss != null && packetLoss > 0.1) || (rtt != null && rtt > 500)) return 'poor';
  if ((packetLoss != null && packetLoss > 0.03) || (rtt != null && rtt > 250)) return 'weak';
  return 'good';
}

num? _num(dynamic v) {
  if (v is num && v.isFinite) return v;
  if (v is String) {
    final parsed = num.tryParse(v);
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

CallStatsResult buildCallStatsSample(
  Iterable<CallStatsEntry> report,
  CallStatsSnapshot? previous,
  int nowMs, {
  Map<String, dynamic> extra = const {},
}) {
  final byId = <String, CallStatsEntry>{for (final r in report) r.id: r};

  CallStatsEntry? pair;
  for (final r in report) {
    if (r.type == 'transport') {
      final selected = r.values['selectedCandidatePairId'];
      if (selected is String && byId.containsKey(selected)) pair = byId[selected];
    }
  }
  if (pair == null) {
    for (final r in report) {
      if (r.type == 'candidate-pair' &&
          (r.values['selected'] == true || (r.values['nominated'] == true && r.values['state'] == 'succeeded'))) {
        pair = r;
      }
    }
  }

  num? rtt;
  var iceType = '';
  if (pair != null) {
    final r = _num(pair.values['currentRoundTripTime']);
    if (r != null) rtt = (r * 1000).round();
    final types = [
      byId[pair.values['localCandidateId']]?.values['candidateType'],
      byId[pair.values['remoteCandidateId']]?.values['candidateType'],
    ];
    if (types.contains('relay')) {
      iceType = 'relay';
    } else {
      for (final t in types) {
        if (t == 'host' || t == 'srflx' || t == 'prflx') {
          iceType = t as String;
          break;
        }
      }
    }
  }

  num packetsReceived = 0, packetsLost = 0, bytesIn = 0, bytesOut = 0;
  num? jitterSec;
  var resolution = '';
  for (final r in report) {
    if (r.type == 'inbound-rtp' && r.values['isRemote'] != true) {
      packetsReceived += _num(r.values['packetsReceived']) ?? 0;
      final lost = _num(r.values['packetsLost']) ?? 0;
      packetsLost += lost < 0 ? 0 : lost;
      bytesIn += _num(r.values['bytesReceived']) ?? 0;
      final w = _num(r.values['frameWidth']);
      final h = _num(r.values['frameHeight']);
      if ((r.values['kind'] ?? r.values['mediaType']) == 'video' && w != null && h != null && w > 0) {
        resolution = '${w.round()}x${h.round()}';
      }
      final j = _num(r.values['jitter']);
      if (j != null) jitterSec = (jitterSec == null || j > jitterSec) ? j : jitterSec;
    } else if (r.type == 'outbound-rtp' && r.values['isRemote'] != true) {
      bytesOut += _num(r.values['bytesSent']) ?? 0;
    }
  }

  final total = packetsReceived + packetsLost;
  num? packetLoss = total > 0 ? packetsLost / total : null;
  if (previous != null && total - previous.packets > 0) {
    final lostDelta = packetsLost - previous.lost;
    packetLoss = (lostDelta < 0 ? 0 : lostDelta) / (total - previous.packets);
  }

  int? bitrateKbps, outKbps;
  if (previous != null && nowMs > previous.atMs) {
    final secs = (nowMs - previous.atMs) / 1000;
    if (bytesIn >= previous.bytesIn) bitrateKbps = (((bytesIn - previous.bytesIn) * 8) / 1000 / secs).round();
    if (bytesOut >= previous.bytesOut) outKbps = (((bytesOut - previous.bytesOut) * 8) / 1000 / secs).round();
  }

  final pl = packetLoss == null ? null : (packetLoss > 1 ? 1 : (packetLoss * 1000).round() / 1000);
  final sample = <String, dynamic>{
    if (rtt != null) 'rtt': rtt,
    if (pl != null) 'packetLoss': pl,
    if (jitterSec != null) 'jitter': (jitterSec * 1000).round(),
    if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
    if (outKbps != null) 'outKbps': outKbps,
    if (iceType.isNotEmpty) 'iceType': iceType,
    if (resolution.isNotEmpty) 'resolution': resolution,
    'quality': classifyCallQuality(rtt: rtt, packetLoss: pl),
    ...extra,
  };
  return CallStatsResult(
    sample,
    CallStatsSnapshot(atMs: nowMs, bytesIn: bytesIn, bytesOut: bytesOut, packets: total, lost: packetsLost),
  );
}
