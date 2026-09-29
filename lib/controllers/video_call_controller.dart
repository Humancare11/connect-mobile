// Signaling / WebRTC / call-lifecycle controller, ported 1:1 from the
// behavior of frontend/src/pages/VideoCall.jsx's big `useEffect`. Kept
// deliberately close to the React control flow (same event names, same
// perfect-negotiation/ICE-restart machinery, same constants) rather than
// "improved," since the whole point is behavioral parity with the web app
// and the shared Node backend.
//
// This app only ever authenticates as a patient (see appointments_screen.dart
// — `initialRole` is always 'user', and there is no doctor login flow), so
// `isDoctor` below is always false at runtime. The branching is kept anyway
// because it's shared signaling/call-lifecycle logic (who is the "polite"
// peer in perfect negotiation, who can complete the appointment) mirrored
// from the same source the web app uses — not doctor-only UI.

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../services/api_service.dart';
import '../services/call_foreground_service.dart';
import '../services/ice_server_config.dart';
import '../services/socket_service.dart';
import '../services/token_storage_service.dart';
import '../utils/direct_upload.dart';

const Map<String, dynamic> kMediaConstraints = {
  'audio': {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
    'channelCount': {'ideal': 2},
    'sampleRate': {'ideal': 48000},
    'sampleSize': {'ideal': 16},
  },
  'video': {
    'width': {'ideal': 1280, 'max': 1920},
    'height': {'ideal': 720, 'max': 1080},
    'frameRate': {'ideal': 30, 'max': 30},
    'facingMode': 'user',
  },
};

const int kCameraBitrate = 1200000;
const int kVoiceBitrate = 64000;
const int kIceRestartDelayMs = 2500;
const int kConnectionFailTimeoutMs = 25000;
const int kIceMaxRecoveryAttempts = 4;
const int kIceRecoveryCooldownMs = 30000;
// How long to wait for a video-answer after sending an offer before treating
// it as lost — mirrors VideoCall.jsx's OFFER_ANSWER_TIMEOUT_MS. Without this,
// a dropped/never-arriving answer leaves the RTCPeerConnection permanently
// wedged in "have-local-offer", since nothing else ever rolls back a
// self-initiated offer.
const int kOfferAnswerTimeoutMs = 8000;
const int kStatsIntervalMs = 30000;
// How long a freshly (re)built RTCPeerConnection is protected from being
// torn down again by _handlePeerJoined's resumedCall-triggered rebuild
// check below. (Re)joining the room — which every rebuild's own
// startCallSession() does once local media is ready — makes the server
// echo this very "peer-joined" straight back to us whenever a peer is
// present, carrying resumedCall:true; that echo can arrive before a
// brand-new pc has any realistic chance to negotiate (native ICE/DTLS
// setup, offer/answer, isn't instant). Without this grace window, that
// echo alone could re-satisfy "resumed but not yet healthy" and tear the
// pc down again before it ever connects — an unbounded rebuild cascade.
// Mirrors VideoCall.jsx's REBUILD_GRACE_MS.
const int kRebuildGraceMs = 5000;

/// A remote offer stashed while no pc was ready (or a rebuild was running) is
/// dropped when older than this — the sender has long since rolled it back.
const int kPendingOfferMaxAgeMs = 15000;

/// A `request-peer-rebuild` is ignored when this side's pc is younger than
/// this: it was just rebuilt, so the request is almost certainly stale.
const int kPeerRebuildMinPcAgeMs = 5000;
// How long a mid-call drop (connection already reached "connected" at least
// once) is allowed to sit unrecovered before surfacing the manual "Retry"
// button — see _startReconnectStallWatch's call sites in
// _handleConnectionStateChange/_handleIceConnectionStateChange. Without this,
// the only place that ever arms the stall watch is the initial join in
// _handlePeerJoined, so a reconnect that stalls after the call was already
// live had no user-facing recovery path at all.
const int kMidCallReconnectStallMs = 12000;
// After this many reconnect-stall episodes in a row without a successful
// reconnect in between, the automatic ICE-restart machinery is clearly not
// going to resolve this on its own — stop presenting the stall banner as a
// "still working on it, hang tight" message and offer an explicit way to
// end the call instead of retrying silently forever. Mirrors
// VideoCall.jsx's identical MAX_RECONNECT_STALL_RETRIES.
const int kMaxReconnectStallRetries = 3;
// How many consecutive failed token-refresh heartbeat attempts (one every 4
// minutes — see _markInCall's _heartbeatTimer) are tolerated silently before
// treating the session as no longer authenticatable.
// ApiClient.refreshAccessToken collapses every failure reason (no stored
// refresh token, a non-2xx response, a network error) into a single
// `false`, so — unlike VideoCall.jsx's heartbeat, which can act immediately
// on a definitive 401/403 — this can only threshold on repetition. Kept
// slightly higher than the React side's threshold for that reason. Mirrors
// VideoCall.jsx's AUTH_REFRESH_FAILURE_THRESHOLD.
const int kAuthRefreshFailureThreshold = 3;
const int kChatSendCooldownMs = 300;
const int kPeerJoinTimeoutMs = 20000;
const int kMediaAcquireTimeoutMs = 20000;
// retryMediaPermissions() gets a tighter deadline than the initial join: the
// user is actively watching the "Retrying..." button, so a stuck permission
// prompt or native getUserMedia call must hand control back well before the
// full kMediaAcquireTimeoutMs — mirrors VideoCall.jsx's
// RETRY_MEDIA_PERMISSIONS_TIMEOUT_MS.
const int kRetryMediaPermissionsTimeoutMs = 10000;
// Telemetry events queued while the socket is disconnected are replayed once
// it reconnects — see VideoCallController._logEvent/_flushTelemetryQueue.
// Capped so a long outage can't grow this without bound (mirrors
// VideoCall.jsx's TELEMETRY_QUEUE_MAX).
const int kTelemetryQueueMax = 50;
// Chat messages sent while we can't be sure join-appointment-room has
// actually completed server-side are queued here and flushed once
// appointment-chat-history confirms it — see _roomJoinConfirmed/
// _flushChatQueue. Capped for the same reason as kTelemetryQueueMax.
const int kChatQueueMax = 20;
// ICE candidates received before the remote description is set are queued
// here until it is. Capped for the same reason as kTelemetryQueueMax — a
// long-delayed remote description (e.g. a stuck media-permission prompt)
// shouldn't let this grow without bound; drops the oldest once full.
const int kPendingCandidatesMax = 50;

// ── TEMPORARY: Retry-bug diagnostic logging ─────────────────────────────
// Added to investigate "blank video on the other side after tapping Retry".
// Logging only — no call/reconnect logic is changed by this block. Flip
// kRetryDebug to false (or delete this block and its call sites, all tagged
// "[RETRY-DEBUG]") once the investigation is closed. Mirrors
// VideoCall.jsx's RETRY_DEBUG/retryDebugLog.
const bool kRetryDebug = kDebugMode;

void retryDebugLog(bool isDoctor, String appointmentId, String label, [Object? data]) {
  if (!kRetryDebug) return;
  final role = isDoctor ? 'doctor' : 'patient';
  debugPrint(
    '[RETRY-DEBUG] ${DateTime.now().toIso8601String()} role=$role appt=$appointmentId $label ${data ?? ''}',
  );
}

/// DTLS fingerprint of an SDP blob. Real reconnect logic (NOT debug-only): a
/// different fingerprint means the peer rebuilt its RTCPeerConnection.
String? extractDtlsFingerprint(String? sdp) {
  if (sdp == null) return null;
  final match = RegExp(r'a=fingerprint:\S+\s+(\S+)', caseSensitive: false).firstMatch(sdp);
  return match?.group(1);
}

// TEMPORARY (RETRY_DEBUG): pulls the DTLS fingerprint out of an SDP blob so
// _handleOffer's diagnostic log can tell whether the peer's certificate (and
// therefore its RTCPeerConnection) changed between offers. Read-only parse,
// no effect on negotiation. Mirrors VideoCall.jsx's retryDebugExtractFingerprint.
String? retryDebugExtractFingerprint(String? sdp) {
  if (sdp == null) return null;
  final match = RegExp(r'a=fingerprint:\S+\s+(\S+)', caseSensitive: false).firstMatch(sdp);
  return match?.group(1);
}

// TEMPORARY (RETRY_DEBUG): samples getStats() every 2s for 20s (10 samples)
// after an offer is applied, logging the inbound-rtp video report so we can
// tell "media never arrived" apart from "media arrived but never rendered".
// Read-only — never touches the RTCPeerConnection's negotiation state.
// Mirrors VideoCall.jsx's retryDebugPollInboundVideoStats.
void retryDebugPollInboundVideoStats(
  RTCPeerConnection? pc,
  bool isDoctor,
  String appointmentId,
  String label,
) {
  if (!kRetryDebug || pc == null) return;
  var ticks = 0;
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    ticks += 1;
    try {
      final reports = await pc.getStats();
      Map<String, dynamic>? inboundVideo;
      for (final report in reports) {
        if (report.type == 'inbound-rtp' && report.values['kind'] == 'video') {
          inboundVideo = {
            'bytesReceived': report.values['bytesReceived'],
            'framesDecoded': report.values['framesDecoded'],
            'packetsReceived': report.values['packetsReceived'],
            'packetsLost': report.values['packetsLost'],
            'frameWidth': report.values['frameWidth'],
            'frameHeight': report.values['frameHeight'],
          };
        }
      }
      retryDebugLog(isDoctor, appointmentId, '$label:stats_tick_$ticks/10', {
        'inboundVideo': inboundVideo,
      });
    } catch (err) {
      retryDebugLog(isDoctor, appointmentId, '$label:stats_tick_$ticks/10:ERROR', {
        'message': err.toString(),
      });
    }
    if (ticks >= 10) timer.cancel();
  });
}

// Turns the stats already gathered by _startStatsCollection into a coarse,
// user-facing quality bucket. Ported from VideoCall.jsx's
// deriveConnectionQuality: packet loss is derived from the DELTA between
// this poll and the previous one (not the raw cumulative counter) — using
// the cumulative value directly would mean a single lost packet early in a
// long call marks the connection "poor" for its entire remaining duration.
String deriveConnectionQuality(
  Map<String, dynamic> diagnostics,
  Map<String, num>? previousSample,
) {
  final rtt = diagnostics['rtt'];
  if (rtt is! num) return 'unknown';

  var lossRatio = 0.0;
  if (previousSample != null) {
    final sentNow = diagnostics['packetsSent'];
    final lostNow = diagnostics['packetsLost'];
    if (sentNow is num && lostNow is num) {
      final deltaSent = sentNow - (previousSample['packetsSent'] ?? 0);
      final deltaLost = lostNow - (previousSample['packetsLost'] ?? 0);
      if (deltaSent > 0 && deltaLost > 0) {
        lossRatio = deltaLost / (deltaSent + deltaLost);
      }
    }
  }

  if (rtt > 400 || lossRatio > 0.08) return 'poor';
  if (rtt > 200 || lossRatio > 0.03) return 'weak';
  return 'good';
}

// Chat messages carry no server-issued id in the payloads this app
// receives, so a stable per-message identity has to be minted client-side
// the moment each one enters state (on receipt, not on send — see
// _handleChatMessage's comment on why sends aren't optimistic). Used as the
// chat ListView's item key instead of the list index, which would silently
// break (wrong item retains state/animates incorrectly) the moment anything
// other than pure appending is introduced — mirrors VideoCall.jsx's
// makeMessageKey()/_localKey.
int _messageKeySeq = 0;
String _generateMessageKey() {
  _messageKeySeq += 1;
  return 'msg-${DateTime.now().microsecondsSinceEpoch}-$_messageKeySeq';
}

class ChatMessage {
  final String localKey;
  final String senderId;
  final String senderName;
  final String text;
  final String? fileUrl;
  final String? fileName;
  final String? fileType;
  final String? createdAt;

