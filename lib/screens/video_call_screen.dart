// video_call_screen.dart
//
// Flutter conversion of the React "VideoCall" page.
// Same backend, same REST endpoints, same socket.io signaling protocol,
// same business rules (role detection, gate screens, call lifecycle,
// chat, screen share, prescriptions) — only the rendering layer changes.
//
// ── Backend / event contract kept 100% identical ──────────────────────
//   REST:
//     GET  /api/appointments/patient/:id
//     GET  /api/appointments/doctor/:id
//     PUT  /api/appointments/:id/complete
//     POST /api/medical/prescriptions
//     POST /api/auth/refresh                 (session heartbeat)
//   Socket events (in): video-offer, video-answer, ice-candidate,
//     peer-joined, participant-left, appointment-message,
//     appointment-chat-history, appointment-updated, new-prescription,
//     room-access-denied
//   Socket events (out): user-online, join-appointment-room,
//     leave-appointment-room, video-offer, video-answer, ice-candidate,
//     appointment-message
//
// ── Required pubspec.yaml packages ─────────────────────────────────────
//   flutter_webrtc: ^0.10.0     (RTCPeerConnection / getUserMedia / getDisplayMedia)
//   socket_io_client: ^2.0.3+1
//   http: ^1.2.0
//   file_picker: ^8.0.0         (chat file attachment, replaces <input type=file>)
//   intl: ^0.19.0
//
// ── Project wiring assumed (mirrors api.js / socket.js / AuthContext /
//    DoctorAuthContext / utils/directUpload.js) ─────────────────────────
//   lib/services/api_service.dart        -> ApiService.instance.get/post/put
//   lib/services/socket_service.dart     -> SocketService.instance (socket_io_client)
//   lib/providers/auth_provider.dart     -> AuthProvider.of(context).user / loading
//   lib/providers/doctor_auth_provider.dart -> DoctorAuthProvider.of(context).doctor / loading
//   lib/utils/direct_upload.dart         -> uploadFileDirectToS3(file) -> {key/url, name, type}
//
// Platform notes:
//   * Screen sharing (getDisplayMedia) only works out-of-the-box on Web
//     and Desktop builds of flutter_webrtc; Android/iOS require native
//     foreground-service screen-capture wiring. The button below calls
//     getDisplayMedia and surfaces a friendly error if unsupported,
//     exactly like the browser would if permission were denied.
//   * "Fullscreen" is mapped to Android/iOS immersive mode via SystemChrome.
//   * "beforeunload" (browser tab close) has no true mobile equivalent;
//     we cover the same intent with WidgetsBindingObserver's `detached`
//     lifecycle state and the widget's dispose().
//   * Browser back-button interception is mapped to PopScope.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/direct_upload.dart';

/// =====================================================================
/// Constants (identical values to the React file)
/// =====================================================================

const Map<String, dynamic> kStunServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun3.l.google.com:19302'},
    {'urls': 'stun:stun4.l.google.com:19302'},
  ],
};

const Map<String, dynamic> kMediaConstraints = {
  'audio': {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
  },
  'video': {
    'width': {'ideal': 1920, 'max': 1920},
    'height': {'ideal': 1080, 'max': 1080},
    'frameRate': {'ideal': 30, 'max': 30},
    'facingMode': 'user',
  },
};

class BitrateProfile {
  static const int cameraVideo = 2500000;
  static const int screenShareVideo = 4000000;
  static const int voiceAudio = 128000;
}

String mediaErrorMessage(Object err) {
  final msg = err.toString();
  if (msg.contains('NotAllowedError') || msg.contains('PermissionDeniedError')) {
    return "Camera/microphone permission was denied. Allow access in your device settings, then retry.";
  }
  if (msg.contains('NotFoundError') || msg.contains('DevicesNotFoundError')) {
    return "No camera or microphone was found on this device.";
  }
  if (msg.contains('NotReadableError') || msg.contains('TrackStartError')) {
    return "Your camera or microphone is already in use by another app. Close it and retry.";
  }
  return "Camera or microphone access failed. Check app permissions and reload.";
}

Future<void> tuneSenderQuality(
  RTCRtpSender? sender, {
  int? maxBitrate,
  double? maxFramerate,
  bool maintainResolution = false,
}) async {
  if (sender == null || sender.track == null) return;
  try {
    final params = sender.parameters;
    final encodings = params.encodings ?? [RTCRtpEncoding()];
    final encoding = encodings.isNotEmpty ? encodings.first : RTCRtpEncoding();
    if (maxBitrate != null) encoding.maxBitrate = maxBitrate;
    if (maxFramerate != null) encoding.maxFramerate = maxFramerate.toInt();
    if (maintainResolution) {
      encoding.scaleResolutionDownBy ??= 1;
    }
    params.encodings = [encoding, ...encodings.skip(1)];
    await sender.setParameters(params);
  } catch (_) {
    // Mirrors the swallowed try/catch in the original.
  }
}

String fmtDate(String? d) {
  if (d == null || d.isEmpty) return '—';
  final parsed = DateTime.tryParse(d);
  if (parsed == null) return d;
  return DateFormat('d MMM y', 'en_IN').format(parsed);
}

String fmtTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  return DateFormat('h:mm a').format(parsed);
}