  ChatMessage({
    String? key,
    required this.senderId,
    required this.senderName,
    this.text = '',
    this.fileUrl,
    this.fileName,
    this.fileType,
    this.createdAt,
  }) : localKey = key ?? _generateMessageKey();

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        senderId: (json['senderId'] ?? '').toString(),
        senderName: (json['senderName'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        fileUrl: json['fileUrl'] as String?,
        fileName: json['fileName'] as String?,
        fileType: json['fileType'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class VideoCallController extends ChangeNotifier {
  VideoCallController({
    required this.appointmentId,
    Map<String, dynamic>? initialAppointment,
    Map<String, dynamic>? initialDoctor,
    Map<String, dynamic>? initialPatient,
    String initialRole = '',
    this.onCompletedByPeer,
  })  : appt = initialAppointment,
        // Field is intentionally private; the parameter is intentionally
        // public (`initialDoctor`). A private named parameter (`this._initialDoctor`)
        // is a compile error, so an initializing formal isn't possible here.
        // ignore: prefer_initializing_formals
        _initialDoctor = initialDoctor,
        // ignore: prefer_initializing_formals
        _initialPatient = initialPatient,
        _initialRole = initialRole,
        activeRole = initialRole,
        apptLoading = initialAppointment == null;

  final String appointmentId;
  final Map<String, dynamic>? _initialDoctor;
  final Map<String, dynamic>? _initialPatient;
  final String _initialRole;
  final SocketService _socket = SocketService.instance;

  /// Called ~4s after the peer marks the appointment complete (patient side
  /// only) so the widget can navigate away. Kept as a callback instead of a
  /// Navigator call here, since the controller has no BuildContext.
  final VoidCallback? onCompletedByPeer;

  // ── Renderers (equivalent of the two <video> elements) ────────────────
  final RTCVideoRenderer mainRenderer = RTCVideoRenderer();
  final RTCVideoRenderer pipRenderer = RTCVideoRenderer();

  bool _disposed = false;
  bool _rendererReady = false;

  // ── Appointment ─────────────────────────────────────────────────────
  Map<String, dynamic>? appt;
  bool apptLoading;
  String apptError = '';
  String activeRole;
  bool _callSessionStarted = false;

  // This app only has a patient login flow (see class doc comment), so
  // there is never a logged-in doctor identity to attempt that role's
  // endpoint with, and a user identity is always present by the time this
  // screen is reachable (navigation requires being logged in already).
  bool get _hasUserIdentity => true;
  bool get _hasDoctorIdentity => false;

  // flutter_webrtc's Helper.switchCamera/setSpeakerphoneOn are native-only —
  // the web target has no front/back camera concept and routes audio output
  // however the browser tab's own device picker decided, so both controls
  // are hidden there rather than shown greyed-out for no reason.
  bool get supportsCameraSwitch => !kIsWeb;
  bool get supportsSpeakerToggle => !kIsWeb;

  Map<String, dynamic>? get _doctor {
    if (_initialDoctor != null && _initialDoctor.isNotEmpty) return _initialDoctor;
    final value = appt?['doctorId'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Map<String, dynamic>? get _user {
    if (_initialPatient != null && _initialPatient.isNotEmpty) return _initialPatient;
    final value = appt?['patientId'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String get doctorId => (_doctor?['_id'] ?? _doctor?['id'] ?? '').toString();
  String get userId => (_user?['_id'] ?? '').toString();

  String get apptDoctorId {
    final d = appt?['doctorId'];
    if (d is Map) return (d['_id'] ?? '').toString();
    return (d ?? '').toString();
  }

  String get apptPatientId {
    final p = appt?['patientId'];
    if (p is Map) return (p['_id'] ?? '').toString();
    return (p ?? '').toString();
  }

  /// Matches VideoCall.jsx exactly: gated purely on `confirmed`. (A prior
  /// port of this screen also allowed `assigned`, an unauthorized deviation
  /// from the backend's own semantics — removed.)
  bool get canJoinConsultation => appt?['status'] == 'confirmed';

  bool get isDoctor {
    if (activeRole.isNotEmpty) return activeRole == 'doctor';
    if (doctorId.isNotEmpty && apptDoctorId.isNotEmpty && doctorId == apptDoctorId) {
      return true;
    }
    if (userId.isNotEmpty && apptPatientId.isNotEmpty && userId == apptPatientId) {
      return false;
    }
    return _hasDoctorIdentity && !_hasUserIdentity;
  }

  Map<String, String> get currentUser {
    if (isDoctor) {
      return {
        'id': doctorId.isEmpty ? 'doctor' : doctorId,
        'name': (_doctor?['name'] ?? 'Doctor').toString(),
      };
    }
    return {
      'id': userId.isEmpty ? 'user' : userId,
      'name': (_user?['name'] ?? 'Patient').toString(),
    };
  }

  Map<String, dynamic>? get otherParty {
    final a = appt;
    if (a == null) return null;
    if (isDoctor) {
      final patient = a['patientId'];
      final name = (patient is Map ? patient['name'] : null) ?? 'Unknown Patient';
      return {
        'label': 'Patient',
        'name': name,
        'sub': a['problem'] ?? '',
        'initial': (name is String && name.isNotEmpty) ? name[0].toUpperCase() : 'P',
      };
    }
    final doc = a['doctorId'];
    final docName = (doc is Map ? doc['name'] : null) ?? 'Unknown';
    return {
      'label': 'Doctor',
      'name': 'Dr. $docName',
      'sub': (doc is Map ? doc['email'] : null) ?? '',
      'initial': (docName is String && docName.isNotEmpty) ? docName[0].toUpperCase() : 'D',
    };
  }

  // ── Media / peer connection ─────────────────────────────────────────
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCPeerConnection? _pc;
  // Wall-clock time _pc was constructed — see kRebuildGraceMs for why
  // _handlePeerJoined needs this instead of relying on a per-call debounce
  // alone (that would only protect a single rebuild, not the freshly
  // rebuilt pc a self "peer-joined" echo lands on next).
  DateTime _pcCreatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  // TEMPORARY (RETRY_DEBUG): last remote DTLS fingerprint applied, so
  // _handleOffer's diagnostic log can report whether an incoming offer's
  // fingerprint differs from the previous one (i.e. the peer rebuilt their
  // RTCPeerConnection). Read/written only by retry-debug logging.
  String? _retryDebugLastRemoteFingerprint;
  // Last remote DTLS fingerprint applied via an offer/answer (real logic, not
  // debug). Cleared on teardown and participant-left.
  String? _lastRemoteFingerprint;
  // A remote offer that arrived while _pc was null or a rebuild was running;
  // replayed once the new pc and local media are ready (see
  // _replayPendingRemoteOffer). Survives _teardownSession on purpose.
  Map<String, dynamic>? _pendingRemoteOffer;
  DateTime? _pendingRemoteOfferAt;
  // TEMPORARY (RETRY_DEBUG): previous connectionState/iceConnectionState so
  // the state-change handlers can log an old→new transition instead of just
  // the new value. Read/written only by retry-debug logging.
  RTCPeerConnectionState? _retryDebugPrevConnState;
  RTCIceConnectionState? _retryDebugPrevIceState;
  Completer<bool> _localReady = Completer<bool>();
  bool _isPolitePeer = false;

  // ── Perfect negotiation state ────────────────────────────────────────
  bool _makingOffer = false;
  bool _ignoreOffer = false;
  bool _settingRemoteAnswerPending = false;
  final List<dynamic> _pendingRemoteCandidates = [];
  Timer? _ignoreOfferResetTimer;
  final Random _idRng = Random();
  // The offerId of our own most recent outstanding offer, echoed back by the
  // peer's answer so a stale/replayed answer (e.g. socket.io reconnect
  // replay) can be told apart from a genuine fresh one — mirrors
  // VideoCall.jsx's pendingOfferIdRef.
  String? _pendingOfferId;
  Timer? _offerAnswerTimeoutTimer;
  // The offerId of the most recent remote offer we accepted — echoed back in
  // our video-answer so the offerer can correlate it. Also used by
  // retryMediaPermissions() when it answers a remote offer that arrived
  // before local media was ready — mirrors lastReceivedOfferIdRef.
  String? _lastReceivedOfferId;

  // ── Reconnect / ICE-restart machinery ───────────────────────────────
  Timer? _iceRestartTimer;
  Timer? _connectionFailTimer;
  Timer? _reconnectStallTimer;
  bool _restartRequestInFlight = false;
  int _iceRecoveryAttempts = 0;
  DateTime _lastIceRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _joinedSocketId = '';
  Timer? _joinTimeoutTimer;
  bool reconnectStalled = false;
  // How many times the stall banner has fired since the last successful
  // (re)connect — see kMaxReconnectStallRetries.
  int reconnectStallCount = 0;
  bool get reconnectStallExhausted => reconnectStallCount >= kMaxReconnectStallRetries;

  // ── Device connectivity ──────────────────────────────────────────────
  // Mirrors VideoCall.jsx's window online/offline listeners: a fully
  // offline device otherwise only surfaces indirectly, once the socket/ICE
  // timeouts eventually fire many seconds later.
  bool isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  // Mirrors VideoCall.jsx's hasConnectedOnceRef — distinguishes the first
  // "Establishing secure connection..." from a later "Reconnecting..." on
  // the waiting overlay.
  bool hasConnectedOnce = false;
  // Set when the connection drops (disconnected/failed) after having been
  // up at least once, and consumed the next time either connection-state
  // handler below reports "connected"/"completed" again — see
  // _refreshRemoteStreamBinding.
  bool _remoteRebindPending = false;
  // Guards _handleNetworkInterfaceChanged() against overlapping runs — e.g.
  // a device oscillating between two towers firing onConnectivityChanged
  // again before the previous check's settle delay has finished. See that
  // method's own doc comment for the full recovery-path reasoning.
  bool _networkChangeRecoveryInProgress = false;
  bool retryingMedia = false;

  // ── Call lifecycle ────────────────────────────────────────────────────
  bool _completedFlag = false;
  // Tracks whether the Android foreground service has been started for the
  // current session, so it's requested exactly once as soon as local media
  // is ready (see _startForegroundServiceIfNeeded) instead of waiting for
  // offer/answer signaling to finish in _markInCall — a patient who
  // backgrounds the app while still waiting for the other party to join
  // otherwise has no foreground-service protection during that window.
  bool _foregroundServiceStarted = false;
  Timer? _callTimer;
  Timer? _heartbeatTimer;
  // Consecutive failed token-refresh heartbeat attempts — see
  // kAuthRefreshFailureThreshold and _markInCall.
  int _authRefreshFailureCount = 0;
  Timer? _statsTimer;
  bool isReady = false;
  bool peerJoined = false;
  bool peerLeft = false;
  bool inCall = false;
  bool isRemoteConnected = false;
  String connectionState = 'idle';
  // good | weak | poor | unknown — mirrors VideoCall.jsx's `connectionQuality`
  // state, derived from stats polling in _startStatsCollection below.
  String connectionQuality = 'unknown';
  // Previous stats poll's packet counters, so quality is derived from the
  // delta between polls (see _deriveConnectionQuality) rather than a
  // misleading cumulative total — same reasoning as VideoCall.jsx's
  // lastStatsSampleRef.
  Map<String, num>? _lastStatsSample;
  // Most recent getStats() RTT sample (ms), used to widen the offer-answer
  // timeout on high-latency links — mirrors VideoCall.jsx's lastRttMsRef.
  num? _lastRttMs;
  int callDuration = 0;
  bool isMuted = false;
  bool isCamOff = false;
  // Mirrors isCamOff, but for the remote peer — driven entirely by the
  // 'camera-state' signaling event (see _announceCameraState/
  // _handleCameraState), not by anything WebRTC reports on its own. Disabling
  // a video track via `enabled = false` on native mobile (this app, via
  // flutter_webrtc) stops producing frames entirely; browsers, by contrast,
  // keep sending black frames per the MediaStreamTrack spec. Without an
  // explicit signal, the peer would have no way to distinguish "camera
  // deliberately turned off" from "the video froze" — it would just see a
  // stuck last frame either way.
  bool peerCameraOff = false;
  // Audio-route and front/back-camera state have no equivalent in
  // VideoCall.jsx (a browser tab has neither concept) — genuinely
  // mobile-only affordances. Both default to the platform's own default
  // behavior (front camera; video calls auto-route to loudspeaker on
  // Android/iOS) so the toggle only kicks in once the user actually taps it.
  bool isSpeakerOn = true;
  bool isFrontCamera = true;
  bool isSwapped = false;
  // Re-entrancy guard for switchCamera() — see its own comment.
  bool _switchingCamera = false;
  // Public (not the usual leading-underscore private field) so the screen
  // can disable/show a loading state on the manual "Retry" button while a
  // forceReconnect() is already underway — mirrors retryingMedia's role for
  // the camera-error retry button. The guard behavior this already provided
  // internally (forceReconnect's own re-entrancy check, and the automatic
  // rebuild check in _handlePeerJoined) is unchanged.
  bool reconnectInProgress = false;
  bool camError = false;
  String camErrorReason = '';
  // True when the camera/mic permission is permanently denied ("don't ask
  // again") — retrying getUserMedia can't re-prompt the OS in that state,
  // so the UI needs to offer a way to the system settings screen instead.
  bool camPermissionPermanentlyDenied = false;
  // idle | checking | ready | failed — mirrors React's `deviceCheck.status`.
  String deviceCheckStatus = 'idle';
  String deviceCheckCamera = 'unknown';
  String deviceCheckMicrophone = 'unknown';
  String deviceCheckSpeaker = 'unknown';
  bool completing = false;
  String inlineError = '';
  Timer? _inlineErrorTimer;
  bool showCompletedOverlay = false;

  // ── Chat ──────────────────────────────────────────────────────────────
  bool chatOpen = false;
  final List<ChatMessage> messages = [];
  int unreadCount = 0;
  bool uploadingFile = false;
  bool chatSendCoolingDown = false;
  Timer? _chatSendCooldownTimer;

  // ── Prescription notification (patient-facing toast) ───────────────────
  Map<String, dynamic>? prescriptionNotif;
  Timer? _prescriptionTimer;

  String iceConfigError = '';
  bool _fetchingIceConfig = false;

  // ─────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await mainRenderer.initialize();
    await pipRenderer.initialize();
    _rendererReady = true;
    if (_disposed) {
      // dispose() may already have run while the awaits above were still
      // pending — it would have seen _rendererReady still false at that
      // point and skipped disposing the renderers, so finish that cleanup
      // here instead of leaking their native textures.
      mainRenderer.dispose();
      pipRenderer.dispose();
      return;
    }

    unawaited(_initConnectivityWatch());

    if (appt != null) {
      apptLoading = false;
      notifyListeners();
      _afterApptLoaded();
    }
    await fetchAppointment();
  }

  List<ConnectivityResult> _lastConnectivityResults = const [];

  bool _connectivityResultsChanged(
    List<ConnectivityResult> a,
    List<ConnectivityResult> b,
  ) {
    final setA = a.toSet();
    final setB = b.toSet();
    return setA.length != setB.length || !setA.containsAll(setB);
  }

  Future<void> _initConnectivityWatch() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      if (_disposed) return;
      _lastConnectivityResults = initial;
      isOffline = initial.every((r) => r == ConnectivityResult.none);
      notifyListeners();
    } catch (_) {
      // Best-effort — if the platform channel isn't available, the offline
      // banner simply never shows, same as VideoCall.jsx on a browser
      // without connectivity APIs.
    }
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (_disposed) return;
      final offline = results.every((r) => r == ConnectivityResult.none);
      final networkChanged = _connectivityResultsChanged(
        results,
        _lastConnectivityResults,
      );
      _lastConnectivityResults = results;
      final wasOffline = isOffline;

      if (offline != isOffline) {
        isOffline = offline;
        notifyListeners();
      }

      // Connectivity is back: reconnect signaling right now instead of
      // waiting out the socket client's backoff timer.
      if (!offline && (wasOffline || networkChanged) && !_socket.connected) {
        retryDebugLog(isDoctor, appointmentId, 'connectivity:socket_connect_now');
        _socket.connect();
      }

      // The OS reports a fully offline device almost instantly — far sooner
      // than libwebrtc's own ICE consent-check can notice a dead transport
      // (several seconds, sometimes tens of seconds). Without this, the last
      // received frame just sits frozen on screen with no indication
      // anything is wrong until that real state-change callback eventually
      // fires. Surface the "Reconnecting" UI immediately instead, and mark
      // the remote renderer for a rebind so it doesn't stay stuck on the
      // stale frame once media actually resumes — mirrors what
      // _handleConnectionStateChange/_handleIceConnectionStateChange already
      // do for a genuine pc-level drop.
      if (offline && !wasOffline && _pc != null && hasConnectedOnce) {
        connectionState = 'connecting';
        isRemoteConnected = false;
        _remoteRebindPending = true;
        notifyListeners();
        if (inCall) _startReconnectStallWatch(kMidCallReconnectStallMs);
      }

      // A network handoff (e.g. WiFi -> cellular) can silently degrade an
      // already-established connection well before libwebrtc's own ICE
      // consent-check notices (that can take ~20-30s). Nudge a restart
      // proactively instead of waiting it out — _scheduleIceRestart() is a
      // no-op if the connection turns out fine by the time its own 2.5s
      // debounce timer fires. That "fine" outcome is exactly the case that
      // used to leave the remote video renderer with no path back to a
      // fresh frame (connectionState==connected is proof the transport
      // recovered, not proof the renderer is still painting) — arm the
      // same rebind flag the offline branch above uses, and let
      // _handleNetworkInterfaceChanged() below consume it if nothing else
      // (a genuine disconnect/reconnect cycle) already does.
      if (!offline && networkChanged && _pc != null) {
        if (hasConnectedOnce) _remoteRebindPending = true;
        // The outage above may have been a false alarm — e.g. a brief
        // connectivity-API flicker the peer connection itself never actually
        // noticed. Resync from the pc's real state first so an already-
        // healthy connection clears the "Reconnecting" banner right away,
        // rather than only via an ICE restart that scheduleIceRestart()
        // would skip as a no-op anyway. If this does end up calling
        // _handleConnectedState(), it consumes the flag just armed above
        // itself, and _handleNetworkInterfaceChanged() below correctly
        // finds nothing left to do.
        _resyncConnectionStateFromPeerConnection();
        _scheduleIceRestart();
        unawaited(_handleNetworkInterfaceChanged());
      }
    });
  }

  // Network interface changes (Wi-Fi <-> mobile data) can silently degrade
  // the bundled audio/video transport without RTCPeerConnection ever
  // reporting "disconnected" — libwebrtc's own ICE consent-check can
  // re-nominate a working candidate pair, or simply never notice a brief
  // enough gap, fast enough that connectionState never leaves "connected".
  // When that happens, _resyncConnectionStateFromPeerConnection() and
  // _scheduleIceRestart()'s own guard (both called just above, unchanged)
  // correctly decline to do anything further — the transport genuinely is
  // fine, so there is nothing to reconnect. But "the transport is fine" is
  // not proof the remote video renderer is still painting fresh frames: the
  // same track survives untouched, pc.onTrack never re-fires, and nothing
  // else ever revisits the renderer binding. This gives the existing stack
  // a short, fixed window to either genuinely fail (in which case the
  // untouched connection-state-change handlers and _scheduleIceRestart's
  // own timer already own recovery from there — this method does nothing
  // further in that case) or silently self-heal; only once neither of
  // those is going to trigger a rebind on its own does this proactively run
  // the exact same rebind _handleConnectedState() already trusts for the
  // analogous "recovered, same track" case. Idempotent and race-safe:
  // _remoteRebindPending is the single shared signal armed by the call site
  // above — if a genuine disconnect/reconnect cycle (or
  // _resyncConnectionStateFromPeerConnection itself) beats this method to
  // it, _handleConnectedState() will already have cleared the flag by the
  // time this checks it, and this becomes a no-op.
  Future<void> _handleNetworkInterfaceChanged() async {
    if (_networkChangeRecoveryInProgress || _disposed) return;
    final pc = _pc;
    if (pc == null || !hasConnectedOnce) return;
    // A manual Retry, or an app-resume recovery, is already actively
    // driving this same PeerConnection toward a known state — piling
    // another recovery attempt on top could race a rebuild in progress
    // rather than help it. Those paths already cover their own rebind
    // needs (forceReconnect tears down and re-establishes from scratch;
    // _verifyConnectionAfterResume/_reconnectAfterResume own the app-resume
    // case), so simply deferring to them here is correct, not a gap.
    if (reconnectInProgress || _resumeReconnectInProgress) return;

    _networkChangeRecoveryInProgress = true;
    try {
      // Reuses the same settle window _scheduleIceRestart() already waits
      // out before deciding the connection needs help — no new timing
      // constant introduced.
      await Future.delayed(const Duration(milliseconds: kIceRestartDelayMs));
      if (_disposed || _pc != pc) return; // torn down/rebuilt while waiting

      if (!_isConnectedState(pc)) {
        // Genuinely unhealthy — the connection-state-change handlers and/or
        // _scheduleIceRestart's own timer own recovery from here; they will
        // call _handleConnectedState() (which consumes _remoteRebindPending
        // itself) once it genuinely reconnects. Nothing further to do here.
        return;
      }

      // Still healthy after the settle window: no reconnect is coming to
      // naturally re-trigger onTrack, so nothing else will ever consume
      // _remoteRebindPending for this event. Only act if it's still
      // armed — if a real disconnect/reconnect cycle already happened and
      // _handleConnectedState() already cleared it, there is nothing to do.
      if (!_remoteRebindPending) return;
      _remoteRebindPending = false;
      _refreshRemoteStreamBinding();
    } finally {
      _networkChangeRecoveryInProgress = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_connectivitySub?.cancel());
    unawaited(performCleanup());
    if (_rendererReady) {
      mainRenderer.dispose();
      pipRenderer.dispose();
    }
    _inlineErrorTimer?.cancel();
    _prescriptionTimer?.cancel();
    _chatSendCooldownTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Appointment fetch (role-aware dual-endpoint fallback)
  // ─────────────────────────────────────────────────────────────────────

  Future<void> fetchAppointment() async {
    if (appointmentId.isEmpty) {
      apptError = 'No appointment ID found.';
      apptLoading = false;
      notifyListeners();
      return;
    }

    apptLoading = true;
    apptError = '';
    notifyListeners();

    Object? lastError;
    final roleAttempts = _initialRole == 'doctor'
        ? ['doctor', 'user']
        : _initialRole == 'user'
            ? ['user', 'doctor']
            : (_hasDoctorIdentity && !_hasUserIdentity)
                ? ['doctor']
                : (_hasUserIdentity && !_hasDoctorIdentity)
                    ? ['user']
                    : ['doctor', 'user'];

    for (final role in roleAttempts) {
      if (role == 'doctor' && !_hasDoctorIdentity) continue;
      if (role == 'user' && !_hasUserIdentity) continue;

      try {
        final endpoint = role == 'doctor'
            ? '/api/appointments/doctor/$appointmentId'
            : '/api/appointments/patient/$appointmentId';
        // Silent: the screen already shows its own "Loading appointment..."
        // gate (see VideoCallScreen.build) while apptLoading is true — the
        // app-wide overlay would just be a second spinner stacked on it.
        final data = await ApiService.instance.get(endpoint, silent: true);
        if (_disposed) return;
        appt = Map<String, dynamic>.from(data as Map);
        activeRole = role;
        apptLoading = false;
        notifyListeners();
        _afterApptLoaded();
        return;
      } catch (err) {
        lastError = err;
      }
    }

    if (_disposed) return;
    apptError = (!_hasUserIdentity && !_hasDoctorIdentity)
        ? 'Please login to access this appointment.'
        : (lastError?.toString() ?? 'Could not load appointment.');
    apptLoading = false;
    notifyListeners();
  }

  void _afterApptLoaded() {
    if (canJoinConsultation && !_callSessionStarted) {
      _callSessionStarted = true;
      unawaited(startCallSession());
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // WebRTC + socket session
  // ─────────────────────────────────────────────────────────────────────

  /// Android 12+ (API 31) split the legacy `BLUETOOTH` permission (granted
  /// automatically at install) into runtime-gated permissions, including
  /// `BLUETOOTH_CONNECT`. Native WebRTC's audio device manager queries paired
  /// Bluetooth devices when setting up the call's audio route (for headset
  /// support); on Android 12+ that query fails silently — or throws,
  /// depending on OEM/AOSP version — if the permission was only declared in
  /// the manifest and never actually granted, since flutter_webrtc itself
  /// only requests CAMERA/RECORD_AUDIO, not Bluetooth. Requesting it here,
  /// before any audio/peer-connection setup begins, closes that gap. This is
  /// a no-op on iOS/web and on Android < 12 (permission_handler resolves it
  /// as already-granted there).
  Future<void> _ensureAndroidRuntimePermissions() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final status = await ph.Permission.bluetoothConnect.status;
      if (!status.isGranted) {
        await ph.Permission.bluetoothConnect.request();
      }
    } catch (err) {
      // Never let a Bluetooth-permission hiccup block the call itself —
      // worst case the audio route falls back to the phone speaker/mic.
      debugPrint('[video-call] bluetoothConnect permission request failed: $err');
    }
  }

  Future<void> startCallSession() async {
    // _completedFlag is only true once performCleanup() has actually run —
    // i.e. this call session already considers itself finished. Checked
    // before _ensureAndroidRuntimePermissions()'s await (which reopens the
    // narrow window a stray reconnect trigger could land in) so a call that
    // ended just before widget disposal can't have its camera/mic and
    // signaling restarted from underneath it. startCallSession resets
    // _completedFlag to false further below for a *legitimate* new session
    // (a real forceReconnect); this guard only blocks re-entry into an
    // already-completed one.
    if (_disposed || _completedFlag) return;
    await _ensureAndroidRuntimePermissions();
    // Rechecked after every await below, not just _disposed — performCleanup
    // (e.g. from a room-access-denied/duplicate-session server event, or the
    // user backing out) can flip _completedFlag true while any of these are
    // in flight, and without this a stale in-flight call would otherwise
    // resurrect a session that was already told to stop.
    if (_disposed || _completedFlag) return;

    // Best-effort: a token that's gone stale while the app was backgrounded
    // would otherwise fail the ICE-config fetch and the room join below.
    // Non-fatal — if this fails, proceed with whatever's in storage, same
    // as before this existed.
    try {
      await ApiService.instance.refreshAccessToken(isDoctor ? 'doctor' : 'user');
    } catch (_) {
      // Ignore — fall through with the existing stored token.
    }
    if (_disposed || _completedFlag) return;

    if (_fetchingIceConfig) return;
    _fetchingIceConfig = true;
    final iceSetup = await fetchIceServerConfig();
    _fetchingIceConfig = false;
    if (_disposed || _completedFlag) return;

    if (!iceSetup.isUsable) {
      iceConfigError = iceSetup.error;
      apptError = 'Video consultation is not configured: ${iceSetup.error}';
      notifyListeners();
      return;
    }
    iceConfigError = '';

    _completedFlag = false;
    _pendingRemoteCandidates.clear();
    _ignoreOffer = false;
    _settingRemoteAnswerPending = false;
    _pendingOfferId = null;
    _lastReceivedOfferId = null;
    _lastRttMs = null;
    _clearOfferAnswerTimeout();
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
    _ignoreOfferResetTimer?.cancel();
    _ignoreOfferResetTimer = null;
    _reconnectStallTimer?.cancel();
    _reconnectStallTimer = null;
    reconnectStalled = false;
    // Captured as a local below and threaded through to _acquireLocalMedia
    // as an explicit parameter, rather than having that method read/write
    // this field directly — a slow/stuck previous _acquireLocalMedia call
    // (from a prior startCallSession/forceReconnect) resuming after this
    // field has already been reassigned would otherwise complete the NEW
    // session's completer instead of its own, wrongly reporting media as
    // unready (a false "Allow camera or microphone access" error) for a
    // session it was never part of.
    final localReadyCompleter = Completer<bool>();
    _localReady = localReadyCompleter;
    _isPolitePeer = isDoctor;

    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }

    // Unlike the browser, a native RTCPeerConnection/MediaStream constructor
    // can genuinely throw here (a malformed ICE config, a native WebRTC
    // plugin/OS failure) — left unguarded, that exception would propagate out
    // of an `unawaited` call site with nothing to catch it, leaving the user
    // stuck on the waiting screen forever with no error and no retry. Route
    // it through the same apptError gate the ICE-config-fetch failure above
    // already uses, rather than a silent hang.
    RTCPeerConnection pc;
    MediaStream remoteStream;
    try {
      pc = await createPeerConnection(iceSetup.config);
      remoteStream = await createLocalMediaStream('remote');
    } catch (err) {
      debugPrint('[video-call] peer connection setup failed: $err');
      _logEvent('peer_connection_setup_failed', {'error': err.toString()});
      if (!_disposed) {
        apptError =
            'Could not start the video call on this device. Please restart the app and try again.';
        notifyListeners();
      }
      return;
    }
    if (_disposed) {
      await pc.close();
      return;
    }
    _pc = pc;
    _pcCreatedAt = DateTime.now();
    // TEMPORARY (RETRY_DEBUG)
    retryDebugLog(isDoctor, appointmentId, 'startCallSession:new_pc_created', {
      'reconnectInProgress': reconnectInProgress,
    });
    _logEvent('peer_connection_created', {
      'iceServerCount': (iceSetup.config['iceServers'] as List).length,
      'hasTurn': iceSetup.hasTurn,
    });

    _remoteStream = remoteStream;
    mainRenderer.srcObject = remoteStream;

    pc.onTrack = (event) => unawaited(_handleTrack(event, remoteStream));
    pc.onIceCandidate = _handleLocalIceCandidate;
    pc.onConnectionState = _handleConnectionStateChange;
    pc.onIceConnectionState = _handleIceConnectionStateChange;
    pc.onSignalingState = _handleSignalingStateChange;

    _registerSocketListeners();

    unawaited(_acquireLocalMedia(pc, localReadyCompleter));

    if (_socket.connected) {
      _emitOnlineAndJoinRoom();
    } else {
      _socket.connect();
    }
  }

  Future<void> _acquireLocalMedia(
    RTCPeerConnection pc,
    Completer<bool> readyCompleter,
  ) async {
    try {
      deviceCheckStatus = 'checking';
      notifyListeners();

      final summary = await _deviceCheckSummary();
      deviceCheckCamera = summary['camera'] ?? 'unknown';
      deviceCheckMicrophone = summary['microphone'] ?? 'unknown';
      deviceCheckSpeaker = summary['speaker'] ?? 'unknown';
      notifyListeners();
      _logEvent('device_check', summary);

      final stream = await _acquireMediaWithTimeout();
      if (_disposed || _pc != pc) {
        for (final t in stream.getTracks()) {
          await t.stop();
        }
        if (!readyCompleter.isCompleted) readyCompleter.complete(false);
        return;
      }

      await _attachLocalMediaStream(stream, pc);
      unawaited(_applySpeakerphonePreference());

      isReady = true;
      camError = false;
      camErrorReason = '';
      camPermissionPermanentlyDenied = false;
      deviceCheckStatus = 'ready';
      // Only one of audio/video may have actually been granted (see
      // _getConsultationMediaStream's split-device fallback) — reflect that
      // truthfully instead of leaving isCamOff/isMuted at their defaults, and
      // tell the peer so their UI doesn't show a stale "camera on".
      isCamOff = stream.getVideoTracks().isEmpty;
      isMuted = stream.getAudioTracks().isEmpty;
      notifyListeners();
      _logEvent('media_ready', {
        'audioTracks': stream.getAudioTracks().length,
        'videoTracks': stream.getVideoTracks().length,
      });

      // Local media is ready — protect the process with the foreground
      // service now rather than waiting for the peer to join and signaling
      // to complete (see _startForegroundServiceIfNeeded's doc comment).
      _startForegroundServiceIfNeeded();

      if (_socket.connected) _emitOnlineAndJoinRoom();
      _announceCameraState();

      if (!isDoctor && peerJoined) {
        Timer(const Duration(milliseconds: 300), () {
          if (_disposed || _pc != pc) return;
          if (_isConnectedState(pc)) return;
          unawaited(_createAndSendOffer(iceRestart: inCall));
        });
      }
      if (!readyCompleter.isCompleted) readyCompleter.complete(true);
      // Local tracks are attached now, so an offer that arrived during the
      // rebuild is answered sendrecv rather than recvonly.
      _replayPendingRemoteOffer(pc);
    } catch (err) {
      debugPrint('[video-call] media permission failed: $err');
      _logEvent('media_permission_failed', {'error': err.toString()});
      if (_disposed || _pc != pc) {
        if (!readyCompleter.isCompleted) readyCompleter.complete(false);
        return;
      }
      camError = true;
      camErrorReason = _mediaErrorMessage(err);
      deviceCheckStatus = 'failed';
      await _refreshPermissionDenialState();
      retryDebugLog(isDoctor, appointmentId, 'acquireLocalMedia:media_failed_joining_recvonly', {
        'error': err.toString(),
        'errorType': err.runtimeType.toString(),
        'permanentlyDenied': camPermissionPermanentlyDenied,
      });

      // CRITICAL fix: still join the call receive-only instead of leaving it
      // permanently unnegotiated. Mobile is always the offerer, so without
      // this neither side ever exchanges an SDP offer/answer at all — the
      // doctor would be stuck on "Waiting for patient..." forever even
      // though the patient is actually in the room. Mirrors VideoCall.jsx's
      // fix for the same scenario.
      isCamOff = true;
      isMuted = true;
      await _ensureRecvOnlyTransceivers(pc, audio: true, video: true);
      isReady = true;
      notifyListeners();

      if (_socket.connected) _emitOnlineAndJoinRoom();
      _announceCameraState();

      if (!isDoctor && peerJoined) {
        Timer(const Duration(milliseconds: 300), () {
          if (_disposed || _pc != pc) return;
          if (_isConnectedState(pc)) return;
          unawaited(_createAndSendOffer(iceRestart: inCall));
        });
      }
      if (!readyCompleter.isCompleted) readyCompleter.complete(true);
      _replayPendingRemoteOffer(pc);
    }
  }

  Future<Map<String, dynamic>> _deviceCheckSummary() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      return {
        'camera': devices.any((d) => d.kind == 'videoinput') ? 'available' : 'missing',
        'microphone': devices.any((d) => d.kind == 'audioinput') ? 'available' : 'missing',
        'speaker': devices.any((d) => d.kind == 'audiooutput') ? 'available' : 'unknown',
      };
    } catch (_) {
      return {'camera': 'unknown', 'microphone': 'unknown', 'speaker': 'unknown'};
    }
  }

  /// Same 3-step fallback chain as `getConsultationMediaStream` in
  /// VideoCall.jsx: full constraints -> basic audio+video -> split
  /// audio-only/video-only so a call still connects if only one device
  /// grants permission.
  Future<MediaStream> _getConsultationMediaStream() async {
    try {
      return await navigator.mediaDevices.getUserMedia(kMediaConstraints);
    } catch (firstErr) {
      debugPrint('[video-call] high-quality media failed, trying basic: $firstErr');
      try {
        return await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
      } catch (secondErr) {
        debugPrint('[video-call] basic media failed, trying split devices: $secondErr');
        final partial = await createLocalMediaStream('partial');
        Object lastErr = secondErr;

        // Audio BEFORE video so the m-line order is always audio, video.
        try {
          final audioOnly = await navigator.mediaDevices
              .getUserMedia({'audio': kMediaConstraints['audio'], 'video': false});
          for (final track in audioOnly.getTracks()) {
            await partial.addTrack(track);
          }
        } catch (audioErr) {
          debugPrint('[video-call] audio-only media failed: $audioErr');
          lastErr = audioErr;
          retryDebugLog(isDoctor, appointmentId, 'getConsultationMediaStream:kind_failed', {
            'kind': 'audio',
            'error': audioErr.toString(),
          });
        }

        try {
          final videoOnly = await navigator.mediaDevices
              .getUserMedia({'audio': false, 'video': kMediaConstraints['video']});
          for (final track in videoOnly.getTracks()) {
            await partial.addTrack(track);
          }
        } catch (videoErr) {
          debugPrint('[video-call] video-only media failed: $videoErr');
          lastErr = videoErr;
          retryDebugLog(isDoctor, appointmentId, 'getConsultationMediaStream:kind_failed', {
            'kind': 'video',
            'error': videoErr.toString(),
          });
        }

        if (partial.getTracks().isNotEmpty) return partial;
        throw lastErr;
      }
    }
  }

  String _mediaErrorMessage(Object err) {
    if (err is TimeoutException) {
      return 'Camera/microphone access is taking too long. Check app permissions and try again.';
    }
    final msg = err.toString();
    if (msg.contains('NotAllowedError') || msg.contains('PermissionDeniedError')) {
      return 'Camera/microphone permission was denied. Allow access in your device settings, then retry.';
    }
    if (msg.contains('NotFoundError') || msg.contains('DevicesNotFoundError')) {
      return 'No camera or microphone was found on this device.';
    }
    if (msg.contains('NotReadableError') || msg.contains('TrackStartError')) {
      return 'Your camera or microphone is already in use by another app. Close it and retry.';
    }
    return 'Camera or microphone access failed. Check app permissions and reload.';
  }

  /// Checked after a media-acquisition failure to tell a transient/denied
  /// prompt apart from a "don't ask again" permanent denial — in the latter
  /// case, getUserMedia will keep failing identically forever since the OS
  /// won't re-show the prompt, so the UI needs [openPermissionSettings]
  /// instead of another retry.
  Future<void> _refreshPermissionDenialState() async {
    if (kIsWeb) return;
    try {
      final cam = await ph.Permission.camera.status;
      final mic = await ph.Permission.microphone.status;
      final permanentlyDenied = cam.isPermanentlyDenied || mic.isPermanentlyDenied;
      if (permanentlyDenied && !camPermissionPermanentlyDenied) {
        retryDebugLog(isDoctor, appointmentId, 'permission:permanently_denied_detected', {
          'camera': cam.toString(),
          'microphone': mic.toString(),
        });
      }
      camPermissionPermanentlyDenied = permanentlyDenied;
    } catch (_) {
      // Best-effort — leave the flag as-is if the platform channel isn't
      // available rather than blocking the error UI on this check.
    }
  }

  /// Opens this app's system settings screen so the user can grant a
  /// permanently-denied camera/microphone permission manually.
  Future<void> openPermissionSettings() async {
    if (kIsWeb) return;
    await ph.openAppSettings();
  }

  /// Wraps [_getConsultationMediaStream] with a hard deadline: on some Android
  /// devices a stuck permission dialog or a native `getUserMedia` call that
  /// never resolves can otherwise leave the caller awaiting forever with no
  /// visible error — this turns that into an actionable, catchable failure
  /// after `kMediaAcquireTimeoutMs` instead of an unexplained infinite spinner.
  Future<MediaStream> _acquireMediaWithTimeout() =>
      _acquireMediaWithTimeoutMs(kMediaAcquireTimeoutMs);

  Future<MediaStream> _acquireMediaWithTimeoutMs(int timeoutMs) {
    return _getConsultationMediaStream().timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () => throw TimeoutException('getUserMedia timed out'),
    );
  }