String fmtDuration(int secs) {
  final h = secs ~/ 3600;
  final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (secs % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// =====================================================================
/// Chat message model
/// =====================================================================

class ChatMessage {
  final String senderId;
  final String senderName;
  final String text;
  final String? fileUrl;
  final String? fileName;
  final String? fileType;
  final String? createdAt;

  ChatMessage({
    required this.senderId,
    required this.senderName,
    this.text = '',
    this.fileUrl,
    this.fileName,
    this.fileType,
    this.createdAt,
  });

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

/// =====================================================================
/// In-call prescription modal (doctor only)
/// =====================================================================

class _EmptyMed {
  String name = '';
  String dosage = '';
  String frequency = '';
  String duration = '';
  Map<String, dynamic> toJson() =>
      {'name': name, 'dosage': dosage, 'frequency': frequency, 'duration': duration};
}

class InCallPrescriptionModal extends StatefulWidget {
  final Map<String, dynamic> appt;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  const InCallPrescriptionModal({
    super.key,
    required this.appt,
    required this.onClose,
    required this.onSaved,
  });

  @override
  State<InCallPrescriptionModal> createState() =>
      _InCallPrescriptionModalState();
}

class _InCallPrescriptionModalState extends State<InCallPrescriptionModal> {
  final _diagnosisCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  DateTime? _followUpDate;
  final List<_EmptyMed> _medicines = [_EmptyMed()];
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _diagnosisCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_diagnosisCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Diagnosis is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final doctorAppt = widget.appt;
      final patientId = (doctorAppt['patientId'] is Map)
          ? doctorAppt['patientId']['_id']
          : doctorAppt['patientId'];

      await ApiService.instance.post('/api/medical/prescriptions', {
        'appointmentId': doctorAppt['_id'],
        'patientId': patientId,
        'diagnosis': _diagnosisCtrl.text,
        'medicines': _medicines
            .where((m) => m.name.trim().isNotEmpty)
            .map((m) => m.toJson())
            .toList(),
        'instructions': _instructionsCtrl.text,
        'followUpDate':
            _followUpDate != null ? _followUpDate!.toIso8601String() : '',
      });
      widget.onSaved();
    } catch (err) {
      setState(() {
        _error = 'Failed to save prescription.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('💊 ', style: TextStyle(fontSize: 20)),
                    const Expanded(
                      child: Text('Issue Prescription',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                if (_error.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error,
                        style: TextStyle(color: Colors.red.shade700)),
                  ),
                const Text('Diagnosis *',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                TextField(
                  controller: _diagnosisCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Acute viral pharyngitis',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Medicines',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ..._medicines.asMap().entries.map((entry) {
                  final i = entry.key;
                  final med = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            decoration: const InputDecoration(
                                hintText: 'Medicine',
                                isDense: true,
                                border: OutlineInputBorder()),
                            onChanged: (v) => med.name = v,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                                hintText: 'Dosage',
                                isDense: true,
                                border: OutlineInputBorder()),
                            onChanged: (v) => med.dosage = v,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                                hintText: 'Frequency',
                                isDense: true,
                                border: OutlineInputBorder()),
                            onChanged: (v) => med.frequency = v,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                                hintText: 'Duration',
                                isDense: true,
                                border: OutlineInputBorder()),
                            onChanged: (v) => med.duration = v,
                          ),
                        ),
                        if (_medicines.length > 1)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _medicines.removeAt(i)),
                          ),
                      ],
                    ),
                  );
                }),
                TextButton(
                  onPressed: () => setState(() => _medicines.add(_EmptyMed())),
                  child: const Text('+ Add Medicine'),
                ),
                const SizedBox(height: 10),
                const Text('Instructions',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                TextField(
                  controller: _instructionsCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Diet, rest, special instructions…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Follow-up Date',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _followUpDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(_followUpDate == null
                        ? 'Select date'
                        : DateFormat('d MMM y').format(_followUpDate!)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: widget.onClose, child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      child: Text(_saving ? 'Saving…' : 'Issue Prescription'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =====================================================================
/// Main VideoCall screen
/// =====================================================================

class VideoCallScreen extends StatefulWidget {
  final String appointmentId;
  final Map<String, dynamic>? initialAppointment;
  final Map<String, dynamic>? initialDoctor;
  final Map<String, dynamic>? initialPatient;
  final String initialRole;

  const VideoCallScreen({
    super.key,
    required this.appointmentId,
    this.initialAppointment,
    this.initialDoctor,
    this.initialPatient,
    this.initialRole = '',
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with WidgetsBindingObserver {
  // ── Appointment ──────────────────────────────────────────────────
  Map<String, dynamic>? _appt;
  bool _apptLoading = true;
  String _apptError = '';
  String _activeRole = '';
  bool _callSessionStarted = false;

  Map<String, dynamic>? get _doctor {
    if (widget.initialDoctor?.isNotEmpty == true) return widget.initialDoctor;
    final value = _appt?['doctorId'];
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  Map<String, dynamic>? get _user {
    if (widget.initialPatient?.isNotEmpty == true) return widget.initialPatient;
    final value = _appt?['patientId'];
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  String get _doctorId => (_doctor?['_id'] ?? _doctor?['id'] ?? '').toString();
  String get _userId => (_user?['_id'] ?? '').toString();

  String get _apptDoctorId {
    final d = _appt?['doctorId'];
    if (d is Map) return (d['_id'] ?? '').toString();
    return (d ?? '').toString();
  }

  String get _apptPatientId {
    final p = _appt?['patientId'];
    if (p is Map) return (p['_id'] ?? '').toString();
    return (p ?? '').toString();
  }

  bool get _isDoctor {
    if (_activeRole.isNotEmpty) return _activeRole == 'doctor';
    if (_doctorId.isNotEmpty &&
        _apptDoctorId.isNotEmpty &&
        _doctorId == _apptDoctorId) return true;
    if (_userId.isNotEmpty &&
        _apptPatientId.isNotEmpty &&
        _userId == _apptPatientId) return false;
    return _doctor != null && _user == null;
  }

  Map<String, String> get _currentUser {
    if (_isDoctor) {
      return {
        'id': _doctorId.isEmpty ? 'doctor' : _doctorId,
        'name': (_doctor?['name'] ?? 'Doctor').toString(),
      };
    }
    return {
      'id': _userId.isEmpty ? 'user' : _userId,
      'name': (_user?['name'] ?? 'Patient').toString(),
    };
  }

  // ── Renderers (equivalent of the two <video> elements) ────────────
  final RTCVideoRenderer _mainRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _pipRenderer = RTCVideoRenderer();

  // ── Streams / connection ────────────────────────────────────────
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _screenStream;
  RTCPeerConnection? _pc;

  bool _inCallFlag = false;
  bool _isReadyFlag = false;
  bool _chatOpenFlag = false;
  bool _completedFlag = false;
  bool _isSwappedFlag = false;
  Timer? _callTimer;
  Timer? _heartbeatTimer;

  // ── Call state ───────────────────────────────────────────────────
  bool _isReady = false;
  bool _peerJoined = false;
  bool _inCall = false;
  bool _isRemoteConnected = false;
  String _connectionState = 'idle';
  int _callDuration = 0;
  bool _isMuted = false;
  bool _isCamOff = false;
  bool _isScreenSharing = false;
  bool _isSwapped = false;
  bool _isSelfViewMinimized = false;
  bool _isFullscreen = false;
  bool _camError = false;
  String _camErrorReason = '';
  bool _completing = false;
  bool _peerLeft = false;
  bool _endCallConfirm = false;
  bool _leaveConfirm = false;
  String _inlineError = '';
  String? _pendingLeaveRoute;

  // ── Chat state ───────────────────────────────────────────────────
  bool _chatOpen = false;
  final List<ChatMessage> _messages = [];
  final TextEditingController _chatInputCtrl = TextEditingController();
  int _unreadCount = 0;
  bool _uploadingFile = false;
  final ScrollController _chatScrollCtrl = ScrollController();

  // ── PiP drag ─────────────────────────────────────────────────────
  Offset? _pipPos;

  // ── Completion + prescription notifications ────────────────────
  bool _showCompletedOverlay = false;
  Map<String, dynamic>? _prescriptionNotif;
  bool _showRxModal = false;
  bool _rxSavedToast = false;

  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _appt = widget.initialAppointment;
    _activeRole = widget.initialRole;
    _apptLoading = widget.initialAppointment == null;
    WidgetsBinding.instance.addObserver(this);
    _mainRenderer.initialize();
    _pipRenderer.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_appt != null) _afterApptLoaded();
      _fetchAppointment();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _performCleanup(false);
    _mainRenderer.dispose();
    _pipRenderer.dispose();
    _chatInputCtrl.dispose();
    _chatScrollCtrl.dispose();
    _callTimer?.cancel();
    _heartbeatTimer?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }

  // Mirrors the "tab close / reload -> end call automatically" effect:
  // on mobile the closest analogue is the app being fully detached.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _performCleanup(true);
    }
  }

  // -------------------------------------------------------------------
  // Fetch appointment (role-aware, mirrors the dual-endpoint fallback)
  // -------------------------------------------------------------------
  Future<void> _fetchAppointment() async {
    setState(() {
      _apptLoading = _appt == null;
      _apptError = '';
      if (widget.initialRole.isEmpty) _activeRole = '';
    });

    Object? lastError;

    if (_activeRole == 'user' || _user != null) {
      try {
        final res = await ApiService.instance
            .get('/api/appointments/patient/${widget.appointmentId}');
        final data = res is String ? jsonDecode(res) : res;
        if (!mounted) return;
        setState(() {
          _appt = Map<String, dynamic>.from(data);
          _activeRole = 'user';
          _apptLoading = false;
        });
        _afterApptLoaded();
        return;
      } catch (err) {
        lastError = err;
      }
    }

    if (_activeRole == 'doctor' || _doctor != null) {
      try {
        final res = await ApiService.instance
            .get('/api/appointments/doctor/${widget.appointmentId}');
        final data = res is String ? jsonDecode(res) : res;
        if (!mounted) return;
        setState(() {
          _appt = Map<String, dynamic>.from(data);
          _activeRole = 'doctor';
          _apptLoading = false;
        });
        _afterApptLoaded();
        return;
      } catch (err) {
        lastError = err;
      }
    }

    if (!mounted) return;
    setState(() {
      _apptError = (_user == null && _doctor == null)
          ? 'Please login to access this appointment.'
          : (lastError?.toString() ?? 'Could not load appointment.');
      _apptLoading = false;
    });
  }

  void _afterApptLoaded() {
    if (_appt?['status'] == 'confirmed' && !_callSessionStarted) {
      _callSessionStarted = true;
      _startCallSession();
    }
  }

  // -------------------------------------------------------------------
  // Cleanup: stop tracks + notify peers + optional "complete" API call
  // -------------------------------------------------------------------
  void _performCleanup(bool markComplete) {
    if (_completedFlag) return;
    _completedFlag = true;

    _callTimer?.cancel();
    SocketService.instance
        .emit('leave-appointment-room', {'appointmentId': widget.appointmentId});

    _localStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.getTracks().forEach((t) => t.stop());
    _pc?.close();

    if (markComplete && _isDoctor) {
      ApiService.instance
          .put('/api/appointments/${widget.appointmentId}/complete', {})
          .catchError((_) => null);
    }
  }

  // -------------------------------------------------------------------
  // WebRTC + Socket setup (mirrors the big React useEffect)
  // -------------------------------------------------------------------
  Future<void> _startCallSession() async {
    _completedFlag = false;
    final completer = Completer<bool>();

    final pc = await createPeerConnection(kStunServers);
    _pc = pc;

    final remoteStream = await createLocalMediaStream('remote');
    _remoteStream = remoteStream;
    _mainRenderer.srcObject = remoteStream;

    // ── Get local media (with graceful fallbacks, same order as React) ──
    () async {
      MediaStream? stream;
      try {
        try {
          stream = await navigator.mediaDevices.getUserMedia(kMediaConstraints);
        } catch (_) {
          try {
            stream = await navigator.mediaDevices
                .getUserMedia({'audio': true, 'video': true});
          } catch (_) {
            stream = await navigator.mediaDevices
                .getUserMedia({'audio': true, 'video': false});
          }
        }

        _localStream = stream;
        _pipRenderer.srcObject = stream;

        for (final track in stream.getTracks()) {
          final sender = await pc.addTrack(track, stream);
          await tuneSenderQuality(
            sender,
            maxBitrate: track.kind == 'video'
                ? BitrateProfile.cameraVideo
                : BitrateProfile.voiceAudio,
            maxFramerate: track.kind == 'video' ? 30 : null,
            maintainResolution: track.kind == 'video',
          );
        }

        if (mounted) {
          setState(() {
            _isReady = true;
            _camError = false;
          });
        }
        _isReadyFlag = true;
        if (!completer.isCompleted) completer.complete(true);
      } catch (err) {
        if (mounted) {
          setState(() {
            _camError = true;
            _camErrorReason = mediaErrorMessage(err);
            _isReady = true; // proceed audio-only / no-media, like React
          });
        }
        _isReadyFlag = true;
        if (!completer.isCompleted) completer.complete(false);
      }
    }();

    pc.onTrack = (RTCTrackEvent event) {
      for (final track in event.streams.isNotEmpty
          ? event.streams.first.getTracks()
          : <MediaStreamTrack>[]) {
        remoteStream.addTrack(track);
      }
      if (mounted) {
        _assignStreams(_isSwappedFlag);
        setState(() {
          _isRemoteConnected = true;
          _peerLeft = false;
        });
      }
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      SocketService.instance.emit('ice-candidate', {
        'appointmentId': widget.appointmentId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _connectionState = 'connected');
        setState(() => _isRemoteConnected = true);
        if (!_inCallFlag) {
          _markInCall();
        }
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
        setState(() => _connectionState = 'connecting');
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => _connectionState = 'disconnected');
        setState(() => _isRemoteConnected = false);
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (!mounted) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        setState(() => _connectionState = 'connected');
        setState(() => _isRemoteConnected = true);
        if (!_inCallFlag) {
          _markInCall();
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        if (!_inCallFlag) setState(() => _connectionState = 'connecting');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        setState(() => _connectionState = 'disconnected');
        setState(() => _isRemoteConnected = false);
      }
    };

    // ── Socket handlers ────────────────────────────────────────────
    Future<void> handleOffer(dynamic data) async {
      final offer = data['offer'];
      if (offer == null || !mounted) return;
      try {
        setState(() => _connectionState = 'connecting');
        await pc.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']),
        );
        await completer.future;
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        SocketService.instance.emit('video-answer', {
          'appointmentId': widget.appointmentId,
          'answer': {'sdp': answer.sdp, 'type': answer.type},
        });
        if (!_inCallFlag) {
          _markInCall();
        }
      } catch (err) {
        debugPrint('Offer error: $err');
      }
    }

    Future<void> handleAnswer(dynamic data) async {
      final answer = data['answer'];
      if (answer == null || !mounted) return;
      try {
        await pc.setRemoteDescription(
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
        if (!_inCallFlag) {
          _markInCall();
        }
      } catch (err) {
        debugPrint('Answer error: $err');
      }
    }

    Future<void> handleIce(dynamic data) async {
      final candidate = data['candidate'];
      if (candidate == null || !mounted) return;
      try {
        await pc.addCandidate(RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        ));
      } catch (_) {}
    }

    void handlePeerJoined(dynamic _) {
      if (mounted) {
        setState(() {
          _peerJoined = true;
          _peerLeft = false;
        });
      }
    }

    void handleParticipantLeft(dynamic _) {
      if (mounted) {
        setState(() {
          _isRemoteConnected = false;
          _connectionState = 'disconnected';
          _peerJoined = false;
          _peerLeft = true;
        });
      }
    }

    void handleChatMessage(dynamic data) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(data)));
        if (!_chatOpenFlag) _unreadCount += 1;
      });
      _scrollChatToEnd();
    }

    void handleChatHistory(dynamic data) {
      if (!mounted) return;
      final payload = Map<String, dynamic>.from(data);
      if (payload['appointmentId'] == widget.appointmentId) {
        final list = (payload['messages'] as List<dynamic>? ?? []);
        setState(() {
          _messages
            ..clear()
            ..addAll(list.map(
                (m) => ChatMessage.fromJson(Map<String, dynamic>.from(m))));
        });
        _scrollChatToEnd();
      }
    }

    void handleApptUpdated(dynamic data) {
      if (!mounted) return;
      final status = Map<String, dynamic>.from(data)['status'];
      if (['complete', 'completed'].contains(status) && !_isDoctor) {
        setState(() => _showCompletedOverlay = true);
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) Navigator.pushReplacementNamed(context, '/user/dashboard');
        });
      }
    }

    void handleNewPrescription(dynamic data) {
      if (!mounted || _isDoctor) return;
      setState(() =>
          _prescriptionNotif = {'diagnosis': Map<String, dynamic>.from(data)['diagnosis']});
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) setState(() => _prescriptionNotif = null);
      });
    }

    void handleRoomDenied(dynamic data) {
      if (!mounted) return;
      final msg = data is Map ? data['msg'] : null;
      setState(() => _apptError = msg ?? 'Access to this call room was denied.');
    }

    final socket = SocketService.instance;
    socket.on('video-offer', handleOffer);
    socket.on('video-answer', handleAnswer);
    socket.on('ice-candidate', handleIce);
    socket.on('peer-joined', handlePeerJoined);
    socket.on('participant-left', handleParticipantLeft);
    socket.on('appointment-message', handleChatMessage);
    socket.on('appointment-chat-history', handleChatHistory);
    socket.on('appointment-updated', handleApptUpdated);
    socket.on('new-prescription', handleNewPrescription);
    socket.on('room-access-denied', handleRoomDenied);

    final activeUserId = _isDoctor ? _doctorId : _userId;
    void joinRoom() {
      if (activeUserId.isNotEmpty) {
        socket.emit('user-online', {
          'userId': activeUserId,
          'role': _isDoctor ? 'doctor' : 'user',
        });
      }
      socket.emit('join-appointment-room', {'appointmentId': widget.appointmentId});
    }

    if (socket.connected) {
      joinRoom();
    } else {
      socket.once('connect', (_) => joinRoom());
      socket.connect();
    }

    // Auto-start: patient sends the offer once both sides are ready.
    _watchAutoStart(pc);

    // Call timer.
    _callTimer?.cancel();
    // (Started/stopped reactively in _setInCall below.)

    // Session keep-alive heartbeat while in call.
    _heartbeatTimer?.cancel();
  }

  void _watchAutoStart(RTCPeerConnection pc) {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_peerJoined && _isReady && !_inCall && !_isDoctor && !_inCallFlag) {
        timer.cancel();
        try {
          setState(() => _connectionState = 'connecting');
          final offer = await pc.createOffer(
              {'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
          await pc.setLocalDescription(offer);
          SocketService.instance.emit('video-offer', {
            'appointmentId': widget.appointmentId,
            'offer': {'sdp': offer.sdp, 'type': offer.type},
          });
          _markInCall();
        } catch (err) {
          debugPrint('Auto-start error: $err');
        }
      }
    });
  }

  // Marks the call as active exactly once and starts the call timer +
  // session-keepalive heartbeat, mirroring the two React effects keyed
  // on `inCall`. Safe to call multiple times (e.g. from both the offer
  // and connection-state handlers, same as the original `inCallRef` guard).
  void _markInCall() {
    if (_inCallFlag) return;
    _inCallFlag = true;
    if (mounted) setState(() => _inCall = true);

    _callTimer?.cancel();
    _callTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => mounted ? setState(() => _callDuration++) : null);

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      ApiService.instance.post('/api/auth/refresh', {}).catchError((_) => null);
    });
  }

  void _assignStreams(bool swapped) {
    _mainRenderer.srcObject = swapped ? _localStream : _remoteStream;
    _pipRenderer.srcObject = swapped ? _remoteStream : _localStream;
  }

  void _scrollChatToEnd() {
    if (!_chatOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // -------------------------------------------------------------------
  // Controls
  // -------------------------------------------------------------------
  void _toggleMute() {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !t.enabled);
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleCamera() {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !t.enabled);
    setState(() => _isCamOff = !_isCamOff);
  }

  Future<void> _toggleScreenShare() async {
    final pc = _pc;
    if (pc == null) return;

    if (_isScreenSharing) {
      _screenStream?.getTracks().forEach((t) => t.stop());
      _screenStream = null;
      final camTrack = _localStream?.getVideoTracks().isNotEmpty == true
          ? _localStream!.getVideoTracks().first
          : null;
      if (camTrack != null) {
        final senders = await pc.getSenders();
        final sender =
            senders.where((s) => s.track?.kind == 'video').firstOrNull;
        if (sender != null) {
          await sender.replaceTrack(camTrack);
          await tuneSenderQuality(sender,
              maxBitrate: BitrateProfile.cameraVideo,
              maxFramerate: 30,
              maintainResolution: true);
        }
      }
      _assignStreams(_isSwappedFlag);
      setState(() => _isScreenSharing = false);
    } else {
      try {
        final screen = await navigator.mediaDevices
            .getDisplayMedia({'video': true, 'audio': false});
        _screenStream = screen;
        final screenTrack = screen.getVideoTracks().first;
        final senders = await pc.getSenders();
        final sender =
            senders.where((s) => s.track?.kind == 'video').firstOrNull;
        if (sender != null) {
          await sender.replaceTrack(screenTrack);
          await tuneSenderQuality(sender,
              maxBitrate: BitrateProfile.screenShareVideo,
              maxFramerate: 30,
              maintainResolution: true);
        }
        _pipRenderer.srcObject = screen;
        screenTrack.onEnded = () => _toggleScreenShare();
        setState(() => _isScreenSharing = true);
      } catch (err) {
        if (!err.toString().contains('NotAllowedError')) {
          setState(() {
            _inlineError =
                'Screen sharing is not supported on this device/build.';
          });
          Future.delayed(const Duration(seconds: 4),
              () => mounted ? setState(() => _inlineError = '') : null);
        }
      }
    }
  }

  void _toggleSwap() {
    setState(() {
      _isSwapped = !_isSwapped;
      _isSwappedFlag = _isSwapped;
      _assignStreams(_isSwapped);
    });
  }

  void _toggleSelfView() =>
      setState(() => _isSelfViewMinimized = !_isSelfViewMinimized);

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      setState(() => _isFullscreen = false);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      setState(() => _isFullscreen = true);
    }
  }

  Future<void> _endCall() async {
    if (_completing) return;
    setState(() {
      _endCallConfirm = false;
      _completing = true;
    });
    try {
      if (_isDoctor && _appt?['status'] == 'confirmed') {
        await ApiService.instance
            .put('/api/appointments/${widget.appointmentId}/complete', {});
      }
      _performCleanup(false);
      if (!mounted) return;
      Navigator.pushReplacementNamed(
          context, _isDoctor ? '/doctor-dashboard/patients' : '/user/dashboard');
    } catch (err) {
      setState(() {
        _completing = false;
        _inlineError = 'Failed to end call. Please try again.';
      });
      Future.delayed(const Duration(seconds: 5),
          () => mounted ? setState(() => _inlineError = '') : null);
    }
  }

  void _handleRxSaved() {
    setState(() {
      _showRxModal = false;
      _rxSavedToast = true;
    });
    Future.delayed(const Duration(seconds: 4),
        () => mounted ? setState(() => _rxSavedToast = false) : null);
  }

  // -------------------------------------------------------------------
  // Chat
  // -------------------------------------------------------------------
  void _toggleChat() {
    setState(() {
      if (!_chatOpen) _unreadCount = 0;
      _chatOpen = !_chatOpen;
      _chatOpenFlag = _chatOpen;
    });
    _scrollChatToEnd();
  }

  void _sendMessage() {
    final text = _chatInputCtrl.text.trim();
    if (text.isEmpty) return;
    SocketService.instance.emit('appointment-message', {
      'appointmentId': widget.appointmentId,
      'senderId': _currentUser['id'],
      'senderName': _currentUser['name'],
      'text': text,
    });
    _chatInputCtrl.clear();
  }

  Future<void> _handleAttachFile() async {
    final result = await pickFileForUpload();
    if (result == null) return;
    if (result.sizeBytes > 10 * 1024 * 1024) {
      setState(() => _inlineError = 'File too large. Max 10 MB.');
      Future.delayed(const Duration(seconds: 4),
          () => mounted ? setState(() => _inlineError = '') : null);
      return;
    }
    setState(() => _uploadingFile = true);
    try {
      final uploaded = await uploadFileDirectToS3(result);
      SocketService.instance.emit('appointment-message', {
        'appointmentId': widget.appointmentId,
        'senderId': _currentUser['id'],
        'senderName': _currentUser['name'],
        'text': '',
        'fileUrl': uploaded.key,
        'fileName': uploaded.name,
        'fileType': uploaded.type,
      });
    } catch (err) {
      setState(() => _inlineError = 'File upload failed.');
      Future.delayed(const Duration(seconds: 4),
          () => mounted ? setState(() => _inlineError = '') : null);
    } finally {
      if (mounted) setState(() => _uploadingFile = false);
    }
  }

  // -------------------------------------------------------------------
  // Other-party info
  // -------------------------------------------------------------------
  Map<String, dynamic>? get _otherParty {
    if (_appt == null) return null;
    if (_isDoctor) {
      final patient = _appt!['patientId'];
      final name = (patient is Map ? patient['name'] : null) ?? 'Unknown Patient';
      return {
        'label': 'Patient',
        'name': name,
        'sub': _appt!['problem'] ?? '',
        'initial': (name is String && name.isNotEmpty)
            ? name.substring(0, 1).toUpperCase()
            : 'P',
      };
    }
    final doc = _appt!['doctorId'];
    final docName = (doc is Map ? doc['name'] : null) ?? 'Unknown';
    return {
      'label': 'Doctor',
      'name': 'Dr. $docName',
      'sub': (doc is Map ? doc['email'] : null) ?? '',
      'initial':
          (docName is String && docName.isNotEmpty) ? docName.substring(0, 1).toUpperCase() : 'D',
    };
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_apptLoading) return _gateScreen(spinner: true, message: 'Loading appointment…');

    if (_apptError.isNotEmpty) {
      return _gateScreen(
        icon: Icons.warning_amber_rounded,
        title: 'Access Denied',
        message: _apptError,
      );
    }

    if (_appt?['status'] == 'pending') {
      return _gateScreen(
        icon: Icons.access_time,
        title: 'Appointment Pending',
        message: _isDoctor
            ? "Confirm this appointment from your dashboard before starting the video call."
            : "Your appointment is awaiting the doctor's confirmation.",
      );
    }

    final status = _appt?['status'];
    if (['complete', 'completed'].contains(status) || status == 'cancelled') {
      final isComplete = ['complete', 'completed'].contains(status);
      return _gateScreen(
        icon: isComplete ? Icons.check_circle_outline : Icons.close,
        title: 'Appointment ${isComplete ? "Complete" : "Cancelled"}',
        message: 'This appointment is no longer active.',
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_inCall) {
          Navigator.of(context).maybePop();
          return;
        }
        _pendingLeaveRoute = _isDoctor ? '/doctor-dashboard' : '/user/dashboard';
        setState(() => _leaveConfirm = true);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1626),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(),
                  if (_inlineError.isNotEmpty) _inlineErrorBanner(),
                  Expanded(child: _buildBody()),
                  _buildControlBar(),
                  if (_camError) _camErrorBanner(),
                ],
              ),
              if (_endCallConfirm) _confirmOverlay(
                title: _isDoctor ? 'End Consultation?' : 'Leave Call?',
                message: _isDoctor
                    ? 'This will end the call and mark the consultation as completed.'
                    : 'You will leave the video call. The doctor will be notified.',
                confirmLabel: _isDoctor ? 'End & Complete' : 'Leave Call',
                onCancel: () => setState(() => _endCallConfirm = false),
                onConfirm: _endCall,
              ),
              if (_leaveConfirm) _confirmOverlay(
                title: 'Leave Consultation?',
                message: 'Leaving will end your consultation session. Are you sure?',
                confirmLabel: 'Leave',
                onCancel: () => setState(() => _leaveConfirm = false),
                onConfirm: () {
                  setState(() => _leaveConfirm = false);
                  _performCleanup(true);
                  Navigator.pushReplacementNamed(
                      context, _pendingLeaveRoute ?? '/user/dashboard');
                },
              ),
              if (_showCompletedOverlay && !_isDoctor) _completedOverlay(),
              if (_showRxModal && _isDoctor && _appt != null)
                InCallPrescriptionModal(
                  appt: _appt!,
                  onClose: () => setState(() => _showRxModal = false),
                  onSaved: _handleRxSaved,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gateScreen({bool spinner = false, IconData? icon, String? title, String? message}) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spinner) const CircularProgressIndicator(),
              if (icon != null) Icon(icon, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              if (title != null)
                Text(title,
                    style:
                        const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message ?? '', textAlign: TextAlign.center),
              if (!spinner) ...[
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go Back'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF0D1F35),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: Colors.tealAccent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          const Text('Humancare Connect',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          if (_otherParty != null)
            Expanded(
              child: Text(
                '${_otherParty!['label']}: ${_otherParty!['name']}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (_inCall && _isDoctor)
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text(fmtDuration(_callDuration),
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _inlineErrorBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF2F2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_inlineError,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _camErrorBanner() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _camErrorReason.isNotEmpty
                  ? _camErrorReason
                  : 'Camera or microphone access denied. Check app permissions and reload.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () async {
              setState(() => _camError = false);
              try {
                final stream = await navigator.mediaDevices
                    .getUserMedia({'audio': true, 'video': true});
                _localStream = stream;
                _pipRenderer.srcObject = stream;
                for (final track in stream.getTracks()) {
                  final senders = await _pc?.getSenders() ?? [];
                  final sender =
                      senders.where((s) => s.track?.kind == track.kind).firstOrNull;
                  if (sender != null) {
                    await sender.replaceTrack(track);
                  } else {
                    await _pc?.addTrack(track, stream);
                  }
                }
                setState(() {
                  _isReady = true;
                  _camErrorReason = '';
                });
              } catch (e) {
                setState(() {
                  _camError = true;
                  _camErrorReason = mediaErrorMessage(e);
                });
              }
            },
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _confirmOverlay({
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onCancel,
    required VoidCallback onConfirm,
  }) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onCancel,
        child: Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1F35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call_end, color: Colors.redAccent, size: 32),
                  const SizedBox(height: 12),
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(onPressed: onCancel, child: const Text('Stay')),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: onConfirm,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        child: Text(confirmLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _completedOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 40),
              const SizedBox(height: 12),
              const Text('Consultation Completed',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Your doctor has marked this session as complete.'),
              const SizedBox(height: 4),
              Text('Redirecting to your dashboard…',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      children: [
        Expanded(child: _buildStage()),
        if (_chatOpen)
          SizedBox(width: 320, child: _buildChatPanel()),
      ],
    );
  }

  Widget _buildStage() {
    return Stack(
      children: [
        Positioned.fill(
          child: RTCVideoView(
            _mainRenderer,
            mirror: _isSwapped,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),

        if (!_isRemoteConnected && !_isSwapped)
          Positioned.fill(
            child: Container(
              color: const Color(0xCC0B1626),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _peerJoined
                        ? 'Establishing secure connection…'
                        : 'Waiting for ${_isDoctor ? "patient" : "doctor"}…',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _peerJoined
                        ? 'Both participants are ready. Video starting soon.'
                        : 'Share the appointment link with the other person to begin.',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

        if (_peerLeft)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.call_end, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text('${_isDoctor ? "Patient" : "Doctor"} has left the call.',
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),

        if (!_isSelfViewMinimized) _buildPip() else _buildRestorePipButton(),

        if (_peerJoined && !_isRemoteConnected)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_isDoctor ? "Patient" : "Doctor"} joined · connecting…',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPip() {
    final size = MediaQuery.of(context).size;
    final pos = _pipPos ?? Offset(size.width - 140, 90);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final newX = (pos.dx + details.delta.dx)
                .clamp(8.0, size.width - 128 - 8.0);
            final newY = (pos.dy + details.delta.dy)
                .clamp(8.0, size.height - 172 - 8.0);
            _pipPos = Offset(newX, newY);
          });
        },
        child: Container(
          width: 120,
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
            color: Colors.black,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: RTCVideoView(
                  _pipRenderer,
                  mirror: !_isSwapped,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
              if (_isCamOff && !_isSwapped)
                Positioned.fill(
                  child: Container(
                    color: Colors.black87,
                    alignment: Alignment.center,
                    child: const Icon(Icons.videocam_off, color: Colors.white54),
                  ),
                ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Text(
                  _isSwapped
                      ? (_otherParty?['label'] ?? 'Remote')
                      : 'You${_isDoctor ? " (Doctor)" : ""}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Row(
                  children: [
                    _pipIconButton(Icons.close_fullscreen, _toggleSelfView),
                    const SizedBox(width: 4),
                    _pipIconButton(Icons.swap_horiz, _toggleSwap),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pipIconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }

  Widget _buildRestorePipButton() {
    return Positioned(
      top: 16,
      right: 16,
      child: OutlinedButton.icon(
        onPressed: _toggleSelfView,
        icon: const Icon(Icons.open_in_full, size: 16),
        label: const Text('Self View'),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
      ),
    );
  }

  Widget _buildChatPanel() {
    return Container(
      color: const Color(0xFF0D1F35),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('In-call Chat',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: _toggleChat,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline, color: Colors.white24, size: 32),
                        const SizedBox(height: 8),
                        Text('No messages yet.', style: TextStyle(color: Colors.grey.shade500)),
                        Text('Share notes or files here during the call.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = _messages[i];
                      final mine = msg.senderId == _currentUser['id'];
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: const BoxConstraints(maxWidth: 220),
                          decoration: BoxDecoration(
                            color: mine ? Colors.teal.shade600 : Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!mine)
                                Text(msg.senderName,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11)),
                              if (msg.fileUrl != null)
                                Text('📎 ${msg.fileName ?? "Attachment"}',
                                    style: const TextStyle(color: Colors.white))
                              else
                                Text(msg.text, style: const TextStyle(color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(fmtTime(msg.createdAt),
                                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  onPressed: _uploadingFile ? null : _handleAttachFile,
                  icon: _uploadingFile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file, color: Colors.white70),
                ),
                Expanded(
                  child: TextField(
                    controller: _chatInputCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      hintStyle: TextStyle(color: Colors.white38),
                      counterText: '',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.tealAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      color: const Color(0xFF0D1F35),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ctrlButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: _isMuted ? 'Unmute' : 'Mute',
              danger: _isMuted,
              onTap: _isReady ? _toggleMute : null,
            ),
            _ctrlButton(
              icon: _isCamOff ? Icons.videocam_off : Icons.videocam,
              label: _isCamOff ? 'Cam On' : 'Cam Off',
              danger: _isCamOff,
              onTap: _isReady ? _toggleCamera : null,
            ),
            _ctrlButton(
              icon: Icons.screen_share,
              label: _isScreenSharing ? 'Stop' : 'Share',
              active: _isScreenSharing,
              onTap: _isReady ? _toggleScreenShare : null,
            ),
            if (_inCall)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.redAccent, size: 8),
                    SizedBox(width: 6),
                    Text('Live', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                ),
              ),
            _ctrlButton(
              icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              label: _isFullscreen ? 'Exit' : 'Full',
              active: _isFullscreen,
              onTap: _toggleFullscreen,
            ),
            _ctrlButton(
              icon: _isSelfViewMinimized ? Icons.open_in_full : Icons.close_fullscreen,
              label: _isSelfViewMinimized ? 'Show Me' : 'Hide Me',
              active: _isSelfViewMinimized,
              onTap: _toggleSelfView,
            ),
            _ctrlButton(
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              active: _chatOpen,
              badge: (_unreadCount > 0 && !_chatOpen) ? _unreadCount : null,
              onTap: _toggleChat,
            ),
            if (_isDoctor)
              _ctrlButton(
                icon: Icons.medication_outlined,
                label: 'Rx',
                onTap: () => setState(() => _showRxModal = true),
              ),
            _ctrlButton(
              icon: _completing ? Icons.refresh : Icons.call_end,
              label: _completing ? 'Ending...' : 'End Call',
              danger: true,
              onTap: _completing ? null : () => setState(() => _endCallConfirm = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrlButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool danger = false,
    bool active = false,
    int? badge,
  }) {
    final color = danger
        ? Colors.redAccent
        : active
            ? Colors.tealAccent
            : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: color, size: 22),
                    if (badge != null)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.redAccent, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            badge > 9 ? '9+' : '$badge',
                            style: const TextStyle(color: Colors.white, fontSize: 9),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: color, fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