  Future<bool> _attachLocalMediaStream(MediaStream stream, RTCPeerConnection pc) async {
    if (pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) return false;

    final previousStream = _localStream;
    for (final track in stream.getVideoTracks()) {
      track.enabled = !isCamOff;
    }
    for (final track in stream.getAudioTracks()) {
      track.enabled = !isMuted;
    }

    _localStream = stream;
    pipRenderer.srcObject = stream;
    for (final track in stream.getTracks()) {
      _attachLocalTrackEndedListener(track);
    }

    // Any kind this stream has no track for (denied/missing device, or a
    // partial grant — e.g. mic yes, camera no) still needs a recvonly
    // transceiver so this side keeps RECEIVING that kind from the peer even
    // though it sends nothing for it. Mirrors VideoCall.jsx's
    // ensureRecvOnlyTransceivers.
    await _ensureRecvOnlyTransceivers(
      pc,
      audio: stream.getAudioTracks().isEmpty,
      video: stream.getVideoTracks().isEmpty,
    );

    for (final track in stream.getTracks()) {
      final kind = track.kind ?? '';
      final existingTransceiver = await _getTransceiverForKind(pc, kind);
      RTCRtpSender activeSender;
      if (existingTransceiver != null) {
        await existingTransceiver.sender.replaceTrack(track);
        activeSender = existingTransceiver.sender;
        // Late-attach safety net: a transceiver created recvonly/inactive
        // (the initial no-media join above, or a prior partial grant) must
        // be switched to sendrecv now that it actually has a track to send,
        // or the peer keeps not receiving it despite the track being
        // attached — mirrors VideoCall.jsx's attachLocalMediaStream safety
        // net.
        try {
          final currentDirection = await existingTransceiver.getCurrentDirection();
          if (currentDirection == TransceiverDirection.RecvOnly ||
              currentDirection == TransceiverDirection.Inactive) {
            await existingTransceiver.setDirection(TransceiverDirection.SendRecv);
            retryDebugLog(isDoctor, appointmentId, '_attachLocalMediaStream:direction_forced_sendrecv', {
              'kind': kind,
              'previousDirection': currentDirection.toString(),
            });
          }
        } catch (err) {
          debugPrint('[video-call] setDirection(sendRecv) failed for $kind: $err');
        }
      } else {
        activeSender = await pc.addTrack(track, stream);
      }
      // TEMPORARY (RETRY_DEBUG)
      retryDebugLog(isDoctor, appointmentId, '_attachLocalMediaStream:track', {
        'kind': kind,
        'id': track.id,
        'action': existingTransceiver != null ? 'replaceTrack' : 'addTrack',
        'reconnectInProgress': reconnectInProgress,
      });
      await _tuneSenderQuality(
        activeSender,
        maxBitrate: kind == 'video' ? kCameraBitrate : kVoiceBitrate,
        maxFramerate: kind == 'video' ? 30 : null,
        maintainResolution: kind == 'video',
      );
    }

    if (previousStream != null && previousStream != stream) {
      for (final track in previousStream.getTracks()) {
        await track.stop();
      }
    }

    _assignStreams(isSwapped);
    return true;
  }

  // Detects the local camera/mic dying mid-call (permission revoked, device
  // unplugged, an OEM battery manager killing the capture session while
  // backgrounded) — previously nothing listened for this at all, so
  // isCamOff/isMuted kept reporting whatever the user last toggled while
  // the peer silently stopped receiving that track. `onEnded` is the one
  // reliably-available signal for this (webrtc_interface's MediaStreamTrack
  // has no readyState getter to poll instead).
  void _attachLocalTrackEndedListener(MediaStreamTrack track) {
    track.onEnded = () => _handleLocalTrackEnded(track);
  }

  void _handleLocalTrackEnded(MediaStreamTrack track) {
    if (_disposed) return;
    final stream = _localStream;
    if (stream == null) return;
    // Every call site that intentionally stops a local track (cleanup,
    // camera switch, a fresh _attachLocalMediaStream replacing the whole
    // stream) already removes/replaces it in _localStream — or never
    // routed it through here in the first place — before stopping it, so
    // onEnded firing for one of those finds it no longer "current" here and
    // this is a no-op. Only an unexpected end reaches a track still
    // recorded as part of the live local stream.
    if (!stream.getTracks().any((t) => t.id == track.id)) return;

    final kind = track.kind ?? '';
    _logEvent('local_track_ended', {'kind': kind});
    if (kind == 'video') {
      isCamOff = true;
    } else if (kind == 'audio') {
      isMuted = true;
    }
    // Reuses the existing camError/camErrorReason banner and its "Retry"
    // button (already wired to retryMediaPermissions()) rather than adding
    // new UI/recovery machinery — the same real fix path already used for
    // an initial getUserMedia failure applies equally well to losing a
    // track mid-call.
    camError = true;
    camErrorReason = kind == 'video'
        ? 'Your camera stopped working or its permission was revoked. Tap Retry to reconnect it.'
        : 'Your microphone stopped working or its permission was revoked. Tap Retry to reconnect it.';
    notifyListeners();
  }

  Future<RTCRtpTransceiver?> _getTransceiverForKind(RTCPeerConnection pc, String kind) async {
    final transceivers = await pc.getTransceivers();
    for (final t in transceivers) {
      if (t.sender.track?.kind == kind) return t;
    }
    for (final t in transceivers) {
      if (t.receiver.track?.kind == kind) return t;
    }
    return null;
  }

  /// Adds a recvonly transceiver for whichever of [audio]/[video] this side
  /// has no local track for — used when media acquisition fails entirely
  /// (the call must still receive the peer's audio/video) and when only one
  /// permission was granted (the missing kind still needs to receive).
  /// Mirrors VideoCall.jsx's ensureRecvOnlyTransceivers.
  Future<void> _ensureRecvOnlyTransceivers(
    RTCPeerConnection pc, {
    bool audio = true,
    bool video = true,
  }) async {
    if (pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) return;
    final transceivers = await pc.getTransceivers();
    bool hasKind(String kind) => transceivers.any(
          (t) => t.sender.track?.kind == kind || t.receiver.track?.kind == kind,
        );
    if (audio && !hasKind('audio')) {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      retryDebugLog(isDoctor, appointmentId, 'ensureRecvOnlyTransceivers:added', {'kind': 'audio'});
    }
    if (video && !hasKind('video')) {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      retryDebugLog(isDoctor, appointmentId, 'ensureRecvOnlyTransceivers:added', {'kind': 'video'});
    }
  }

  Future<void> _tuneSenderQuality(
    RTCRtpSender sender, {
    int? maxBitrate,
    int? maxFramerate,
    bool maintainResolution = false,
  }) async {
    if (sender.track == null) return;
    try {
      final params = sender.parameters;
      final encodings = params.encodings ?? [RTCRtpEncoding()];
      final encoding = encodings.isNotEmpty ? encodings.first : RTCRtpEncoding();
      if (maxBitrate != null) encoding.maxBitrate = maxBitrate;
      if (maxFramerate != null) encoding.maxFramerate = maxFramerate;
      if (maintainResolution) {
        params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
        encoding.scaleResolutionDownBy ??= 1.0;
      }
      params.encodings = [encoding, ...encodings.skip(1)];
      await sender.setParameters(params);
    } catch (_) {
      // Mirrors the swallowed try/catch in tuneSenderQuality in VideoCall.jsx.
    }
  }

  // Detach-then-reattach (rather than a plain assignment) on both renderers
  // every time — swapping self/peer between the main stage and the pip must
  // never leave either RTCVideoView showing a leftover frame from whichever
  // stream it was previously bound to while its srcObject reference update
  // is still settling, which otherwise reads as "both tiles show the same
  // video" right after a swap.
  void _assignStreams(bool swapped) {
    final mainStream = swapped ? _localStream : _remoteStream;
    final pipStream = swapped ? _remoteStream : _localStream;
    mainRenderer.srcObject = null;
    mainRenderer.srcObject = mainStream;
    pipRenderer.srcObject = null;
    pipRenderer.srcObject = pipStream;
  }

  // Recovering from a dropped connection (network switch, brief outage)
  // reuses the SAME transceiver/track — pc.onTrack never fires again, so it
  // never gets a chance to rebind the renderer. RTCVideoRenderer can fail
  // to resume painting a track that stalled for a stretch of time even
  // though the underlying MediaStream reference and its tracks never
  // changed — force the renderer currently showing the remote stream to
  // detach and reattach so it treats it as a genuine source change,
  // mirroring the same fix VideoCall.jsx applies via a fresh MediaStream
  // object. Called only on a genuine recovery (see _remoteRebindPending),
  // never on the very first connect, which is already handled correctly by
  // the real onTrack callback.
  void _refreshRemoteStreamBinding() {
    if (_disposed || _remoteStream == null) return;
    final remoteRenderer = isSwapped ? pipRenderer : mainRenderer;
    remoteRenderer.srcObject = null;
    remoteRenderer.srcObject = _remoteStream;
    _logEvent('remote_stream_rebind_after_recovery', {});
  }

  Future<void> _handleTrack(RTCTrackEvent event, MediaStream remoteStream) async {
    final incoming = event.streams.isNotEmpty
        ? event.streams.expand((s) => s.getTracks()).toList()
        : [event.track];
    var retryDebugTrackWasReplaced = false;

    for (final track in incoming) {
      // The sender only ever sends one track per kind, so a new track of a
      // given kind always replaces the previous one for that kind — matters
      // after the remote peer's connection is recreated (e.g. they
      // reconnected): their new track has a different id and wouldn't dedupe
      // by id, so without pruning the dead old track stays alongside the new
      // live one and the renderer can end up stuck on the wrong track.
      final stale = remoteStream
          .getTracks()
          .where((t) => t.kind == track.kind && t.id != track.id)
          .toList();
      if (stale.isNotEmpty) retryDebugTrackWasReplaced = true;
      for (final s in stale) {
        await remoteStream.removeTrack(s);
      }
      if (remoteStream.getTrackById(track.id ?? '') == null) {
        await remoteStream.addTrack(track);
      }
      _attachRemoteTrackMuteListener(track);
    }

    if (_disposed) return;
    // TEMPORARY (RETRY_DEBUG)
    retryDebugLog(isDoctor, appointmentId, '_handleTrack', {
      'trackWasReplaced': retryDebugTrackWasReplaced,
      'tracks': incoming
          .map((t) => {
                'kind': t.kind,
                'id': t.id,
                'enabled': t.enabled,
                'muted': t.muted,
              })
          .toList(),
      'streamCount': event.streams.length,
      'attachTarget': isSwapped ? 'pipRenderer(remote)' : 'mainRenderer(remote)',
    });
    _logEvent('remote_track_received', {
      'tracks': incoming.map((t) => t.kind).toList(),
      'streamCount': event.streams.length,
    });
    _assignStreams(isSwapped);
    isRemoteConnected = true;
    peerLeft = false;
    notifyListeners();
  }

  // A receiver's track fires onMute when RTP stops arriving for that
  // specific SSRC (e.g. the sender's encoder hiccups, or a transient
  // bandwidth squeeze starves video while audio keeps flowing) without any
  // change to the overall connection/ICE state — none of the reconnection
  // machinery below (_scheduleIceRestart, _remoteRebindPending) is reachable
  // from that, so without this listener the renderer is left frozen on its
  // last frame indefinitely even though audio (no comparable per-frame
  // pipeline to freeze) recovers on its own. Reassigning these on every
  // onTrack firing for this track is safe/idempotent — a single-callback
  // field, not an accumulating listener list.
  void _attachRemoteTrackMuteListener(MediaStreamTrack track) {
    track.onMute = () {
      _logEvent('remote_track_muted', {'kind': track.kind});
    };
    track.onUnMute = () {
      _logEvent('remote_track_unmuted', {'kind': track.kind});
      if (_disposed) return;
      // Same track object, same MediaStream — reuses the existing recovery
      // rebind rather than new logic: flutter_webrtc's renderer can fail to
      // resume painting a track that stalled for a stretch of time, exactly
      // like the connection-level recovery case _refreshRemoteStreamBinding
      // already handles.
      _refreshRemoteStreamBinding();
    };
  }

  void _handleLocalIceCandidate(RTCIceCandidate candidate) {
    final raw = candidate.candidate;
    if (raw == null || raw.isEmpty) {
      _logEvent('ice_gathering_complete', {});
      return;
    }
    _logEvent('ice_candidate_gathered', {'type': _iceCandidateType(raw)});
    _socket.emit('ice-candidate', {
      'appointmentId': appointmentId,
      'candidate': candidate.toMap(),
    });
  }

  String _iceCandidateType(String candidate) {
    if (candidate.contains(' typ host')) return 'host';
    if (candidate.contains(' typ srflx')) return 'srflx';
    if (candidate.contains(' typ relay')) return 'relay';
    if (candidate.contains(' typ prflx')) return 'prflx';
    return 'unknown';
  }

  bool _isConnectedState(RTCPeerConnection pc) {
    return pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
        pc.iceConnectionState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        pc.iceConnectionState == RTCIceConnectionState.RTCIceConnectionStateCompleted;
  }

  void _handleConnectionStateChange(RTCPeerConnectionState state) {
    if (_disposed) return;
    // TEMPORARY (RETRY_DEBUG)
    retryDebugLog(isDoctor, appointmentId, '_handleConnectionStateChange', {
      'oldState': _retryDebugPrevConnState?.toString(),
      'newState': state.toString(),
    });
    _retryDebugPrevConnState = state;
    _logEvent('connection_state_changed', {'state': state.toString()});
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _handleConnectedState();
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
      connectionState = 'connecting';
      notifyListeners();
      _startConnectionWatchdog();
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      _logEvent('peer_connection_unhealthy', {'state': state.toString()});
      connectionState = 'disconnected';
      isRemoteConnected = false;
      if (hasConnectedOnce) _remoteRebindPending = true;
      notifyListeners();
      _scheduleIceRestart();
      // A drop after the call was already up (as opposed to a slow initial
      // connect, which _handlePeerJoined's own stall watch already covers)
      // otherwise has no path to the manual "Retry" affordance — see
      // _startReconnectStallWatch's call sites.
      if (inCall) _startReconnectStallWatch(kMidCallReconnectStallMs);
    }
  }

  // Shared by both onConnectionState and onIceConnectionState (a platform
  // fallback for the latter — see _handleIceConnectionStateChange) so a
  // genuine "connected" transition is handled identically regardless of
  // which callback fires it, and so _resyncConnectionStateFromPeerConnection
  // (a socket reconnect finding the peer connection was fine all along) gets
  // the exact same recovery behavior as a real state-change event.
  void _handleConnectedState() {
    // TEMPORARY (RETRY_DEBUG)
    final pcForDebug = _pc;
    retryDebugLog(isDoctor, appointmentId, '_handleConnectedState:called', {
      'connectionState': pcForDebug?.connectionState?.toString(),
      'iceConnectionState': pcForDebug?.iceConnectionState?.toString(),
      'remoteRebindPending': _remoteRebindPending,
      'hasConnectedOnce': hasConnectedOnce,
    });
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
    _connectionFailTimer?.cancel();
    _restartRequestInFlight = false;
    _iceRecoveryAttempts = 0;
    _clearReconnectStallWatch();
    connectionState = 'connected';
    isRemoteConnected = true;
    hasConnectedOnce = true;
    notifyListeners();
    _markInCall();
    final pc = _pc;
    if (pc != null) _startStatsCollection(pc);
    if (_remoteRebindPending) {
      _remoteRebindPending = false;
      _refreshRemoteStreamBinding();
    }
  }

  void _handleSignalingStateChange(RTCSignalingState state) {
    if (_disposed) return;
    _logEvent('signaling_state_changed', {'state': state.toString()});
  }

  // Fallback for platforms where onConnectionState fires late or not at all.
  void _handleIceConnectionStateChange(RTCIceConnectionState state) {
    if (_disposed) return;
    // TEMPORARY (RETRY_DEBUG)
    retryDebugLog(isDoctor, appointmentId, '_handleIceConnectionStateChange', {
      'oldState': _retryDebugPrevIceState?.toString(),
      'newState': state.toString(),
    });
    _retryDebugPrevIceState = state;
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _handleConnectedState();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
      if (!inCall) {
        connectionState = 'connecting';
        notifyListeners();
      }
      _startConnectionWatchdog();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _logEvent('ice_connection_failed', {});
      connectionState = 'disconnected';
      isRemoteConnected = false;
      if (hasConnectedOnce) _remoteRebindPending = true;
      notifyListeners();
      _scheduleIceRestart();
      if (inCall) _startReconnectStallWatch(kMidCallReconnectStallMs);
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      _logEvent('ice_connection_disconnected', {});
      connectionState = 'connecting';
      if (hasConnectedOnce) _remoteRebindPending = true;
      notifyListeners();
      _scheduleIceRestart();
      if (inCall) _startReconnectStallWatch(kMidCallReconnectStallMs);
    }
  }

  // Starts the foreground service at most once per session. Safe to call
  // from both the "local media just became ready" path (the earliest point
  // the app is truly at risk of being suspended while backgrounded, before
  // the peer has even joined) and _markInCall's "connected" path, which
  // stays as a fallback for the (unexpected) case media readiness never
  // fired it.
  void _startForegroundServiceIfNeeded() {
    if (_foregroundServiceStarted || _disposed) return;
    _foregroundServiceStarted = true;
    final localTracks = _localStream?.getTracks() ?? const [];
    unawaited(CallForegroundService.start(
      hasAudio: localTracks.any((t) => t.kind == 'audio'),
      hasVideo: localTracks.any((t) => t.kind == 'video'),
    ));
  }

  void _markInCall() {
    if (inCall) return;
    inCall = true;
    notifyListeners();

    _startForegroundServiceIfNeeded();

    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      callDuration++;
      notifyListeners();
    });

    // A live call has no other API traffic, so the inactivity timer + short-
    // lived access token can expire mid-consultation. Refresh on a cadence
    // well under both timeouts, same as VideoCall.jsx's heartbeat effect.
    // Failure handling: a single failed attempt is silent and non-fatal
    // (refreshAccessToken already falls through to whatever's in storage on
    // its own internal failures) — this only escalates once it has failed
    // kAuthRefreshFailureThreshold times in a row, meaning the session
    // genuinely can no longer be kept alive by retrying, not just a
    // transient blip.
    _heartbeatTimer?.cancel();
    _authRefreshFailureCount = 0;
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 4), (_) async {
      final refreshed = await ApiService.instance
          .refreshAccessToken(isDoctor ? 'doctor' : 'user')
          .catchError((_) => false);
      if (refreshed) {
        _authRefreshFailureCount = 0;
        return;
      }
      _authRefreshFailureCount += 1;
      if (_authRefreshFailureCount < kAuthRefreshFailureThreshold) {
        return; // transient — the next scheduled attempt will try again
      }
      // Repeated failure: the session can no longer be kept alive by
      // retrying. Stop the futile silent retries and surface the same
      // terminal apptError gate _handleRoomDenied/_handleDuplicateSession
      // already use, instead of a second authentication UI —
      // performCleanup() also tears down the socket listeners and peer
      // connection, so nothing is left running a reconnect loop against a
      // session that's already been told it's unauthenticated.
      _heartbeatTimer?.cancel();
      await performCleanup();
      if (_disposed) return;
      apptError =
          'Your session has expired. Please restart the app and log in again to continue.';
      notifyListeners();
    });
  }

  // ── Perfect negotiation (glare handling) ────────────────────────────

  void _resetIgnoredOffer() {
    _ignoreOfferResetTimer?.cancel();
    _ignoreOfferResetTimer = null;
    _ignoreOffer = false;
  }

  void _markIgnoredOffer() {
    _ignoreOffer = true;
    _ignoreOfferResetTimer?.cancel();
    _ignoreOfferResetTimer = Timer(
      const Duration(milliseconds: kIceRestartDelayMs * 2),
      () {
        _ignoreOffer = false;
        _ignoreOfferResetTimer = null;
      },
    );
  }

  Future<void> _flushPendingIceCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    final remoteDesc = await pc.getRemoteDescription();
    if (remoteDesc == null) return;
    final pending = List<dynamic>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidateMap in pending) {
      try {
        await pc.addCandidate(RTCIceCandidate(
          candidateMap['candidate'],
          candidateMap['sdpMid'],
          candidateMap['sdpMLineIndex'],
        ));
      } catch (err) {
        debugPrint('[video-call] queued ICE candidate rejected: $err');
      }
    }
  }

  Future<bool> _createAndSendOffer({bool iceRestart = false}) async {
    final pc = _pc;
    if (pc == null || _disposed || _makingOffer) {
      debugPrint('[video-call] offer skipped: pc=$_pc disposed=$_disposed makingOffer=$_makingOffer');
      return false;
    }
    if (!isReady) {
      debugPrint('[video-call] offer skipped: not ready');
      return false;
    }
    // On some platforms (particularly Flutter web) the RTCPeerConnection's
    // signalingState getter in the flutter_webrtc Dart wrapper returns null
    // even though the underlying JS connection is valid.  Poll briefly, then
    // proceed anyway — a null signalingState is treated as equivalent to
    // stable so the offer/answer exchange can still happen.
    if (pc.signalingState == null && _pc == pc) {
      const delays = [100, 500];
      for (final ms in delays) {
        await Future.delayed(Duration(milliseconds: ms));
        if (_disposed || _pc != pc) return false;
        if (pc.signalingState != null) break;
      }
    }
    if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable &&
        pc.signalingState != null) {
      debugPrint('[video-call] offer skipped: signalingState=${pc.signalingState}');
      return false;
    }

    try {
      _makingOffer = true;
      _resetIgnoredOffer();
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
        if (iceRestart) 'iceRestart': true,
      });
      if (_disposed || pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
        return false;
      }
      await pc.setLocalDescription(offer);
      final offerId = _makeOfferId();
      _pendingOfferId = offerId;
      _logEvent('offer_sent', {'iceRestart': iceRestart, 'sdpLength': offer.sdp?.length ?? 0});
      // TEMPORARY (RETRY_DEBUG)
      retryDebugLog(isDoctor, appointmentId, '_createAndSendOffer:offer_sent', {
        'offerId': offerId,
        'iceRestart': iceRestart,
        'reconnectInProgress': reconnectInProgress,
        'dtlsFingerprint': retryDebugExtractFingerprint(offer.sdp),
      });
      _socket.emit('video-offer', {
        'appointmentId': appointmentId,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'offerId': offerId,
      });
      if (iceRestart) _logEvent('ice_restart_offer_sent', {});
      final hasLocalMedia = _localStream != null && _localStream!.getTracks().isNotEmpty;
      if (!hasLocalMedia) {
        retryDebugLog(isDoctor, appointmentId, '_createAndSendOffer:receive_only_offer_sent', {
          'offerId': offerId,
        });
      }
      _armOfferAnswerTimeout(pc, offerId);
      return true;
    } catch (err) {
      debugPrint('[video-call] ${iceRestart ? "ICE restart offer" : "offer"} failed: $err');
      if (iceRestart) _logEvent('ice_restart_offer_failed', {'error': err.toString()});
      return false;
    } finally {
      _makingOffer = false;
    }
  }

  // `_idRng.nextInt(1 << 32)` used to be the max here, but on Flutter Web
  // (dart2js/dartdevc) shifting by exactly the int bit-width silently
  // truncates to 0, so `nextInt(0)` throws `RangeError: max must be in
  // range 0 < max ≤ 2^32, was 0` — thrown *after* setLocalDescription()
  // already moved signalingState to have-local-offer but *before*
  // _pendingOfferId/_armOfferAnswerTimeout ever run, permanently wedging
  // the call (nothing left to roll the offer back). `1 << 31` stays well
  // under nextInt's 2^32 limit without hitting that shift-width edge case.
  String _makeOfferId() =>
      'offer-${DateTime.now().microsecondsSinceEpoch}-${_idRng.nextInt(1 << 31)}';

  void _clearOfferAnswerTimeout() {
    _offerAnswerTimeoutTimer?.cancel();
    _offerAnswerTimeoutTimer = null;
  }

  /// Self-heals if this specific offer never gets answered (dropped
  /// signaling message, peer mid-reconnect, replayed/rejected stale answer,
  /// etc.) — otherwise the RTCPeerConnection stays wedged in
  /// "have-local-offer" forever, since nothing else ever rolls back our own
  /// offer. Mirrors VideoCall.jsx's offerAnswerTimeoutRef watchdog.
  ///
  /// The wait is widened on high-latency links: kOfferAnswerTimeoutMs is
  /// sized for a typical connection, but on a slow/high-RTT network (mobile
  /// data, international) that alone can fire before the answer had any
  /// realistic chance to arrive. When a recent RTT sample exists, require at
  /// least 3x it (plus headroom for signaling + SDP processing), capped so a
  /// temporarily degraded link can't wedge retry logic behind a
  /// multi-minute wait. Mirrors VideoCall.jsx's effectiveOfferAnswerTimeoutMs.
  void _armOfferAnswerTimeout(RTCPeerConnection pc, String offerId) {
    _clearOfferAnswerTimeout();
    final measuredRtt = _lastRttMs;
    final effectiveTimeoutMs = (measuredRtt != null && measuredRtt > 0)
        ? min(max(kOfferAnswerTimeoutMs, (measuredRtt * 3 + 5000).round()), 30000)
        : kOfferAnswerTimeoutMs;
    _offerAnswerTimeoutTimer = Timer(Duration(milliseconds: effectiveTimeoutMs), () async {
      _offerAnswerTimeoutTimer = null;
      if (_disposed || _pc != pc || pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
        return;
      }
      if (_pendingOfferId != offerId) return; // already resolved or superseded
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        _pendingOfferId = null;
        return;
      }
      _logEvent('offer_answer_timeout_rollback', {'offerId': offerId, 'timeoutMs': effectiveTimeoutMs, 'measuredRtt': measuredRtt});
      debugPrint('[video-call] no answer received for offer $offerId within ${effectiveTimeoutMs}ms (rtt=${measuredRtt ?? "unknown"}) — rolling back to retry.');
      try {
        await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
        _pendingOfferId = null;
        // Retry directly rather than via _scheduleIceRestart(): that helper
        // bails out early whenever the connection already reads
        // "connected" — which is exactly the misleading state this timeout
        // is designed to catch. _createAndSendOffer's own guards (disposed,
        // signalingState, isReady) still apply, so this can't fire against a
        // closed/torn-down pc.
        unawaited(_createAndSendOffer(iceRestart: true));
      } catch (err) {
        _pendingOfferId = null;
        debugPrint('[video-call] rollback after offer-answer timeout failed: $err');
      }
    });
  }

  // ── Connection watchdog / ICE-restart recovery ──────────────────────

  void _startConnectionWatchdog() {
    _connectionFailTimer?.cancel();
    _connectionFailTimer = Timer(const Duration(milliseconds: kConnectionFailTimeoutMs), () {
      final pc = _pc;
      if (_disposed || pc == null) return;
      if (_isConnectedState(pc)) return;
      debugPrint('[video-call] connection establishment timed out; scheduling ICE recovery');
      _scheduleIceRestart();
    });
  }

  void _clearReconnectStallWatch() {
    _reconnectStallTimer?.cancel();
    _reconnectStallTimer = null;
    // Every call site of this method represents either a genuine reconnect
    // success or "no longer trying to reconnect right now" (peer left) —
    // either way, a future stall is a fresh episode, not a continuation of
    // whatever was happening before.
    reconnectStallCount = 0;
    if (reconnectStalled) {
      reconnectStalled = false;
      notifyListeners();
    }
  }

  void _startReconnectStallWatch(int delayMs) {
    if (_reconnectStallTimer != null) return;
    _reconnectStallTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectStallTimer = null;
      final pc = _pc;
      if (_disposed || pc == null) return;
      if (_isConnectedState(pc)) return;
      reconnectStallCount += 1;
      reconnectStalled = true;
      notifyListeners();
    });
  }

  void _startJoinTimeout() {
    _joinTimeoutTimer?.cancel();
    if (peerJoined) return;
    _joinTimeoutTimer = Timer(const Duration(milliseconds: kPeerJoinTimeoutMs), () {
      if (_disposed || peerJoined || inCall) return;
      _logEvent('join_timed_out', {});
      _showInlineMessage(
        'The other participant has not joined yet. The call will retry automatically.',
        const Duration(seconds: 6),
      );
      reconnectStalled = true;
      notifyListeners();
    });
  }

  void _clearJoinTimeout() {
    _joinTimeoutTimer?.cancel();
    _joinTimeoutTimer = null;
  }

  void _requestPeerIceRestart() {
    if (_restartRequestInFlight) return;
    _restartRequestInFlight = true;
    _socket.emit('ice-restart-request', {'appointmentId': appointmentId});
    _logEvent('ice_restart_requested_from_peer', {});
    Timer(const Duration(milliseconds: kIceRestartDelayMs * 2), () {
      _restartRequestInFlight = false;
    });
  }

  void _scheduleIceRestart() {
    if (_disposed || _iceRestartTimer != null) return;
    _iceRestartTimer = Timer(const Duration(milliseconds: kIceRestartDelayMs), () async {
      _iceRestartTimer = null;
      final pc = _pc;
      if (_disposed || pc == null) return;
      if (_isConnectedState(pc)) return;

      final now = DateTime.now();
      if (now.difference(_lastIceRecoveryAt).inMilliseconds > kIceRecoveryCooldownMs) {
        _iceRecoveryAttempts = 0;
      }
      _lastIceRecoveryAt = now;

      if (_iceRecoveryAttempts >= kIceMaxRecoveryAttempts) {
        _logEvent('ice_recovery_exhausted', {'attempts': _iceRecoveryAttempts});
        _requestPeerIceRestart();
        _rearmIceRecoveryLoop();
        return;
      }

      if (_isPolitePeer) {
        _iceRecoveryAttempts += 1;
        _logEvent('ice_recovery_attempt', {'attempts': _iceRecoveryAttempts});
        _requestPeerIceRestart();
        _rearmIceRecoveryLoop();
        return;
      }

      // A negotiation this same recovery machinery already kicked off (or
      // one that raced in from elsewhere — e.g. the peer's own offer) is
      // still outstanding. Perfect negotiation only ever tolerates one
      // outstanding offer at a time (see _makingOffer/createAndSendOffer's
      // own signalingState guard, which would otherwise silently drop this
      // trigger with nothing to pick it back up) — sending a second,
      // overlapping offer here would violate that invariant. The existing
      // offer-answer-timeout watchdog (_armOfferAnswerTimeout) already owns
      // rolling this specific negotiation back and retrying it if it
      // stalls, so this doesn't spend an attempt or lose the trigger — it
      // just re-checks on the next cycle via _rearmIceRecoveryLoop below,
      // by which point that negotiation has either succeeded (the loop
      // stops on its own) or been rolled back (signalingState is stable
      // again, so the next tick sends a fresh restart offer normally).
      if (_makingOffer || pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        _logEvent('ice_recovery_deferred_offer_in_flight', {'attempts': _iceRecoveryAttempts});
        _rearmIceRecoveryLoop();
        return;
      }

      _iceRecoveryAttempts += 1;
      _logEvent('ice_recovery_attempt', {'attempts': _iceRecoveryAttempts});
      await _createAndSendOffer(iceRestart: true);
      _rearmIceRecoveryLoop();
    });
  }

  // Closes the gap where a single failed/unhealthy recovery attempt left
  // nothing to automatically try again: re-arms _scheduleIceRestart() on
  // the same debounce cadence it already uses, so the existing
  // _iceRecoveryAttempts/kIceMaxRecoveryAttempts/kIceRecoveryCooldownMs
  // constants above actually function as a bounded retry loop instead of
  // firing once and stopping. Safe and idempotent to call unconditionally
  // — checked here AND by _scheduleIceRestart's own guards on its next
  // tick, so this naturally and immediately stops the moment the
  // connection recovers, the controller is disposed, or the PeerConnection
  // is torn down (_pc set to null by _teardownSession, which also
  // explicitly cancels any pending _iceRestartTimer) — never sends
  // anything by itself, only decides whether another check is warranted.
  void _rearmIceRecoveryLoop() {
    if (_disposed) return;
    final pc = _pc;
    if (pc == null || _isConnectedState(pc)) return;
    _scheduleIceRestart();
  }

  /// Manual escape hatch: tears down and rebuilds the RTCPeerConnection and
  /// rejoins the room from scratch. Mirrors `forceReconnect`'s nonce bump in
  /// VideoCall.jsx.
  Future<void> forceReconnect() async {
    if (reconnectInProgress) return;
    // TEMPORARY (RETRY_DEBUG)
    retryDebugLog(isDoctor, appointmentId, 'forceReconnect:TAPPED', {
      'pcConnectionState': _pc?.connectionState?.toString(),
      'pcIceConnectionState': _pc?.iceConnectionState?.toString(),
    });
    reconnectInProgress = true;
    reconnectStalled = false;
    notifyListeners();
    try {
      await _teardownSession(leaveRoom: false, keepListeners: true);
      await startCallSession();
    } finally {
      reconnectInProgress = false;
      notifyListeners();
    }
  }

  /// _handlePeerJoined's pcNeedsRebuild branch calls this instead of
  /// forceReconnect() directly. The peer-joined event that triggered the
  /// rebuild is itself proof the other party is already in the room, but
  /// forceReconnect() -> _teardownSession() resets `peerJoined` to false
  /// along with everything else, and only a *future* 'peer-joined' socket
  /// event ever sets it back to true. Unlike a normal cold start, this
  /// rebuilt session has no such event coming — the other party isn't
  /// rejoining again, they already joined and *caused* this rebuild — so
  /// the usual self-offer checks in _acquireLocalMedia/_handlePeerJoined
  /// never see `peerJoined == true` and nothing ever calls
  /// _createAndSendOffer for the new peer connection, leaving it stuck at
  /// RTCPeerConnectionState.new. Only the Patient side self-initiates
  /// offers (the Doctor stays a purely polite peer — see
  /// _acquireLocalMedia), so only it needs to resend one here, once the
  /// rebuilt session's local media is actually ready.
  Future<void> _rebuildAfterPeerRejoin() async {
    await forceReconnect();
    if (isDoctor || _disposed || _completedFlag) return;

    // Same readiness signal _handleOffer already awaits — sidesteps the
    // fact that startCallSession() kicks off media acquisition without
    // awaiting it itself.
    final localReady = await _localReady.future;
    if (_disposed || _completedFlag || !localReady) return;

    final pc = _pc;
    if (pc == null || _isConnectedState(pc)) return;
    // _createAndSendOffer has its own _makingOffer/signalingState guards,
    // so an overlapping call here (e.g. a second peer-joined arriving
    // mid-rebuild) can't produce a duplicate offer.
    unawaited(_createAndSendOffer(iceRestart: inCall));
  }

  /// No direct React equivalent (browser tabs don't get suspended the same
  /// way), but a real mobile gap: the OS can freeze networking while the app
  /// is backgrounded, leaving the socket client's own reconnection backoff
  /// timer stale by the time the app returns to the foreground. Proactively
  /// kicking the socket on resume starts recovery immediately instead of
  /// waiting out whatever backoff delay was in flight when the app was
  /// backgrounded.
  bool _resumeReconnectInProgress = false;

  void handleAppResumed() {
    if (_disposed) return;
    // The local self-view can be suspended by the OS/Flutter's own
    // rendering pipeline while the app is backgrounded, even though the
    // underlying camera track and its WebRTC transmission to the peer keep
    // running unaffected (a separate pipeline from the local preview's
    // decode/render) — mirrors _refreshRemoteStreamBinding's reasoning for
    // the remote side. Replay it explicitly on resume instead of leaving it
    // stuck on a frozen/black frame. Independent of the connection-recovery
    // logic below (a purely local rendering concern), and a no-op if
    // there's no local stream yet — see _refreshLocalStreamBinding's own
    // guard.
    _refreshLocalStreamBinding();

    // The user may have just come back from the OS Settings screen after
    // tapping "Open Settings" on a permanently-denied camera/mic banner —
    // re-check permission state now instead of waiting for another manual
    // tap, and resume the join automatically if it's now granted.
    if (camError) unawaited(_recheckPermissionAfterResume());

    final pc = _pc;
    if (pc == null) return;
    if (_resumeReconnectInProgress) return;
    if (_isConnectedState(pc)) {
      // A "connected" reading here can be stale: the OS may have frozen the
      // app's networking entirely while backgrounded, in which case
      // libwebrtc never got to run the consent/keepalive checks that would
      // normally flip this to "disconnected" and trigger our own recovery —
      // pc.connectionState just reflects whatever it last was before the
      // freeze. Probe actual inbound media progress instead of trusting the
      // cached state, and only fall through to a restart if that probe
      // confirms the transport is genuinely stalled.
      unawaited(_verifyConnectionAfterResume(pc));
      return;
    }
    unawaited(_reconnectAfterResume());
  }

  /// Re-checks camera/mic permission status after the app resumes and
  /// automatically retries joining with real media if it's now granted —
  /// otherwise a user who fixes the permission in Settings would have to
  /// come back and tap Retry themselves for no reason. No-op unless the
  /// camera-error banner is actually showing (camError).
  Future<void> _recheckPermissionAfterResume() async {
    if (kIsWeb || !camError) return;
    try {
      final cam = await ph.Permission.camera.status;
      final mic = await ph.Permission.microphone.status;
      final stillPermanentlyDenied = cam.isPermanentlyDenied || mic.isPermanentlyDenied;
      camPermissionPermanentlyDenied = stillPermanentlyDenied;
      if (!stillPermanentlyDenied && (cam.isGranted || mic.isGranted)) {
        retryDebugLog(isDoctor, appointmentId, 'handleAppResumed:permission_granted_after_settings', {
          'camera': cam.toString(),
          'microphone': mic.toString(),
        });
        unawaited(retryMediaPermissions());
      } else {
        notifyListeners();
      }
    } catch (err) {
      debugPrint('[video-call] permission recheck on resume failed: $err');
    }
  }

  Future<num?> _sampleInboundBytes(RTCPeerConnection pc) async {
    try {
      final stats = await pc.getStats();
      for (final report in stats) {
        if (report.type == 'candidate-pair' && report.values['state'] == 'succeeded') {
          final bytesReceived = report.values['bytesReceived'];
          if (bytesReceived is num) return bytesReceived;
        }
      }
    } catch (_) {
      // Unknown, not stalled — see _verifyConnectionAfterResume's null handling.
    }
    return null;
  }

  /// Takes two inbound-bytes samples ~1.5s apart on the already-selected
  /// candidate pair; a connected call should always show some growth
  /// (RTP/RTCP keepalives continue even during silence/camera-off), so no
  /// growth at all is a strong signal the transport died silently while the
  /// app was backgrounded. Bypasses _scheduleIceRestart()'s own "already
  /// connected" guard on purpose — that guard is exactly the misleading
  /// cached state this probe exists to catch (same reasoning as
  /// _armOfferAnswerTimeout's direct rollback-and-retry).
  Future<void> _verifyConnectionAfterResume(RTCPeerConnection pc) async {
    _resumeReconnectInProgress = true;
    try {
      final before = await _sampleInboundBytes(pc);
      if (_disposed || _pc != pc) return;
      await Future.delayed(const Duration(milliseconds: 1500));
      if (_disposed || _pc != pc) return;
      // A real state-change callback may have already fired (and started
      // its own recovery, or torn the call down) while we were sampling —
      // don't second-guess it.
      if (!_isConnectedState(pc)) return;
      final after = await _sampleInboundBytes(pc);
      if (_disposed || _pc != pc) return;

      final stalled = before != null && after != null && after <= before;
      if (!stalled) return;

      _logEvent('resume_stale_connection_detected', {'bytesBefore': before, 'bytesAfter': after});
      debugPrint('[video-call] app resumed with a stale "connected" state — no inbound media progress, forcing recovery.');
      if (_isPolitePeer) {
        _requestPeerIceRestart();
      } else {
        await _createAndSendOffer(iceRestart: true);
      }
    } finally {
      _resumeReconnectInProgress = false;
    }
  }

  Future<void> _reconnectAfterResume() async {
    _resumeReconnectInProgress = true;
    try {
      // The access token can have expired while backgrounded (15-minute
      // TTL) — refresh it before reconnecting so the rejoin isn't rejected
      // as unauthenticated. Non-fatal: proceed with whatever's in storage
      // on failure, same as before this existed.
      try {
        await ApiService.instance.refreshAccessToken(isDoctor ? 'doctor' : 'user');
      } catch (_) {
        // Ignore — fall through with the existing stored token.
      }
      if (_disposed) return;
      _socket.connect();
      // The socket reconnecting on its own never touches the
      // RTCPeerConnection — if it was already disconnected/failed before
      // backgrounding (the branch that routes here rather than to
      // _verifyConnectionAfterResume), nothing else on this path would
      // otherwise retry it; recovery would depend entirely on whatever
      // ICE-restart timer happened to already be pending from before the
      // app was backgrounded. Ensure the existing recovery machinery is
      // actually running now that signaling is being re-established — no
      // new mechanism: _scheduleIceRestart's own guards (already-connected
      // check, _iceRestartTimer != null reentrancy guard) make this a safe,
      // duplicate-free no-op if a cycle is already in flight.
      final pc = _pc;
      if (pc != null && !_isConnectedState(pc)) {
        _scheduleIceRestart();
      }
    } finally {
      _resumeReconnectInProgress = false;
    }
  }

  Future<void> retryMediaPermissions() async {
    final pc = _pc;
    if (pc == null || pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
      camError = true;
      camErrorReason =
          'The call connection is no longer active. Rejoin the consultation and try again.';
      notifyListeners();
      return;
    }

    camError = false;
    deviceCheckStatus = 'checking';
    retryingMedia = true;
    notifyListeners();

    try {
      final summary = await _deviceCheckSummary();
      deviceCheckCamera = summary['camera'] ?? 'unknown';
      deviceCheckMicrophone = summary['microphone'] ?? 'unknown';
      deviceCheckSpeaker = summary['speaker'] ?? 'unknown';
      _logEvent('media_retry_started', summary);

      // Tighter deadline than the initial join (kRetryMediaPermissionsTimeoutMs,
      // not kMediaAcquireTimeoutMs): the user is actively watching this
      // button, so a stuck prompt must hand back control well within ~10s
      // rather than leaving "Retrying..." up for the full 20s join budget.
      final stream = await _acquireMediaWithTimeoutMs(kRetryMediaPermissionsTimeoutMs);
      // A concurrent forceReconnect() can close this pc and open a new one
      // while the permission prompt above is still pending — mirrors the
      // same check _acquireLocalMedia already does after its own await, so
      // a stale retry can't attach tracks to (or answer on) a pc that's no
      // longer the active call.
      if (_disposed || _pc != pc) {
        for (final t in stream.getTracks()) {
          await t.stop();
        }
        if (!_disposed) {
          retryingMedia = false;
          notifyListeners();
        }
        return;
      }
      // Late-attach: replaceTrack onto any existing (possibly recvonly)
      // transceiver and force it to sendrecv — see _attachLocalMediaStream's
      // safety net.
      await _attachLocalMediaStream(stream, pc);
      unawaited(_applySpeakerphonePreference());

      isReady = true;
      camError = false;
      camErrorReason = '';
      camPermissionPermanentlyDenied = false;
      deviceCheckStatus = 'ready';
      retryingMedia = false;
      // Reflects what was actually (re)captured — a partial grant (e.g. mic
      // only) must not falsely report "camera on".
      isCamOff = stream.getVideoTracks().isEmpty;
      isMuted = stream.getAudioTracks().isEmpty;
      notifyListeners();
      _logEvent('media_retry_succeeded', {
        'audioTracks': stream.getAudioTracks().length,
        'videoTracks': stream.getVideoTracks().length,
      });
      _emitOnlineAndJoinRoom();
      _announceCameraState();

      if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
        final answer = await pc.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': true,
        });
        await pc.setLocalDescription(answer);
        _socket.emit('video-answer', {
          'appointmentId': appointmentId,
          'answer': {'sdp': answer.sdp, 'type': answer.type},
          'offerId': _lastReceivedOfferId,
        });
      } else if (!isDoctor && peerJoined) {
        // We're the offerer and the peer is already in the room — the
        // original join may have sent no offer at all (no media at the
        // time) or an offer with recvonly m-lines only. Either way, now
        // that real tracks are attached, a fresh offer is needed for the
        // peer to actually start receiving them. Deliberately NOT gated on
        // "already connected": the pc can be connected receive-only from
        // the earlier no-media join, which is exactly the case that still
        // needs this renegotiation. Mirrors VideoCall.jsx's equivalent fix.
        retryDebugLog(isDoctor, appointmentId, 'retryMediaPermissions:renegotiation_offer_scheduled', {
          'connectionState': pc.connectionState?.toString(),
        });
        Timer(const Duration(milliseconds: 300), () {
          if (_disposed || _pc != pc) return;
          unawaited(_createAndSendOffer(iceRestart: inCall));
        });
      }
    } catch (err) {
      camError = true;
      camErrorReason = _mediaErrorMessage(err);
      deviceCheckStatus = 'failed';
      retryingMedia = false;
      _logEvent('media_retry_failed', {'error': err.toString()});
      retryDebugLog(isDoctor, appointmentId, 'retryMediaPermissions:timed_out_or_failed', {
        'error': err.toString(),
        'errorType': err.runtimeType.toString(),
      });
      await _refreshPermissionDenialState();
      notifyListeners();
    }
  }

  // ── Socket signaling handlers ────────────────────────────────────────

  /// Flutter Web's socket_io_client v2 wraps event data as [payload, ackId]
  /// instead of passing the raw Map. Unwrap both formats transparently.
  Map<String, dynamic>? _toMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty && data[0] is Map) {
      return Map<String, dynamic>.from(data[0]);
    }
    return null;
  }

  // Stashes a remote offer that can't be applied yet (no pc / rebuild running).
  void _stashRemoteOffer(Map<String, dynamic> data, String why) {
    _pendingRemoteOffer = data;
    _pendingRemoteOfferAt = DateTime.now();
    retryDebugLog(isDoctor, appointmentId, 'pendingOffer:STASHED', {
      'why': why,
      'offerId': data['offerId'],
    });
  }

  // Replays the stashed offer onto [pc] — called once its local media is
  // attached, so the answer is sendrecv. Drops it if older than 15s.
  void _replayPendingRemoteOffer(RTCPeerConnection pc) {
    final offer = _pendingRemoteOffer;
    final at = _pendingRemoteOfferAt;
    if (offer == null || at == null || _disposed || _completedFlag || _pc != pc) return;
    if (reconnectInProgress) {
      // The rebuild that owns this pc hasn't released the in-progress flag
      // yet — _handleOffer would just re-stash it. Try again shortly.
      Timer(const Duration(milliseconds: 200), () => _replayPendingRemoteOffer(pc));
      return;
    }
    _pendingRemoteOffer = null;
    _pendingRemoteOfferAt = null;
    final ageMs = DateTime.now().difference(at).inMilliseconds;
    if (ageMs > kPendingOfferMaxAgeMs) {
      retryDebugLog(isDoctor, appointmentId, 'pendingOffer:DROPPED_stale', {
        'offerId': offer['offerId'],
        'ageMs': ageMs,
      });
      return;
    }
    retryDebugLog(isDoctor, appointmentId, 'pendingOffer:REPLAY', {
      'offerId': offer['offerId'],
      'ageMs': ageMs,
    });
    unawaited(_handleOffer(offer));
  }

  // The single entry point for every automatic rebuild. reconnectInProgress
  // is the one in-progress flag (forceReconnect sets it), so two rebuild
  // paths can never run at the same time; an offer that couldn't be applied
  // is stashed instead of lost.
  Future<void> _rebuildPc(String reason, {Map<String, dynamic>? offerToReplay}) async {
    if (_disposed || _completedFlag) return;
    if (reconnectInProgress) {
      if (offerToReplay != null) _stashRemoteOffer(offerToReplay, 'rebuild_in_progress');
      retryDebugLog(isDoctor, appointmentId, 'rebuildPc:SKIPPED_in_progress', {'reason': reason});
      return;
    }
    retryDebugLog(isDoctor, appointmentId, 'rebuildPc:START', {
      'reason': reason,
      'withOfferToReplay': offerToReplay != null,
    });
    if (offerToReplay != null) {
      // We're going to ANSWER this offer on the new pc, not send our own.
      _stashRemoteOffer(offerToReplay, reason);
      await forceReconnect();
    } else {
      await _rebuildAfterPeerRejoin();
    }
  }

  // Web doctor tapped Retry / rebuilt: same rebuild as our own Retry, unless
  // our pc is brand new or a rebuild is already running.
  void _handlePeerRebuildRequest(dynamic _) {
    if (_disposed || _completedFlag) return;
    final pc = _pc;
    final pcAgeMs = DateTime.now().difference(_pcCreatedAt).inMilliseconds;
    if (pc == null || reconnectInProgress || pcAgeMs < kPeerRebuildMinPcAgeMs) {
      retryDebugLog(isDoctor, appointmentId, 'request-peer-rebuild:IGNORED', {
        'pcMissing': pc == null,
        'reconnectInProgress': reconnectInProgress,
        'pcAgeMs': pcAgeMs,
      });
      return;
    }
    retryDebugLog(isDoctor, appointmentId, 'request-peer-rebuild:RECEIVED', {'pcAgeMs': pcAgeMs});
    unawaited(_rebuildPc('peer_requested'));
  }

  Future<void> _handleOffer(dynamic raw) async {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final offerMap = data['offer'];
    if (offerMap == null || offerMap is! Map) return;
    final incomingOfferId = data['offerId'] as String?;
    final pc = _pc;
    if (pc == null || reconnectInProgress) {
      // The offer beat our pc into existence (or a rebuild is tearing it
      // down): keep it, and answer it once the new pc has local media.
      if (!_completedFlag) _stashRemoteOffer(data, pc == null ? 'no_pc' : 'rebuild_running');
      return;
    }
    // A newer offer supersedes anything stashed earlier.
    _pendingRemoteOffer = null;
    _pendingRemoteOfferAt = null;

    // Peer rebuilt its RTCPeerConnection (new DTLS identity): this pc can
    // never accept its offer (m-line order). Checked BEFORE the collision
    // logic so it can't be ignored/rolled back; rebuild and answer the same
    // offer on the fresh pc. Real logic — independent of kRetryDebug.
    final incomingFingerprint = extractDtlsFingerprint(offerMap['sdp'] as String?);
    final knownFingerprint = _lastRemoteFingerprint;
    if (incomingFingerprint != null &&
        knownFingerprint != null &&
        incomingFingerprint != knownFingerprint) {
      retryDebugLog(isDoctor, appointmentId, '_handleOffer:peer_rebuilt_detected_via_fingerprint', {
        'offerId': incomingOfferId,
      });
      unawaited(_rebuildPc('fingerprint_changed', offerToReplay: data));
      return;
    }

    try {
      connectionState = 'connecting';
      notifyListeners();

      final signalingState = pc.signalingState;
      // Treat null signalingState (flutter_webrtc web wrapper quirk) as
      // stable so the offer is accepted and the call can proceed.
      final isStable = signalingState == null ||
          signalingState == RTCSignalingState.RTCSignalingStateStable;
      final readyForOffer = !_makingOffer &&
          (isStable || _settingRemoteAnswerPending);
      final offerCollision = !readyForOffer;
      final shouldIgnoreOffer = !_isPolitePeer && offerCollision;

      // TEMPORARY (RETRY_DEBUG): snapshot everything relevant at the moment
      // this offer arrived, before any of it is mutated below.
      final retryDebugPcAgeMs = DateTime.now().difference(_pcCreatedAt).inMilliseconds;
      final retryDebugIncomingFingerprint = retryDebugExtractFingerprint(offerMap['sdp'] as String?);
      final retryDebugPrevFingerprint = _retryDebugLastRemoteFingerprint;
      retryDebugLog(isDoctor, appointmentId, '_handleOffer:arrived', {
        'offerId': incomingOfferId,
        'signalingState': signalingState?.toString(),
        'connectionState': pc.connectionState?.toString(),
        'iceConnectionState': pc.iceConnectionState?.toString(),
        'pcAgeMs': retryDebugPcAgeMs,
        'pcLooksFreshlyRebuilt': retryDebugPcAgeMs < 3000,
        'makingOffer': _makingOffer,
        'settingRemoteAnswerPending': _settingRemoteAnswerPending,
        'offerCollision': offerCollision,
        'isPolitePeer': _isPolitePeer,
        'shouldIgnoreOffer': shouldIgnoreOffer,
        'incomingDtlsFingerprint': retryDebugIncomingFingerprint,
        'previousRemoteDtlsFingerprint': retryDebugPrevFingerprint,
        'dtlsFingerprintChanged': retryDebugIncomingFingerprint != null &&
            retryDebugPrevFingerprint != null &&
            retryDebugIncomingFingerprint != retryDebugPrevFingerprint,
      });

      if (shouldIgnoreOffer) {
        _markIgnoredOffer();
        retryDebugLog(isDoctor, appointmentId, '_handleOffer:IGNORED_collision', {'offerId': incomingOfferId});
        return;
      }
      _resetIgnoredOffer();

      if (offerCollision && signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        retryDebugLog(isDoctor, appointmentId, '_handleOffer:rollback_local_offer', {'offerId': incomingOfferId});
        await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
        // Our own outstanding offer was just discarded — any answer that
        // still shows up for it later is stale and must be rejected, and
        // the answer-timeout watchdog for it is no longer relevant.
        _pendingOfferId = null;
        _clearOfferAnswerTimeout();
      } else if (offerCollision) {
        retryDebugLog(isDoctor, appointmentId, '_handleOffer:IGNORED_in_progress', {
          'offerId': incomingOfferId,
          'signalingState': signalingState?.toString(),
        });
        return;
      }

      try {
        await pc.setRemoteDescription(RTCSessionDescription(
          offerMap['sdp'] as String?,
          offerMap['type'] as String?,
        ));
      } catch (err) {
        retryDebugLog(isDoctor, appointmentId, '_handleOffer:setRemoteDescription:ERROR', {
          'offerId': incomingOfferId,
          'error': err.toString(),
        });
        // Reactive twin of the fingerprint check (the first offer after a
        // rebuild has nothing to compare against). flutter_webrtc errors are
        // Strings. Skipped for a brand-new pc so a genuinely bad offer can't
        // loop rebuilds.
        final errText = err.toString();
        final looksRebuilt = errText.contains('m-line') ||
            errText.contains('SetRemoteDescriptionFailed') ||
            errText.contains('WEBRTC_SET_REMOTE_DESCRIPTION_ERROR');
        if (looksRebuilt &&
            DateTime.now().difference(_pcCreatedAt).inMilliseconds > 2000) {
          retryDebugLog(isDoctor, appointmentId, '_handleOffer:peer_rebuilt_detected_via_sdp_error', {
            'offerId': incomingOfferId,
          });
          unawaited(_rebuildPc('sdp_error', offerToReplay: data));
          return;
        }
        rethrow;
      }
      if (incomingFingerprint != null) _lastRemoteFingerprint = incomingFingerprint;
      // Diagnostic bookkeeping only — records the fingerprint we just
      // applied so the *next* offer's arrival log can report whether it
      // changed (i.e. the peer's RTCPeerConnection was rebuilt).
      _retryDebugLastRemoteFingerprint = retryDebugIncomingFingerprint;
      retryDebugLog(isDoctor, appointmentId, '_handleOffer:setRemoteDescription:ok', {'offerId': incomingOfferId});
      // Record which offer we just accepted as soon as it's applied, not
      // only once we get around to answering it — if local media isn't
      // ready yet, retryMediaPermissions() answers this same remote
      // description later, and needs the right id to echo back then too.
      _lastReceivedOfferId = incomingOfferId;
      _resetIgnoredOffer();
      await _flushPendingIceCandidates();

      final localReady = await _localReady.future;
      if (_disposed) return;
      final hasLocalMedia = _localStream != null && _localStream!.getTracks().isNotEmpty;
      if (!localReady || !hasLocalMedia) {
        // Parity fix with VideoCall.jsx: answer recvonly instead of bailing
        // out without answering at all. Bailing here would starve the
        // offerer's own answer-timeout watchdog forever (it never gets a
        // video-answer), which otherwise causes an infinite rebuild loop —
        // the call must still connect and receive the peer's media even
        // though this side has none to send.
        camError = true;
        camErrorReason =
            'Allow camera or microphone access, then retry to join the consultation.';
        notifyListeners();
        retryDebugLog(isDoctor, appointmentId, '_handleOffer:local_media_not_ready_answering_recvonly', {
          'offerId': incomingOfferId,
          'localReady': localReady,
        });
        final transceivers = await pc.getTransceivers();
        for (final t in transceivers) {
          if (t.sender.track == null) {
            try {
              await t.setDirection(TransceiverDirection.RecvOnly);
            } catch (_) {
              // Best-effort — createAnswer below still reflects whatever
              // direction libwebrtc settled on if this fails.
            }
          }
        }
      }

      RTCSessionDescription answer;
      try {
        answer = await pc.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': true,
        });
      } catch (err) {
        retryDebugLog(isDoctor, appointmentId, '_handleOffer:createAnswer:ERROR', {
          'offerId': incomingOfferId,
          'error': err.toString(),
        });
        rethrow;
      }
      try {
        await pc.setLocalDescription(answer);
      } catch (err) {
        retryDebugLog(isDoctor, appointmentId, '_handleOffer:setLocalDescription:ERROR', {
          'offerId': incomingOfferId,
          'error': err.toString(),
        });
        rethrow;
      }
      retryDebugLog(isDoctor, appointmentId, '_handleOffer:answer_sent', {'offerId': incomingOfferId});
      _socket.emit('video-answer', {
        'appointmentId': appointmentId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'offerId': incomingOfferId,
      });
      _markInCall();
      // TEMPORARY (RETRY_DEBUG): watch whether media actually starts
      // flowing on this pc after answering this offer.
      retryDebugPollInboundVideoStats(pc, isDoctor, appointmentId, '_handleOffer:post_answer');
    } catch (err) {
      debugPrint('[video-call] offer error: $err');
      retryDebugLog(isDoctor, appointmentId, '_handleOffer:ERROR', {'error': err.toString()});
    }
  }

  Future<void> _handleAnswer(dynamic raw) async {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final answerMap = data['answer'];
    if (answerMap == null || answerMap is! Map) return;
    final receivedOfferId = data['offerId'] as String?;
    final pc = _pc;
    if (pc == null) return;

    // TEMPORARY (RETRY_DEBUG)
    retryDebugLog(isDoctor, appointmentId, '_handleAnswer:received', {
      'offerId': receivedOfferId,
      'expectedOfferId': _pendingOfferId,
      'signalingState': pc.signalingState?.toString(),
      'reconnectInProgress': reconnectInProgress,
    });

    try {
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer &&
          pc.signalingState != null) {
        return;
      }
      // Guards against a stale/replayed video-answer being applied to a
      // newer offer — e.g. a socket.io reconnect redelivering an
      // already-consumed answer. signalingState alone can't tell a genuine
      // fresh answer apart from that, since a replayed one arrives while
      // we're legitimately in have-local-offer waiting for a real one.
      final expectedOfferId = _pendingOfferId;
      if (expectedOfferId == null || receivedOfferId != expectedOfferId) {
        _logEvent('answer_rejected_stale', {
          'expectedOfferId': expectedOfferId,
          'receivedOfferId': receivedOfferId,
        });
        debugPrint('[video-call] rejecting answer: offerId mismatch (expected $expectedOfferId, got $receivedOfferId)');
        return;
      }
      // An answer from a rebuilt peer (different DTLS identity) can't be
      // applied to this pc — rebuild instead (the patient then sends a fresh
      // offer). Real logic — independent of kRetryDebug.
      final answerFingerprint = extractDtlsFingerprint(answerMap['sdp'] as String?);
      final knownFingerprint = _lastRemoteFingerprint;
      if (answerFingerprint != null &&
          knownFingerprint != null &&
          answerFingerprint != knownFingerprint) {
        retryDebugLog(isDoctor, appointmentId, '_handleAnswer:REJECTED_fingerprint_changed', {
          'offerId': receivedOfferId,
        });
        unawaited(_rebuildPc('answer_fingerprint_changed'));
        return;
      }
      _settingRemoteAnswerPending = true;
      _logEvent('answer_received', {'sdpLength': answerMap['sdp']?.toString().length ?? 0});
      await pc.setRemoteDescription(RTCSessionDescription(
        answerMap['sdp'] as String?,
        answerMap['type'] as String?,
      ));
      if (answerFingerprint != null) _lastRemoteFingerprint = answerFingerprint;
      _pendingOfferId = null;
      _clearOfferAnswerTimeout();
      _logEvent('answer_accepted', {'offerId': receivedOfferId});
      _resetIgnoredOffer();
      await _flushPendingIceCandidates();
      _markInCall();
      // TEMPORARY (RETRY_DEBUG)
      retryDebugLog(isDoctor, appointmentId, '_handleAnswer:applied_ok', {'offerId': receivedOfferId});
    } catch (err) {
      debugPrint('[video-call] answer error: $err');
      _logEvent('answer_error', {'error': err.toString()});
      retryDebugLog(isDoctor, appointmentId, '_handleAnswer:ERROR', {
        'offerId': receivedOfferId,
        'error': err.toString(),
      });
    } finally {
      _settingRemoteAnswerPending = false;
    }
  }

  Future<void> _handleIce(dynamic raw) async {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final candidateMap = data['candidate'];
    if (candidateMap == null || candidateMap is! Map) return;
    final pc = _pc;
    if (pc == null) return;

    final rawCandidate = candidateMap['candidate']?.toString() ?? '';
    _logEvent('ice_candidate_received', {
      'type': rawCandidate.isNotEmpty ? _iceCandidateType(rawCandidate) : 'end-of-candidates',
    });

    final remoteDesc = await pc.getRemoteDescription();
    if (remoteDesc == null) {
      if (_ignoreOffer) return;
      if (_pendingRemoteCandidates.length >= kPendingCandidatesMax) {
        _pendingRemoteCandidates.removeAt(0);
      }
      _pendingRemoteCandidates.add(candidateMap);
      return;
    }
    try {
      await pc.addCandidate(RTCIceCandidate(
        candidateMap['candidate'] as String?,
        candidateMap['sdpMid'] as String?,
        candidateMap['sdpMLineIndex'] as int?,
      ));
    } catch (err) {
      if (_ignoreOffer) return;
      debugPrint('[video-call] ICE candidate rejected: $err');
    }
  }

  // The doctor still never self-initiates an offer as a matter of course
  // (see _handlePeerJoined) — but if the PATIENT explicitly asks for a
  // restart because it just exhausted its own recovery attempts (see
  // _scheduleIceRestart's exhaustion branch), it needs the doctor to
  // actually act on that request. This used to return early for isDoctor
  // (this app is always the patient, so it was a no-op here in practice),
  // but that guard has drifted from VideoCall.jsx's handleIceRestartRequest,
  // which deliberately dropped it — _createAndSendOffer/_handleOffer's
  // existing collision handling (impolite ignores, polite rolls back)
  // already resolves the rare case where both sides end up offering at once.
  Future<void> _handleIceRestartRequest(dynamic _) async {
    final pc = _pc;
    if (_disposed || pc == null || !isReady) return;
    if (_isConnectedState(pc)) return;
    _logEvent('ice_restart_request_received', {});
    await _createAndSendOffer(iceRestart: true);
  }

  void _handlePeerJoined(dynamic raw) {
    if (_disposed) return;
    _clearJoinTimeout();
    final data = _toMap(raw);
    final resumedCall = data?['resumedCall'] == true;
    _logEvent('peer_joined', {'resumedCall': resumedCall, 'isReady': isReady});
    peerJoined = true;
    peerLeft = false;
    // The peer's own camera state before this (re)join is unknown until they
    // tell us again — assume "on" rather than keep whatever stale value was
    // left over from a previous session, since a wrongly-stuck "camera off"
    // placeholder is a worse failure mode than a brief incorrect "camera on"
    // assumption for the second or two until their announcement arrives.
    peerCameraOff = false;
    notifyListeners();
    // They just (re)joined and may have missed our last toggle (e.g. they
    // reconnected) — make sure they get our current state again.
    _announceCameraState();

    final pc = _pc;

    // A peer connection that's missing, closed, or failed cannot be
    // salvaged with an ICE restart against a peer that now has a brand-new
    // connection/DTLS identity — rebuild it from scratch via the same path
    // the manual "Retry" button uses. A resumed session whose pc is merely
    // stuck at "disconnected" (rather than the unambiguous "failed" case)
    // after a real network outage also won't reliably self-heal via ICE
    // restart alone — mirrors VideoCall.jsx's handlePeerJoined/
    // pcNeedsRebuild. That last case is gated on both resumedCall (so an
    // ordinary first-time connect, whose fresh pc briefly sits at
    // "new"/"connecting" — also "not healthy" — is never affected) and
    // kRebuildGraceMs (so the rebuild this very check triggers can't be
    // undone by its own room-rejoin echoing straight back to us — see
    // kRebuildGraceMs's own comment for why).
    final pcHealthy = pc != null && _isConnectedState(pc);
    final pcAgeMs = DateTime.now().difference(_pcCreatedAt).inMilliseconds;
    final pcNeedsRebuild = pc == null ||
        pc.signalingState == RTCSignalingState.RTCSignalingStateClosed ||
        pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        (resumedCall && !pcHealthy && pcAgeMs > kRebuildGraceMs);
    // TEMPORARY (RETRY_DEBUG)
    retryDebugLog(isDoctor, appointmentId, '_handlePeerJoined', {
      'resumedCall': resumedCall,
      'existingPcConnectionState': pc?.connectionState?.toString(),
      'existingPcIceConnectionState': pc?.iceConnectionState?.toString(),
      'existingPcSignalingState': pc?.signalingState?.toString(),
      'pcHealthy': pcHealthy,
      'pcAgeMs': pcAgeMs,
      'rebuildGraceMs': kRebuildGraceMs,
      'pcNeedsRebuild': pcNeedsRebuild,
      'branch': pcNeedsRebuild ? 'REBUILD' : 'NO_REBUILD',
      'reconnectAlreadyInProgress': reconnectInProgress,
    });
    if (pcNeedsRebuild && !reconnectInProgress) {
      _logEvent('peer_rejoined_pc_rebuild', {
        'reason': pc == null
            ? 'missing'
            : pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed
                ? 'failed'
                : pc.signalingState == RTCSignalingState.RTCSignalingStateClosed
                    ? 'closed'
                    : 'stale_resumed',
        'resumedCall': resumedCall,
      });
      unawaited(_rebuildPc(pc == null ? 'missing' : 'peer_joined'));
      return;
    }

    if (isReady && !inCall) {
      _startConnectionWatchdog();
      _startReconnectStallWatch(resumedCall ? 8000 : 20000);
    }

    if (!isDoctor && isReady && pc != null) {
      Timer(const Duration(milliseconds: 300), () {
        if (_disposed || _pc != pc) return;
        if (_isConnectedState(pc)) return;
        unawaited(_createAndSendOffer(iceRestart: inCall));
      });
    }

    // Doctor never self-initiates an offer (polite peer), so recovery after
    // a doctor-side reconnect otherwise depends on the connection watchdog.
    // When the server confirms this room was already active (resumedCall),
    // nudge the patient to renegotiate immediately instead of waiting.
    if (isDoctor && resumedCall && isReady && pc != null) {
      Timer(const Duration(milliseconds: 500), () {
        if (_disposed || _pc != pc) return;
        if (_isConnectedState(pc)) return;
        _requestPeerIceRestart();
      });
    }
  }

  void _handleParticipantLeft(dynamic _) {
    if (_disposed) return;
    _clearJoinTimeout();
    peerJoined = false;
    _lastRemoteFingerprint = null;
    isRemoteConnected = false;
    connectionState = 'disconnected';
    peerLeft = true;
    peerCameraOff = false;
    notifyListeners();
    _clearReconnectStallWatch();
  }

  void _handleChatMessage(dynamic raw) {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) {
      debugPrint('[video-call] chat_message received with non-Map data: $raw');
      return;
    }
    _logEvent('chat_received', {'senderId': data['senderId'], 'hasText': data['text'] is String && (data['text'] as String).isNotEmpty});

    // Own messages are only added here, once the server actually echoes
    // them back to the room — never optimistically on send (see
    // sendMessage/attachFile). VideoCall.jsx's handleChatMessage works the
    // same way: if the server silently drops a message (rate limiter,
    // socket hiccup), the sender never sees a false "delivered" state.
    try {
      messages.add(ChatMessage.fromJson(data));
    } catch (err) {
      debugPrint('[video-call] chat_message parse failed: $err');
      return;
    }

    if (!chatOpen) unreadCount++;
    notifyListeners();
  }

  void _handleChatHistory(dynamic raw) {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) {
      debugPrint('[video-call] chat_history received with non-Map data: $raw');
      return;
    }
    if (data['appointmentId'] != appointmentId) {
      debugPrint('[video-call] chat_history mismatched appointmentId: expected=$appointmentId got=${data['appointmentId']}');
      return;
    }
    final list = data['messages'] as List<dynamic>? ?? [];
    _logEvent('chat_history_received', {'count': list.length});
    messages
      ..clear()
      ..addAll(list.map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map))));
    // Only reached on a fully successful join (a denied join emits
    // room-access-denied instead and never gets here) — the reliable signal
    // that it's now safe to send queued chat, unlike socket.connected
    // alone, which flips true well before the async, DB-backed join
    // finishes processing server-side.
    _roomJoinConfirmed = true;
    _flushChatQueue();
    // Our own (re)join is now confirmed server-side — tell whoever's already
    // in the room our current camera state, in case we're the one who just
    // reconnected after toggling it earlier.
    _announceCameraState();
    notifyListeners();
  }

  Future<void> _handleApptUpdated(dynamic raw) async {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final status = data['status'];
    if ((status == 'complete' || status == 'completed') && !isDoctor) {
      showCompletedOverlay = true;
      notifyListeners();
      Timer(const Duration(seconds: 4), () {
        if (!_disposed) onCompletedByPeer?.call();
      });
      return;
    }
    // This app only ever authenticates as a patient (see the class doc
    // comment), so every appointment-cancelled-mid-call case lands here.
    // Previously unhandled — only "complete" redirected the patient, so a
    // mid-call cancellation (by the doctor or an admin) left the call
    // silently stalling with no explanation once the server's
    // evictAllFromAppointmentRoom dropped this socket from the room. Tear
    // the session down the same way _handleRoomDenied/_handleDuplicateSession
    // do — mirrors VideoCall.jsx's handleApptUpdated cancelled branch.
    if (status == 'cancelled' && !isDoctor) {
      await performCleanup();
      if (_disposed) return;
      apptError = 'This appointment was cancelled by an administrator.';
      notifyListeners();
    }
  }

  void _handleNewPrescription(dynamic raw) {
    if (_disposed || isDoctor) return;
    final data = _toMap(raw);
    if (data == null) return;
    prescriptionNotif = {'diagnosis': data['diagnosis']};
    notifyListeners();
    _prescriptionTimer?.cancel();
    _prescriptionTimer = Timer(const Duration(seconds: 10), () {
      if (_disposed) return;
      prescriptionNotif = null;
      notifyListeners();
    });
  }

  /// Cancels the auto-dismiss timer too — otherwise a user who dismisses (or
  /// taps "View" on) the toast early would see it silently reappear-then-
  /// vanish if the 10s timer fires afterward on a stale `prescriptionNotif`.
  void dismissPrescriptionNotif() {
    _prescriptionTimer?.cancel();
    _prescriptionTimer = null;
    if (prescriptionNotif == null) return;
    prescriptionNotif = null;
    notifyListeners();
  }

  Future<void> _handleRoomDenied(dynamic data) async {
    if (_disposed) return;
    // Previously left the camera/mic and RTCPeerConnection running
    // indefinitely behind the "Access Denied" screen — local media was
    // already acquired by startCallSession() independently of whether the
    // room join itself succeeded. Tear the session down the same way a
    // duplicate session does, instead of only changing what's shown.
    // Mirrors VideoCall.jsx's handleRoomDenied.
    await performCleanup();
    if (_disposed) return;
    final msg = (data is Map) ? data['msg']?.toString() : null;
    apptError = msg ?? 'Access to this call room was denied.';
    notifyListeners();
  }

  Future<void> _handleDuplicateSession(dynamic data) async {
    if (_disposed) return;
    // A newer session for this appointment has taken over. Tear this stale
    // session all the way down — tracks, timers, socket room, peer
    // connection, the Android ongoing-call notification — instead of only
    // closing the PC, so nothing (call timer, stats polling, socket
    // listeners, the foreground service) keeps running behind the "Access
    // Denied" screen this triggers. Mirrors VideoCall.jsx's
    // handleDuplicateSession, which calls performCleanup() for the same
    // reason.
    await performCleanup();
    if (_disposed) return;
    final msg = (data is Map) ? data['msg']?.toString() : null;
    apptError = msg ?? 'Another consultation session was started elsewhere.';
    notifyListeners();
  }

  // The backend forcibly removes a socket from the appointment room (and
  // emits this) when the appointment is reassigned to a different doctor,
  // or — as a defensive fallback with no more specific reason — in any
  // other case access is revoked outside the normal complete/cancel flow.
  // "completed"/"cancelled" are deliberately excluded here: those already
  // get their own, friendlier messaging via appointment-updated (the
  // completed-overlay redirect and the cancellation handling above) —
  // reacting to them here too would just race that messaging with a
  // blunter "Access Denied" screen for the exact same event. Mirrors
  // VideoCall.jsx's handleAccessRevoked.
  Future<void> _handleAccessRevoked(dynamic data) async {
    if (_disposed) return;
    final map = _toMap(data);
    final reason = map?['reason']?.toString();
    if (reason == 'completed' || reason == 'cancelled') return;
    await performCleanup();
    if (_disposed) return;
    final msg = map?['msg']?.toString();
    apptError = msg ?? 'You no longer have access to this appointment.';
    notifyListeners();
  }

  // ── Socket connection lifecycle ──────────────────────────────────────

  void _registerSocketListeners() {
    // Idempotent: listeners now survive a rebuild, so startCallSession must
    // not stack a second copy of each handler.
    _unregisterSocketListeners();
    _socket.on('video-offer', _handleOffer);
    _socket.on('video-answer', _handleAnswer);
    _socket.on('ice-candidate', _handleIce);
    _socket.on('ice-restart-request', _handleIceRestartRequest);
    _socket.on('request-peer-rebuild', _handlePeerRebuildRequest);
    _socket.on('camera-state', _handleCameraState);
    _socket.on('peer-joined', _handlePeerJoined);
    _socket.on('participant-left', _handleParticipantLeft);
    _socket.on('appointment-message', _handleChatMessage);
    _socket.on('appointment-chat-history', _handleChatHistory);
    _socket.on('appointment-updated', _handleApptUpdated);
    _socket.on('new-prescription', _handleNewPrescription);
    _socket.on('room-access-denied', _handleRoomDenied);
    _socket.on('duplicate-session', _handleDuplicateSession);
    _socket.on('appointment-access-revoked', _handleAccessRevoked);
    _socket.on('connect', _handleSocketConnect);
    _socket.on('disconnect', _handleSocketDisconnect);
    _socket.on('connect_error', _handleSocketConnectError);
    _socket.onManager('reconnect', _handleSocketReconnect);
  }

  void _unregisterSocketListeners() {
    _socket.off('video-offer', _handleOffer);
    _socket.off('video-answer', _handleAnswer);
    _socket.off('ice-candidate', _handleIce);
    _socket.off('ice-restart-request', _handleIceRestartRequest);
    _socket.off('request-peer-rebuild', _handlePeerRebuildRequest);
    _socket.off('camera-state', _handleCameraState);
    _socket.off('peer-joined', _handlePeerJoined);
    _socket.off('participant-left', _handleParticipantLeft);
    _socket.off('appointment-message', _handleChatMessage);
    _socket.off('appointment-chat-history', _handleChatHistory);
    _socket.off('appointment-updated', _handleApptUpdated);
    _socket.off('new-prescription', _handleNewPrescription);
    _socket.off('room-access-denied', _handleRoomDenied);
    _socket.off('duplicate-session', _handleDuplicateSession);
    _socket.off('appointment-access-revoked', _handleAccessRevoked);
    _socket.off('connect', _handleSocketConnect);
    _socket.off('disconnect', _handleSocketDisconnect);
    _socket.off('connect_error', _handleSocketConnectError);
    _socket.offManager('reconnect', _handleSocketReconnect);
  }

  bool _emitOnlineAndJoinRoom() {
    if (!_socket.connected || !isReady) return false;
    if (_joinedSocketId == _socket.id) return true;

    _joinedSocketId = _socket.id ?? '';
    if (connectionState != 'connected') {
      connectionState = 'connecting';
      notifyListeners();
    }

    _startJoinTimeout();

    final activeUserId = isDoctor ? doctorId : userId;
    final activeRole = isDoctor ? 'doctor' : 'user';
    unawaited(_emitOnlineAndJoinRoomPayload(activeUserId, activeRole));
    return true;
  }

  /// Split out from `_emitOnlineAndJoinRoom` because fetching the token is
  /// async while the join dedup check above must stay synchronous. Explicit,
  /// role-scoped `token` on both emits — matches VideoCall.jsx: each event is
  /// handled independently and asynchronously on the server, so
  /// join-appointment-room can't assume user-online (emitted first) has
  /// already finished resolving identity from the connection-time auth
  /// snapshot alone (see server.js's resolveSocketIdentity). This app only
  /// ever authenticates as a patient today, so the connection-time handshake
  /// token is normally enough on its own — this is defense-in-depth so
  /// per-event identity resolution stays correct if that ever changes.
  Future<void> _emitOnlineAndJoinRoomPayload(String activeUserId, String role) async {
    // The access token can have expired since the call started or since the
    // last (re)join — 15-minute TTL — and this fires on *every* rejoin
    // trigger, not just the app-resume one (_reconnectAfterResume already
    // refreshes for that specific case): a plain signaling-socket reconnect
    // (cellular handoff, brief Wi-Fi drop, server restart) mid-call re-emits
    // the join here too, and without a fresh token that rejoin was being
    // sent with whatever was already in storage — silently rejected as
    // unauthenticated (room-access-denied) if it had expired in the
    // meantime. Non-fatal: proceed with whatever's in storage on failure,
    // same pattern used everywhere else this refresh is called.
    try {
      await ApiService.instance.refreshAccessToken(isDoctor ? 'doctor' : 'user');
    } catch (_) {
      // Ignore — fall through with the existing stored token.
    }
    if (_disposed) return;

    // `_joinedSocketId` was already marked "joined" synchronously by the
    // caller before this ran (see its comment) — if the secure-storage read
    // below throws (a real Android failure mode: Keystore invalidated by an
    // OS backup/restore or biometric reset) without this try/catch, both
    // emits below would be skipped but the dedup marker would stay set,
    // permanently blocking every future join attempt on this socket
    // connection. Falling back to an empty token instead still lets the
    // join through — the connection-time handshake token (see
    // SocketService's authFn) is normally sufficient on its own; this
    // per-event token is defense-in-depth, not the only identity signal.
    String token = '';
    try {
      token = await const TokenStorageService().getToken() ?? '';
    } catch (err) {
      debugPrint('[video-call] token fetch for room join failed, joining without it: $err');
    }

    if (activeUserId.isNotEmpty) {
      _socket.emit('user-online', {
        'userId': activeUserId,
        'role': role,
        'token': token,
      });
    }
    _socket.emit('join-appointment-room', {
      'appointmentId': appointmentId,
      'userId': activeUserId,
      'role': role,
      'token': token,
      // Items 1-4 (listeners kept across rebuilds, offer stash, fingerprint
      // rebuilds, request-peer-rebuild) are implemented — tell the server
      // a peer doctor may use the request-peer-rebuild handshake with us.
      'capabilities': {'peerRebuild': true},
    });
    _logEvent('appointment_room_join_requested', {'socketId': _socket.id});
  }

  void _handleSocketConnect(dynamic _) {
    _emitOnlineAndJoinRoom();
    _resyncConnectionStateFromPeerConnection();
  }

  void _handleSocketDisconnect(dynamic reason) {
    _joinedSocketId = '';
    _roomJoinConfirmed = false;
    if (_disposed) return;
    _logEvent('socket_disconnected_during_call', {'inCall': inCall});
    connectionState = 'disconnected';
    isRemoteConnected = false;
    notifyListeners();
    // Safety net for the case the signaling socket itself stays down for a
    // while during an active call: the peer connection's own state-change
    // handlers already arm this when THEY see a real drop, but a signaling-
    // only outage (server restart, prolonged reconnect backoff) might never
    // trip those at all if the underlying media path happens to survive it.
    // Harmless if it turns out to be a brief blip — _resyncConnectionState-
    // FromPeerConnection clears it again the moment the socket reconnects
    // and finds the peer connection still healthy.
    if (inCall) _startReconnectStallWatch(kMidCallReconnectStallMs);
  }

  // A Socket.IO (signaling) drop is a different transport than the already-
  // established WebRTC/ICE media path — a brief blip here (NAT rebind, app
  // backgrounding, cellular handoff) doesn't necessarily mean the peer
  // connection itself was ever affected. If it wasn't, neither
  // _handleConnectionStateChange nor _handleIceConnectionStateChange ever
  // fires again (no state transition happened), and those callbacks are the
  // only place _handleConnectedState() normally gets called from — so
  // nothing would ever clear the 'disconnected' flags _handleSocketDisconnect
  // just set, permanently stranding the UI on "Reconnecting..." over a call
  // that's actually still working. Called after every (re)connect to
  // immediately resync from the peer connection's actual current state
  // instead of waiting on an event that may never come.
  void _resyncConnectionStateFromPeerConnection() {
    final pc = _pc;
    if (pc == null || connectionState == 'connected') return;
    if (_isConnectedState(pc)) _handleConnectedState();
  }

  void _handleSocketConnectError(dynamic err) {
    if (_disposed) return;
    _logEvent('socket_connect_error', {'error': err.toString()});
    if (!isReady) {
      _showInlineMessage(
        'Connection to the call service failed. Please check your internet and try again.',
        const Duration(seconds: 8),
      );
    }
  }

  void _handleSocketReconnect(dynamic _) {
    if (_disposed) return;
    _joinedSocketId = '';
    _emitOnlineAndJoinRoom();
    _logEvent('socket_reconnected_during_call', {
      'inCall': inCall,
      'role': isDoctor ? 'doctor' : 'user',
    });
    _resyncConnectionStateFromPeerConnection();

    final pc = _pc;
    if (pc == null) return;

    if (isDoctor) {
      Timer(const Duration(milliseconds: 500), () {
        if (_disposed || !_socket.connected || _pc != pc) return;
        if (_isConnectedState(pc)) return;
        _requestPeerIceRestart();
      });
      return;
    }
    if (isReady) {
      Timer(const Duration(milliseconds: 500), () {
        if (_disposed || !_socket.connected || _pc != pc) return;
        if (_isConnectedState(pc)) return;
        unawaited(_createAndSendOffer(iceRestart: inCall));
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Controls
  // ─────────────────────────────────────────────────────────────────────

  void toggleMute() {
    isMuted = !isMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !isMuted);
    notifyListeners();
  }

  void toggleCamera() {
    isCamOff = !isCamOff;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !isCamOff);
    _announceCameraState();
    notifyListeners();
  }

  // Tells the peer our current camera on/off state — see peerCameraOff's doc
  // for why this signal has to exist at all. Re-announced (not just sent on
  // toggle) whenever either side (re)joins the room — see the calls in
  // _handlePeerJoined and _handleChatHistory — so a peer that reconnects
  // after we toggled, or that we ourselves reconnect into after they
  // toggled, isn't left with stale state.
  void _announceCameraState() {
    if (!_socket.connected) return;
    _socket.emit('camera-state', {
      'appointmentId': appointmentId,
      'isCamOff': isCamOff,
    });
  }

  void _handleCameraState(dynamic raw) {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final off = data['isCamOff'] == true;
    if (peerCameraOff == off) return;
    peerCameraOff = off;
    _logEvent('peer_camera_state_changed', {'isCamOff': off});
    notifyListeners();
  }

  // ── Audio route (speakerphone/earpiece) ─────────────────────────────
  // No React equivalent — a browser tab has no earpiece to route to.
  // Best-effort throughout: a failure here should never block the call
  // itself, only leave the audio route wherever the OS/plugin defaulted it.

  Future<void> _applySpeakerphonePreference() async {
    if (kIsWeb) return;
    try {
      await Helper.setSpeakerphoneOn(isSpeakerOn);
    } catch (err) {
      debugPrint('[video-call] setSpeakerphoneOn (initial) failed: $err');
    }
  }

  Future<void> toggleSpeaker() async {
    if (kIsWeb) return;
    final next = !isSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
      isSpeakerOn = next;
      notifyListeners();
    } catch (err) {
      debugPrint('[video-call] toggleSpeaker failed: $err');
      _showInlineMessage('Could not switch audio output on this device.');
    }
  }

  // ── Camera flip (front/back) ─────────────────────────────────────────
  // No React equivalent — a browser tab has no front/back camera facing
  // concept exposed the same way.
  //
  // Deliberately NOT using flutter_webrtc's Helper.switchCamera(). On
  // native platforms that calls mediaStreamTrackSwitchCamera, which swaps
  // the physical camera *in place* on the SAME MediaStreamTrack/capturer —
  // the plugin's own Android sources resolve "shared" track entries back to
  // one primary capturer for this call. In practice that in-place swap can
  // leave the native camera session's frames briefly attached to whichever
  // texture/renderer the OS compositor hands them to next, which is what
  // produced the reported bug: right after flipping, the local user's own
  // face appeared in BOTH the main stage and the pip, even though the main
  // stage is bound to the *remote* stream and has nothing to do with the
  // local camera. Requesting a brand-new track via getUserMedia and
  // swapping it onto the existing sender with replaceTrack() — the same
  // mechanism _attachLocalMediaStream already uses for reconnects — avoids
  // that shared-capturer path entirely: the new track has its own id and
  // its own independent native capture session, so there is no leftover
  // state for any renderer to pick up.
  //
  // RTCVideoRenderer.srcObject is still pointing at the same MediaStream
  // object before and after (only its tracks changed), so Flutter's
  // renderer would otherwise treat it as an unchanged reference and keep
  // painting the old camera's last frame — same staleness class
  // _refreshRemoteStreamBinding works around for the remote stream. Forcing
  // the local renderer to detach/reattach after a successful switch makes
  // it treat the new track as a genuine source change.
  Future<void> switchCamera() async {
    if (kIsWeb) return;
    // Re-entrancy guard: a second tap landing before the first call's
    // getUserMedia/replaceTrack sequence finishes would otherwise read the
    // same stale oldTrack/isFrontCamera, race to replace the sender
    // independently, and leak whichever track loses the race — see the
    // switchCamera concurrency finding this guard fixes. Checked/set
    // synchronously, before this call's first await, so no interleaving
    // invocation can slip through.
    if (_switchingCamera) return;
    final pc = _pc;
    final stream = _localStream;
    if (pc == null || stream == null) return;
    final oldTrack =
        stream.getVideoTracks().isNotEmpty ? stream.getVideoTracks().first : null;
    if (oldTrack == null) return;

    _switchingCamera = true;
    try {
      try {
        final cams = await Helper.cameras;
        if (cams.length < 2) {
          _showInlineMessage('No other camera is available on this device.');
          return;
        }
      } catch (_) {
        // Best-effort — if enumeration fails, fall through and let the
        // getUserMedia call below be the source of truth.
      }

      final videoConstraints = Map<String, dynamic>.from(kMediaConstraints['video'] as Map);
      videoConstraints['facingMode'] = isFrontCamera ? 'environment' : 'user';

      MediaStream? newStream;
      // True once newTrack has been committed to the outgoing sender — from
      // that point on the peer is actively receiving it, so the failure
      // cleanup below must never stop it (that would break their already-live
      // video instead of just failing the switch); it only discards newTrack
      // for a failure that happens before that commit point.
      var committedToSender = false;
      try {
        newStream = await navigator.mediaDevices
            .getUserMedia({'audio': false, 'video': videoConstraints});
        final newTrack =
            newStream.getVideoTracks().isNotEmpty ? newStream.getVideoTracks().first : null;
        if (newTrack == null) throw 'no video track returned';

        // The session moved on (disposed / peer connection or local stream
        // replaced) while getUserMedia was in flight — discard the freshly
        // captured track rather than attaching it to a stale session.
        if (_disposed || _pc != pc || _localStream != stream) {
          for (final t in newStream.getTracks()) {
            await t.stop();
          }
          return;
        }

        final transceiver = await _getTransceiverForKind(pc, 'video');
        final sender = transceiver?.sender;
        if (sender != null) {
          await sender.replaceTrack(newTrack);
          committedToSender = true;
          await _tuneSenderQuality(
            sender,
            maxBitrate: kCameraBitrate,
            maxFramerate: 30,
            maintainResolution: true,
          );
        }

        newTrack.enabled = !isCamOff;
        _attachLocalTrackEndedListener(newTrack);
        await stream.removeTrack(oldTrack);
        await stream.addTrack(newTrack);
        await oldTrack.stop();

        isFrontCamera = !isFrontCamera;
        _refreshLocalStreamBinding();
        notifyListeners();
      } catch (err) {
        debugPrint('[video-call] switchCamera failed: $err');
        if (newStream != null && !committedToSender) {
          for (final t in newStream.getTracks()) {
            await t.stop();
          }
        }
        _showInlineMessage('Could not switch camera on this device.');
      }
    } finally {
      _switchingCamera = false;
    }
  }

  // Whichever renderer is currently showing the local stream (pip normally,
  // or main when swapped) — forces it to re-bind so a same-reference stream
  // update (e.g. after switchCamera) is repainted instead of left stale.
  void _refreshLocalStreamBinding() {
    if (_disposed || _localStream == null) return;
    final localRenderer = isSwapped ? mainRenderer : pipRenderer;
    localRenderer.srcObject = null;
    localRenderer.srcObject = _localStream;
  }
  void toggleSwap() {
    isSwapped = !isSwapped;
    _assignStreams(isSwapped);
    notifyListeners();
  }

  void setChatOpen(bool open) {
    chatOpen = open;
    if (open) unreadCount = 0;
    notifyListeners();
  }

  /// First line of defense against a stuck Enter key / paste-loop flooding
  /// chat — the server has its own rate limit (chatMessageLimiter in
  /// backend/server.js), this just keeps the UI itself from firing faster
  /// than a human can type. Mirrors VideoCall.jsx's CHAT_SEND_COOLDOWN_MS.
  void sendMessage(String text) {
    if (chatSendCoolingDown) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final senderId = currentUser['id'] ?? '';
    final senderName = currentUser['name'] ?? '';
    _logEvent('chat_send', {'text': trimmed.length > 50 ? '${trimmed.substring(0, 50)}...' : trimmed});
    final payload = {
      'appointmentId': appointmentId,
      'senderId': senderId,
      'senderName': senderName,
      'text': trimmed,
    };
    if (_socket.connected && _roomJoinConfirmed) {
      _socket.emit('appointment-message', payload);
    } else {
      // Not confirmed joined yet (disconnected, or reconnecting but the
      // server hasn't finished processing join-appointment-room) — queue
      // instead of emitting now. socket_io_client would otherwise
      // auto-buffer this and flush it before our own reconnect handler
      // re-joins the room, which the server silently drops since it isn't
      // a room member yet.
      _chatQueue.add(payload);
      if (_chatQueue.length > kChatQueueMax) {
        _chatQueue.removeAt(0);
      }
    }
    chatSendCoolingDown = true;
    notifyListeners();
    _chatSendCooldownTimer?.cancel();
    _chatSendCooldownTimer = Timer(const Duration(milliseconds: kChatSendCooldownMs), () {
      _chatSendCooldownTimer = null;
      if (_disposed) return;
      chatSendCoolingDown = false;
      notifyListeners();
    });
  }

  Future<void> attachFile(UploadCandidate file) async {
    if (file.sizeBytes > 10 * 1024 * 1024) {
      _showInlineMessage('File too large. Max 10 MB.');
      return;
    }
    uploadingFile = true;
    notifyListeners();
    try {
      final uploaded = await uploadFileDirectToS3(file);
      final senderId = currentUser['id'] ?? '';
      final senderName = currentUser['name'] ?? '';
      _logEvent('chat_attach', {'name': uploaded.name, 'type': uploaded.type});
      _socket.emit('appointment-message', {
        'appointmentId': appointmentId,
        'senderId': senderId,
        'senderName': senderName,
        'text': '',
        'fileUrl': uploaded.key,
        'fileName': uploaded.name,
        'fileType': uploaded.type,
      });
    } catch (err) {
      final message = err.toString().replaceFirst('Exception: ', '');
      _showInlineMessage(message.isNotEmpty ? message : 'File upload failed.');
    } finally {
      uploadingFile = false;
      notifyListeners();
    }
  }

  void _showInlineMessage(String message, [Duration duration = const Duration(seconds: 4)]) {
    inlineError = message;
    notifyListeners();
    _inlineErrorTimer?.cancel();
    _inlineErrorTimer = Timer(duration, () {
      if (_disposed) return;
      inlineError = '';
      notifyListeners();
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // Call lifecycle: leave / complete / cleanup
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _teardownSession({bool leaveRoom = true, bool keepListeners = false}) async {
    // A rebuild keeps the listeners registered — unregistering them left a
    // "deaf window" in which an offer from the peer's own rebuild was dropped.
    if (!keepListeners) _unregisterSocketListeners();
    _lastRemoteFingerprint = null;
    _callTimer?.cancel();
    _callTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
    _connectionFailTimer?.cancel();
    _connectionFailTimer = null;
    _ignoreOfferResetTimer?.cancel();
    _ignoreOfferResetTimer = null;
    _reconnectStallTimer?.cancel();
    _reconnectStallTimer = null;
    _clearJoinTimeout();
    _stopStatsCollection();

    if (leaveRoom && _joinedSocketId.isNotEmpty && _socket.connected) {
      _socket.emit('leave-appointment-room', {'appointmentId': appointmentId});
    }

    final pc = _pc;
    // TEMPORARY (RETRY_DEBUG)
    if (pc != null) {
      retryDebugLog(isDoctor, appointmentId, '_teardownSession:closing_pc', {
        'connectionState': pc.connectionState?.toString(),
        'iceConnectionState': pc.iceConnectionState?.toString(),
        'signalingState': pc.signalingState?.toString(),
        'pcAgeMs': DateTime.now().difference(_pcCreatedAt).inMilliseconds,
      });
    }
    _pc = null;
    await pc?.close();

    await CallForegroundService.stop();
    _foregroundServiceStarted = false;

    _pendingRemoteCandidates.clear();
    _joinedSocketId = '';
    _ignoreOffer = false;
    _restartRequestInFlight = false;
    _pendingOfferId = null;
    _lastReceivedOfferId = null;
    _lastRttMs = null;
    _clearOfferAnswerTimeout();

    // Reset all call state so a subsequent startCallSession (via
    // forceReconnect) starts fresh — stale isReady or peerJoined caused
    // premature offer attempts with a newly created RTCPeerConnection
    // whose signalingState may not have initialized yet.
    isReady = false;
    peerJoined = false;
    peerLeft = false;
    inCall = false;
    isRemoteConnected = false;
    hasConnectedOnce = false;
    _remoteRebindPending = false;
    peerCameraOff = false;
    // Every fresh getUserMedia call re-requests facingMode: 'user' (see
    // kMediaConstraints) — the physical camera really does reset to front on
    // a reconnect, so this flag would otherwise go stale and misreport the
    // actual device state. isSpeakerOn is deliberately NOT reset here: it's
    // a user preference that _applySpeakerphonePreference re-applies to the
    // freshly recreated audio session on the next startCallSession, not
    // camera-hardware state tied to this specific getUserMedia call.
    isFrontCamera = true;
    camError = false;
    camErrorReason = '';
    camPermissionPermanentlyDenied = false;
    deviceCheckStatus = 'idle';
    connectionState = 'idle';
    _iceRecoveryAttempts = 0;
    _lastIceRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);
    _makingOffer = false;
  }

  /// [emitLeave] mirrors React's `pageUnloadingRef` gate on the
  /// `leave-appointment-room` emit: user-initiated leaves (leaveCall,
  /// completeAppointment, normal widget dispose) should tell the peer
  /// immediately, but an app-process kill (see
  /// `didChangeAppLifecycleState(AppLifecycleState.detached)` in the
  /// screen) should not — the socket disconnecting on its own gives the
  /// server's grace-period logic a chance to treat a quick relaunch as a
  /// resume instead of an abrupt "peer left".
  Future<void> performCleanup({bool emitLeave = true}) async {
    if (_completedFlag) return;
    _completedFlag = true;

    await _teardownSession(leaveRoom: emitLeave);
    _pendingRemoteOffer = null;
    _pendingRemoteOfferAt = null;

    final tracks = _localStream?.getTracks() ?? const [];
    for (final t in tracks) {
      try {
        await t.stop();
      } catch (err) {
        // dispose() fires this via unawaited(performCleanup()) — best-effort
        // cleanup, so a track.stop() failure (seen on some device/OEM native
        // WebRTC plugins) must not become an unhandled Future rejection with
        // nothing left to catch it.
        debugPrint('[video-call] track.stop() failed during cleanup: $err');
      }
    }
    _localStream = null;
  }

  Future<void> leaveCall() async {
    if (completing) return;
    await performCleanup();
  }

  Future<bool> completeAppointment() async {
    if (!isDoctor || completing) return false;
    completing = true;
    notifyListeners();
    try {
      final status = appt?['status'];
      if (status == 'assigned' || status == 'confirmed') {
        await ApiService.instance.put('/api/appointments/$appointmentId/complete', const {});
      }
      await performCleanup();
      return true;
    } catch (err) {
      completing = false;
      _showInlineMessage(
        'Failed to complete appointment. Please try again.',
        const Duration(seconds: 5),
      );
      return false;
    }
  }

  // ── WebRTC connection-quality stats polling ─────────────────────────
  // Ported from VideoCall.jsx's startStatsCollection/stopStatsCollection —
  // same STATS_INTERVAL_MS cadence and the same `webrtc_stats` telemetry
  // event/shape, so mobile calls surface in the same monitoring data as web.

  void _stopStatsCollection() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _lastStatsSample = null;
    connectionQuality = 'unknown';
  }

  void _startStatsCollection(RTCPeerConnection pc) {
    _stopStatsCollection();
    _statsTimer = Timer.periodic(
      const Duration(milliseconds: kStatsIntervalMs),
      (_) async {
        if (_disposed ||
            pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
          _stopStatsCollection();
          return;
        }
        try {
          final stats = await pc.getStats();
          final diagnostics = <String, dynamic>{
            'rtt': null,
            'packetsSent': 0,
            'packetsLost': 0,
            'bytesSent': 0,
            'bytesReceived': 0,
            'localCandidateType': 'unknown',
            'remoteCandidateType': 'unknown',
            'selectedPairState': 'unknown',
          };

          for (final report in stats) {
            if (report.type != 'candidate-pair' ||
                report.values['state'] != 'succeeded') {
              continue;
            }
            diagnostics['selectedPairState'] = report.values['state'];

            final rtt = report.values['currentRoundTripTime'];
            if (rtt is num) diagnostics['rtt'] = (rtt * 1000).round();
            final bytesSent = report.values['bytesSent'];
            if (bytesSent is num) diagnostics['bytesSent'] = bytesSent;
            final bytesReceived = report.values['bytesReceived'];
            if (bytesReceived is num) {
              diagnostics['bytesReceived'] = bytesReceived;
            }
            final packetsSent = report.values['packetsSent'];
            if (packetsSent is num) diagnostics['packetsSent'] = packetsSent;
            final packetsLost = report.values['packetsLost'];
            if (packetsLost is num) diagnostics['packetsLost'] = packetsLost;

            final localId = report.values['localCandidateId'];
            final remoteId = report.values['remoteCandidateId'];
            for (final inner in stats) {
              if (inner.type == 'local-candidate' && inner.id == localId) {
                diagnostics['localCandidateType'] =
                    inner.values['candidateType'] ?? inner.type;
              }
              if (inner.type == 'remote-candidate' && inner.id == remoteId) {
                diagnostics['remoteCandidateType'] =
                    inner.values['candidateType'] ?? inner.type;
              }
            }
          }

          debugPrint('[webrtc-stats] $diagnostics');
          _logEvent('webrtc_stats', diagnostics);

          final rtt = diagnostics['rtt'];
          if (rtt is num) _lastRttMs = rtt;

          final quality = deriveConnectionQuality(diagnostics, _lastStatsSample);
          _lastStatsSample = {
            'packetsSent': diagnostics['packetsSent'] as num,
            'packetsLost': diagnostics['packetsLost'] as num,
          };
          if (!_disposed) {
            connectionQuality = quality;
            notifyListeners();
          }
        } catch (err) {
          debugPrint('[webrtc-stats] getStats failed: $err');
        }
      },
    );
  }

  // ── Lightweight telemetry ────────────────────────────────────────────
  // Events fired while the socket is disconnected (e.g. during a network
  // blip mid-call — exactly the scenario the ICE-restart machinery handles)
  // are queued and replayed once it reconnects, rather than lost — mirrors
  // VideoCall.jsx's telemetryQueueRef/flushTelemetryQueue.
  final List<Map<String, dynamic>> _telemetryQueue = [];

  void _flushTelemetryQueue() {
    if (!_socket.connected || _telemetryQueue.isEmpty) return;
    final queued = List<Map<String, dynamic>>.from(_telemetryQueue);
    _telemetryQueue.clear();
    for (final payload in queued) {
      _socket.emit('video-telemetry', payload);
    }
  }

  // True only once appointment-chat-history has confirmed join-appointment-room
  // fully completed for the CURRENT connection — socket.connected alone isn't
  // enough, since that flips true before the server's async, DB-backed join
  // finishes processing (the exact race that used to silently drop a chat
  // message sent right at reconnect). See _handleChatHistory/_flushChatQueue.
  bool _roomJoinConfirmed = false;
  final List<Map<String, dynamic>> _chatQueue = [];

  void _flushChatQueue() {
    if (!_socket.connected || _chatQueue.isEmpty) return;
    final queued = List<Map<String, dynamic>>.from(_chatQueue);
    _chatQueue.clear();
    for (final payload in queued) {
      _socket.emit('appointment-message', payload);
    }
  }

  void _logEvent(String event, Map<String, dynamic> details) {
    debugPrint('[video-call] $event $details');
    if (appointmentId.isEmpty) return;

    final payload = {
      'appointmentId': appointmentId,
      'event': event,
      'role': isDoctor ? 'doctor' : 'user',
      'timestamp': DateTime.now().toIso8601String(),
      'details': details,
    };

    if (_socket.connected) {
      _flushTelemetryQueue();
      _socket.emit('video-telemetry', payload);
    } else {
      _telemetryQueue.add(payload);
      if (_telemetryQueue.length > kTelemetryQueueMax) {
        _telemetryQueue.removeAt(0);
      }
    }
  }
}
