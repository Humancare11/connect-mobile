// video_call_screen.dart
//
// Thin presentation layer over VideoCallController — a close visual port of
// frontend/src/pages/VideoCall.jsx + videocall.css (specifically the "2026
// Video Call Layout Refresh" cascade layer, which is what actually renders
// on the web today: combined top meta bar, dark-navy control-bar buttons,
// teal/red/indigo/green state colors, Sora/DM Sans typography). Owns no
// signaling/WebRTC logic itself — see video_call_controller.dart.
//
// Screen sharing is ported (see VideoCallController.startScreenShare /
// stopScreenShare) — Android needs a foreground service declared in
// AndroidManifest.xml (MediaProjection requires one); iOS needs none, since
// flutter_webrtc's getDisplayMedia routes through in-process RPScreenRecorder
// for in-app sharing.
//
// Deliberately NOT ported from the web UI: the doctor-authored
// prescription/notes UI (this app has no doctor login flow — see the
// controller's class doc comment).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../controllers/video_call_controller.dart';
import '../utils/direct_upload.dart';

String _fmtTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  return DateFormat('h:mm a').format(parsed.toLocal());
}

String _fmtDuration(int secs) {
  final h = secs ~/ 3600;
  final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (secs % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Palette lifted directly from videocall.css (values noted inline) so the
/// mobile screen reads as the same product, not a reinterpretation.
class _C {
  _C._();

  static const pageBgTop = Color(0xFF000000);
  static const pageBgBottom = Color(0xFF020814);

  static const gateBgTop = Color(0xFF0E2040);
  static const gateBgBottom = Color(0xFF06101A);
  static const gateIcon = Color(0xFFE8F4FF);
  static const gateTitle = Color(0xFFF0F8FF);
  static const gateBody = Color(0xFF5A7A96);
  static const gateBtnBg = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const gateBtnBorder = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
  static const teal = Color(0xFF19C9A3);

  static const ctrlbarBorder = Color(0x2E5B90DC); // rgba(91,144,220,.18)

  static const stageBg = Color(0xFF03101F);
  static const stageBorder = Color(0x2E5F96DC); // rgba(95,150,220,.18)

  static const logoGradStart = Color(0xFF4DA3FF);
  static const logoGradEnd = Color(0xFF006EFF);
  static const logoText = Color(0xFFF4F8FF);
  static const partyLabel = Color(0xFF7CA4D6);
  static const partyName = Color(0xFFFFFFFF);

  static const timerBg = Color(0xFF01164A);
  static const timerBorder = Color(0x336CA7FF); // rgba(108,167,255,.2)
  static const timerText = Color(0xFFDCECFF);

  static const waitingBgTop = Color(0xFF0D2038);
  static const waitingBgBottom = Color(0xFF040C15);
  static const waitingRing = Color(0x3319C9A3); // rgba(25,201,163,.2)
  static const waitingAvatarBg = Color(0x1419C9A3); // rgba(25,201,163,.08)
  static const waitingAvatarBorder = Color(0x2619C9A3); // rgba(25,201,163,.15)
  static const waitingTitle = Color(0xFFE8F4FF);
  static const waitingSub = Color(0xFF3A5A74);

  static const peerLeftBg = Color(0x1FEF4444); // rgba(239,68,68,.12)
  static const peerLeftBorder = Color(0x4DEF4444); // rgba(239,68,68,.3)
  static const peerLeftText = Color(0xFFFCA5A5);

  static const pipBg = Color(0xFF081422);
  static const pipBorder = Color(0x596294DB); // rgba(98,156,219,.35)
  static const pipLabel = Color(0xBFFFFFFF); // rgba(255,255,255,.75)
  static const pipSwapBg = Color(0xE619C9A3); // rgba(25,201,163,.9)
  static const pipSwapIcon = Color(0xFF08201A);

  static const chatBg = Color(0xFF07192D);
  static const chatBorder = Color(0x337AADE6); // rgba(122,173,230,.2)
  static const chatTitle = Color(0xFFE8F4FF);
  static const chatCloseBg = Color(0x0DFFFFFF); // rgba(255,255,255,.05)
  static const chatCloseBorder = Color(0x14FFFFFF); // rgba(255,255,255,.08)
  static const chatCloseIcon = Color(0xFF5A7A96);
  static const chatEmpty = Color(0xFF3A5A74);
  static const msgMineBg = Color(0xFF19C9A3);
  static const msgMineText = Color(0xFF07201A);
  static const msgTheirsBg = Color(0x14FFFFFF); // rgba(255,255,255,.08)
  static const msgTheirsBorder = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const msgTheirsText = Color(0xFFC8E0F5);
  static const msgName = Color(0xFF5A7A96);
  static const msgTime = Color(0xFF3A5A74);
  static const chatInputBg = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const chatInputBorder = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  static const chatInputText = Color(0xFFE8F4FF);
  static const chatInputHint = Color(0xFF3A5A74);

  static const btnBg = Color(0xFF01164A);
  static const btnBorder = Color(0x248CB6E1); // rgba(140,182,225,.14)
  static const btnText = Color(0xFFA6C4E2);

  static const btnDangerBg = Color(0x21EF4444); // rgba(239,68,68,.13)
  static const btnDangerBorder = Color(0x4DEF4444); // rgba(239,68,68,.3)
  static const btnDangerText = Color(0xFFEF4444);

  static const btnActiveBg = Color(0x296366F1); // rgba(99,102,241,.16)
  static const btnActiveBorder = Color(0x736366F1); // rgba(99,102,241,.45)
  static const btnActiveText = Color(0xFFA5B4FC);

  static const btnChatOnBg = Color(0x1A19C9A3); // rgba(25,201,163,.1)
  static const btnChatOnBorder = Color(0x5919C9A3); // rgba(25,201,163,.35)

  static const btnEndBg = Color(0x1AEF4444); // rgba(239,68,68,.1)
  static const btnEndBorder = Color(0x4DEF4444); // rgba(239,68,68,.3)
  static const btnEndText = Color(0xFFEF4444);

  static const badgeBg = Color(0xFFEF4444);

  static const livePillBg = Color(0x1222C55E); // rgba(34,197,94,.07)
  static const livePillBorder = Color(0x3822C55E); // rgba(34,197,94,.22)
  static const livePillText = Color(0xFF22C55E);

  // Quality pill — same per-bucket colors as .hc-vc__quality-pill--{good,weak,poor}
  static const qualityGoodBg = Color(0x1222C55E); // rgba(34,197,94,.07)
  static const qualityGoodBorder = Color(0x3822C55E); // rgba(34,197,94,.22)
  static const qualityGoodText = Color(0xFF22C55E);
  static const qualityWeakBg = Color(0x1AEAB308); // rgba(234,179,8,.1)
  static const qualityWeakBorder = Color(0x4DEAB308); // rgba(234,179,8,.3)
  static const qualityWeakText = Color(0xFFEAB308);
  static const qualityPoorBg = Color(0x1AEF4444); // rgba(239,68,68,.1)
  static const qualityPoorBorder = Color(0x4DEF4444); // rgba(239,68,68,.3)
  static const qualityPoorText = Color(0xFFEF4444);

  static const modalBg = Color(0xFF0D1F35);
  static const modalBorder = Color(0x1AFFFFFF); // rgba(255,255,255,.1)
  static const modalTitle = Color(0xFFF1F5F9);
  static const modalBody = Color(0xFF94A3B8);
  static const modalStayBg = Color(0x12FFFFFF); // rgba(255,255,255,.07)
  static const modalStayBorder = Color(0x26FFFFFF); // rgba(255,255,255,.15)
  static const modalStayText = Color(0xFFE2E8F0);
  static const modalDangerBg = Color(0xFFEF4444);
  static const modalCompleteBg = Color(0xFF16A34A);

  static const completedOverlayBg = Color(0xE0040C15); // rgba(4,12,21,.88)
  static const completedCardTop = Color(0xFF0D2038);
  static const completedCardBottom = Color(0xFF081422);
  static const completedCardBorder = Color(0x4022C55E); // rgba(34,197,94,.25)
  static const completedIcon = Color(0xFFE8F4FF);
  static const completedTitle = Color(0xFFF0F8FF);
  static const completedBody = Color(0xFF7A9AB4);
  static const completedSub = Color(0xFF3A5A74);
  static const completedSpinner = Color(0xFF22C55E);

  static const toastBg = Color(0xFFFEF2F2);
  static const toastBorder = Color(0xFFFCA5A5);
  static const toastText = Color(0xFFDC2626);

  static const deviceCheckingBg = Color(0xFFEFF6FF);
  static const deviceCheckingBorder = Color(0xFF93C5FD);
  static const deviceCheckingText = Color(0xFF1D4ED8);

  static const camErrorBg = Color(0x1AEF4444); // rgba(239,68,68,.1)
  static const camErrorBorder = Color(0x4DEF4444); // rgba(239,68,68,.3)
  static const camErrorText = Color(0xFFFCA5A5);

  static const rxNotifBg = Color(0x24A855F7); // rgba(168,85,247,.14)
  static const rxNotifBorder = Color(0x66A855F7); // rgba(168,85,247,.4)
  static const rxNotifText = Color(0xFFDDD6FE);
}

TextStyle _sora({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) => GoogleFonts.sora(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

TextStyle _dmSans({
  required double size,
  FontWeight weight = FontWeight.normal,
  Color color = Colors.white,
  double? height,
}) => GoogleFonts.dmSans(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

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

class _VideoCallScreenState extends State<VideoCallScreen> with WidgetsBindingObserver {
  late final VideoCallController _controller;

  // Pure UI state — deliberately not in the controller (no signaling impact).
  bool _isSelfViewMinimized = false;
  bool _isFullscreen = false;
  bool _endCallConfirm = false;
  bool _leaveConfirm = false;
  Offset? _pipPos;

  final TextEditingController _chatInputCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = VideoCallController(
      appointmentId: widget.appointmentId,
      initialAppointment: widget.initialAppointment,
      initialDoctor: widget.initialDoctor,
      initialPatient: widget.initialPatient,
      initialRole: widget.initialRole,
      onCompletedByPeer: _navigateBack,
    );
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _chatInputCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  // Closest mobile analogue of the web's "tab close -> cleanup" handling.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Mirrors VideoCall.jsx's pageUnloadingRef: don't tell the peer we
      // left explicitly on a process kill — let the socket's natural
      // disconnect + the server's grace period handle a quick relaunch as
      // a resume instead of an abrupt "peer left".
      unawaited(_controller.performCleanup(emitLeave: false));
    } else if (state == AppLifecycleState.resumed) {
      _controller.handleAppResumed();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.chatOpen) _scrollChatToEnd();
  }

  void _scrollChatToEnd() {
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

  void _navigateBack() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  Future<void> _handleAttachFile() async {
    final result = await pickFileForUpload();
    if (result == null) return;
    await _controller.attachFile(result);
  }

  void _sendMessage() {
    final text = _chatInputCtrl.text;
    if (text.trim().isEmpty) return;
    _controller.sendMessage(text);
    _chatInputCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.apptLoading) {
      return _gateScreen(spinner: true, message: 'Loading appointment...');
    }

    if (_controller.apptError.isNotEmpty) {
      return _gateScreen(
        icon: Icons.warning_amber_rounded,
        title: 'Access Denied',
        message: _controller.apptError,
      );
    }

    final status = _controller.appt?['status'];
    if (!_controller.canJoinConsultation &&
        ['pending', 'requested', 'upcoming', 'assigned'].contains(status)) {
      return _gateScreen(
        icon: Icons.access_time,
        title: 'Appointment Pending',
        message: _controller.isDoctor
            ? 'Confirm this appointment from your dashboard before starting the video call.'
            : "Your appointment is awaiting the doctor's confirmation.",
      );
    }

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
        if (!_controller.inCall) {
          Navigator.of(context).maybePop();
          return;
        }
        setState(() => _leaveConfirm = true);
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.9),
              radius: 1.3,
              colors: [_C.pageBgTop, _C.pageBgTop, _C.pageBgBottom],
              stops: [0, 0.45, 1],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildTopMetaBar(),
                    if (_controller.inlineError.isNotEmpty) _inlineErrorToast(),
                    if (_controller.deviceCheckStatus != 'idle' &&
                        _controller.deviceCheckStatus != 'ready')
                      _deviceCheckBanner(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _buildBody(),
                      ),
                    ),
                    _buildControlBar(),
                  ],
                ),
                if (_controller.camError)
                  Positioned(bottom: 96, left: 16, right: 16, child: _camErrorBanner()),
                if (_controller.prescriptionNotif != null) _prescriptionToast(),
                if (_endCallConfirm)
                  _confirmOverlay(
                    title: _controller.isDoctor ? 'Leave or Complete?' : 'Leave Call?',
                    message: _controller.isDoctor
                        ? 'Leave only exits the video call. Complete Appointment will mark the consultation complete.'
                        : 'You will leave the video call. The doctor will be notified.',
                    confirmLabel: 'Leave Call',
                    confirmDanger: true,
                    secondaryLabel: _controller.isDoctor ? 'Complete Appointment' : null,
                    onCancel: () => setState(() => _endCallConfirm = false),
                    onConfirm: _handleEndCall,
                    onSecondary: _controller.isDoctor ? _handleEndCall : null,
                  ),
                if (_leaveConfirm)
                  _confirmOverlay(
                    title: 'Leave Consultation?',
                    message: 'Leaving will end your consultation session. Are you sure?',
                    confirmLabel: 'Leave',
                    confirmDanger: true,
                    onCancel: () => setState(() => _leaveConfirm = false),
                    onConfirm: () async {
                      setState(() => _leaveConfirm = false);
                      await _controller.leaveCall();
                      _navigateBack();
                    },
                  ),
                if (_controller.showCompletedOverlay && !_controller.isDoctor) _completedOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleEndCall() async {
    setState(() => _endCallConfirm = false);
    if (_controller.isDoctor) {
      final success = await _controller.completeAppointment();
      if (success) _navigateBack();
    } else {
      await _controller.leaveCall();
      _navigateBack();
    }
  }

  Widget _gateScreen({bool spinner = false, IconData? icon, String? title, String? message}) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.1,
            colors: [_C.gateBgTop, _C.gateBgBottom],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (spinner)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: _C.teal,
                      backgroundColor: Color(0x2619C9A3),
                    ),
                  ),
                if (icon != null) Icon(icon, size: 60, color: _C.gateIcon),
                const SizedBox(height: 20),
                if (title != null) Text(title, style: _sora(size: 24, weight: FontWeight.w700, color: _C.gateTitle)),
                const SizedBox(height: 8),
                Text(
                  message ?? '',
                  textAlign: TextAlign.center,
                  style: _dmSans(size: 14, color: _C.gateBody, height: 1.75),
                ),
                if (!spinner) ...[
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _C.gateBtnBg,
                      side: const BorderSide(color: _C.gateBtnBorder),
                      foregroundColor: _C.gateIcon,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Go Back', style: _sora(size: 13, weight: FontWeight.w600, color: _C.gateIcon)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top meta bar (ported from .hc-vc__ctrlbar-meta, which is what the
  // 2026 redesign actually renders at the top of the page — .hc-vc__topbar
  // and .hc-vc__infobar are `display: none` under that cascade layer) ────
  Widget _buildTopMetaBar() {
    final other = _controller.otherParty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 10),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_C.logoGradStart, _C.logoGradEnd]),
              boxShadow: [BoxShadow(color: Color(0xCC4DA3FF), blurRadius: 12)],
            ),
          ),
          Text('Humancare Connect', style: _sora(size: 15, weight: FontWeight.w700, color: _C.logoText)),
          if (other != null) ...[
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: Colors.white.withValues(alpha: 0.08),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (other['label'] ?? '').toString().toUpperCase(),
                    style: _sora(size: 10, weight: FontWeight.w600, color: _C.partyLabel, letterSpacing: 1),
                  ),
                  Text(
                    (other['name'] ?? '').toString(),
                    style: _sora(size: 13, weight: FontWeight.w600, color: _C.partyName),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ] else
            const Spacer(),
          // Timer is doctor-only on the web (`{inCall && isDoctor && ...}`) —
          // kept behind the same guard for parity even though this app never
          // authenticates as a doctor.
          if (_controller.inCall && _controller.isDoctor)
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _C.timerBg,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: _C.timerBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, color: _C.timerText, size: 14),
                  const SizedBox(width: 6),
                  Text(_fmtDuration(_controller.callDuration), style: _sora(size: 12, weight: FontWeight.w600, color: _C.timerText)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _inlineErrorToast() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: _C.toastBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.toastBorder),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: _C.toastText, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _controller.inlineError,
                style: _sora(size: 13, weight: FontWeight.w600, color: _C.toastText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceCheckBanner() {
    final failed = _controller.deviceCheckStatus == 'failed';
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: failed ? _C.toastBg : _C.deviceCheckingBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: failed ? _C.toastBorder : _C.deviceCheckingBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Icons.warning_amber_rounded : Icons.autorenew,
              color: failed ? _C.toastText : _C.deviceCheckingText,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              failed ? 'Device check failed. Review app permissions and retry.' : 'Checking camera and microphone...',
              style: _sora(size: 13, weight: FontWeight.w600, color: failed ? _C.toastText : _C.deviceCheckingText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _camErrorBanner() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: _C.camErrorBg,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: _C.camErrorBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: _C.camErrorText, size: 15),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _controller.camErrorReason.isNotEmpty
                    ? _controller.camErrorReason
                    : 'Camera or microphone access denied. Check app permissions and retry.',
                style: _sora(size: 13, weight: FontWeight.w500, color: _C.camErrorText),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _controller.retryingMedia ? null : () => unawaited(_controller.retryMediaPermissions()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  _controller.retryingMedia ? 'Retrying...' : 'Retry',
                  style: _sora(size: 12, weight: FontWeight.w700, color: _C.toastText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prescriptionToast() {
    final diagnosis = _controller.prescriptionNotif?['diagnosis']?.toString() ?? '';
    return Positioned(
      top: 14,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _C.rxNotifBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _C.rxNotifBorder),
          ),
          child: Row(
            children: [
              const Text('💊', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New prescription issued', style: _sora(size: 13, weight: FontWeight.w700, color: Colors.white)),
                    if (diagnosis.isNotEmpty)
                      Text(diagnosis, style: _dmSans(size: 12, color: _C.rxNotifText)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmOverlay({
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onCancel,
    required VoidCallback onConfirm,
    bool confirmDanger = false,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onCancel,
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                color: _C.modalBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.modalBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 64, offset: const Offset(0, 24))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_disabled, color: _C.btnEndText, size: 36),
                  const SizedBox(height: 12),
                  Text(title, textAlign: TextAlign.center, style: _sora(size: 17, weight: FontWeight.w600, color: _C.modalTitle)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center, style: _dmSans(size: 13, color: _C.modalBody, height: 1.4)),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _C.modalStayBg,
                          side: const BorderSide(color: _C.modalStayBorder),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Stay', style: _sora(size: 13, weight: FontWeight.w600, color: _C.modalStayText)),
                      ),
                      ElevatedButton(
                        onPressed: onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: confirmDanger ? _C.modalDangerBg : _C.teal,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(confirmLabel, style: _sora(size: 13, weight: FontWeight.w700, color: Colors.white)),
                      ),
                      if (secondaryLabel != null && onSecondary != null)
                        ElevatedButton(
                          onPressed: onSecondary,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _C.modalCompleteBg,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(secondaryLabel, style: _sora(size: 13, weight: FontWeight.w700, color: Colors.white)),
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
        color: _C.completedOverlayBg,
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_C.completedCardTop, _C.completedCardBottom],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _C.completedCardBorder),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 80, offset: const Offset(0, 24))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: _C.completedIcon, size: 64),
              const SizedBox(height: 16),
              Text('Consultation Completed', textAlign: TextAlign.center, style: _sora(size: 22, weight: FontWeight.w700, color: _C.completedTitle)),
              const SizedBox(height: 8),
              Text('Your doctor has marked this session as complete.', textAlign: TextAlign.center, style: _dmSans(size: 14, color: _C.completedBody, height: 1.65)),
              const SizedBox(height: 4),
              Text('Redirecting to your dashboard...', style: _dmSans(size: 12, color: _C.completedSub)),
              const SizedBox(height: 16),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2, color: _C.completedSpinner, backgroundColor: Color(0x2622C55E)),
              ),
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
        if (_controller.chatOpen) ...[
          const SizedBox(width: 10),
          SizedBox(width: 300, child: _buildChatPanel()),
        ],
      ],
    );
  }

  Widget _buildStage() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _C.stageBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.stageBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RTCVideoView(
              _controller.mainRenderer,
              mirror: _controller.isSwapped,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          if (!_controller.isRemoteConnected && !_controller.isSwapped)
            Positioned.fill(child: _waitingOverlay()),
          if (_controller.reconnectStalled)
            Positioned(
              bottom: 118,
              left: 0,
              right: 0,
              child: Center(child: _pillNotice(
                icon: Icons.warning_amber_rounded,
                text: 'Reconnection is taking longer than expected.',
                trailing: GestureDetector(
                  onTap: () => unawaited(_controller.forceReconnect()),
                  child: Text('  Retry', style: _sora(size: 12, weight: FontWeight.w700, color: _C.teal)),
                ),
              )),
            ),
          if (_controller.peerLeft)
            Positioned(
              bottom: 62,
              left: 0,
              right: 0,
              child: Center(
                child: _pillNotice(icon: Icons.phone_disabled, text: '${_controller.isDoctor ? "Patient" : "Doctor"} has left the call.'),
              ),
            ),
          if (!_isSelfViewMinimized) _buildPip() else _buildRestorePipButton(),
          if (_controller.peerJoined && !_controller.isRemoteConnected)
            Positioned(
              top: 18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Blink(color: _C.teal, size: 7),
                      const SizedBox(width: 8),
                      Text(
                        '${_controller.isDoctor ? "Patient" : "Doctor"} joined - connecting...',
                        style: _dmSans(size: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pillNotice({required IconData icon, required String text, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: _C.peerLeftBg,
        border: Border.all(color: _C.peerLeftBorder),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _C.peerLeftText, size: 15),
          const SizedBox(width: 10),
          Text(text, style: _sora(size: 13, weight: FontWeight.w600, color: _C.peerLeftText)),
          ?trailing,
        ],
      ),
    );
  }

  Widget _waitingOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.1,
          colors: [_C.waitingBgTop, _C.waitingBgBottom],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              const _PulseRing(),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _C.waitingAvatarBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _C.waitingAvatarBorder),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.person_outline, color: _C.waitingTitle, size: 40),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _controller.camError && !_controller.peerJoined
                ? 'Camera or microphone access needed'
                : _controller.peerJoined
                    ? (_controller.hasConnectedOnce ? 'Reconnecting...' : 'Establishing secure connection...')
                    : 'Waiting for ${_controller.isDoctor ? "patient" : "doctor"}...',
            style: _sora(size: 17, weight: FontWeight.w600, color: _C.waitingTitle),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _controller.camError && !_controller.peerJoined
                  ? 'Allow camera and microphone access below, then tap Retry to join.'
                  : _controller.peerJoined
                      ? (_controller.hasConnectedOnce
                            ? 'Restoring your connection to the call.'
                            : 'Both participants are ready. Video starting soon.')
                      : 'Share the appointment link with the other person to begin.',
              style: _dmSans(size: 13, color: _C.waitingSub, height: 1.7),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPip() {
    final size = MediaQuery.of(context).size;
    const pipW = 130.0;
    const pipH = pipW * 9 / 16;
    final pos = _pipPos ?? Offset(size.width - pipW - 20, 20);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final newX = (pos.dx + details.delta.dx).clamp(8.0, size.width - pipW - 8.0);
            final newY = (pos.dy + details.delta.dy).clamp(8.0, size.height - pipH - 8.0);
            _pipPos = Offset(newX, newY);
          });
        },
        child: Container(
          width: pipW,
          height: pipH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _C.pipBorder, width: 2),
            color: _C.pipBg,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.65), blurRadius: 40, offset: const Offset(0, 8))],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  _controller.pipRenderer,
                  mirror: !_controller.isSwapped,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
              if (_controller.isCamOff && !_controller.isSwapped)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(color: _C.pipBg, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: Icon(Icons.videocam_off, color: _C.pipLabel, size: 26),
                  ),
                ),
              Positioned(
                left: 9,
                bottom: 7,
                child: Text(
                  (_controller.isSwapped ? (_controller.otherParty?['label'] ?? 'Remote') : 'You').toString().toUpperCase(),
                  style: _sora(size: 10, weight: FontWeight.w600, color: _C.pipLabel, letterSpacing: 0.7),
                ),
              ),
              Positioned(
                top: -10,
                right: -10,
                child: GestureDetector(
                  onTap: () => setState(() => _isSelfViewMinimized = true),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(color: Color(0xB3000000), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, color: Colors.white70, size: 13),
                  ),
                ),
              ),
              Positioned(
                top: -10,
                right: 20,
                child: GestureDetector(
                  onTap: _controller.toggleSwap,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(color: _C.pipSwapBg, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.swap_horiz, color: _C.pipSwapIcon, size: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRestorePipButton() {
    return Positioned(
      top: 16,
      right: 16,
      child: GestureDetector(
        onTap: () => setState(() => _isSelfViewMinimized = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _C.btnBg,
            border: Border.all(color: _C.btnBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_full, size: 14, color: _C.btnText),
              const SizedBox(width: 6),
              Text('Self View', style: _sora(size: 11, weight: FontWeight.w600, color: _C.btnText)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _C.chatBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.chatBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, color: _C.chatTitle, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('In-call Chat', style: _sora(size: 13, weight: FontWeight.w600, color: _C.chatTitle)),
                ),
                GestureDetector(
                  onTap: () => _controller.setChatOpen(false),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _C.chatCloseBg,
                      border: Border.all(color: _C.chatCloseBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, color: _C.chatCloseIcon, size: 14),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          Expanded(
            child: _controller.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline, color: _C.chatEmpty.withValues(alpha: 0.6), size: 34),
                          const SizedBox(height: 8),
                          Text('No messages yet.', style: _dmSans(size: 12, color: _C.chatEmpty, height: 1.65)),
                          Text(
                            'Share notes or files here during the call.',
                            style: _dmSans(size: 12, color: _C.chatEmpty, height: 1.65),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _controller.messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = _controller.messages[i];
                      final mine = msg.senderId == _controller.currentUser['id'];
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Column(
                            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!mine)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 3),
                                  child: Text(msg.senderName, style: _sora(size: 10, weight: FontWeight.w600, color: _C.msgName)),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: mine ? _C.msgMineBg : _C.msgTheirsBg,
                                  border: mine ? null : Border.all(color: _C.msgTheirsBorder),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(14),
                                    topRight: const Radius.circular(14),
                                    bottomLeft: Radius.circular(mine ? 14 : 4),
                                    bottomRight: Radius.circular(mine ? 4 : 14),
                                  ),
                                ),
                                child: msg.fileUrl != null
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('📎 ', style: _dmSans(size: 13, color: mine ? _C.msgMineText : _C.msgTheirsText)),
                                          Flexible(
                                            child: Text(
                                              msg.fileName ?? 'Attachment',
                                              style: _dmSans(size: 13, weight: FontWeight.w500, color: mine ? _C.msgMineText : _C.msgTheirsText),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        msg.text,
                                        style: _dmSans(size: 13, color: mine ? _C.msgMineText : _C.msgTheirsText, height: 1.5),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                child: Text(_fmtTime(msg.createdAt), style: _dmSans(size: 10, color: _C.msgTime)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _controller.uploadingFile ? null : _handleAttachFile,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _C.chatCloseBg,
                      border: Border.all(color: _C.chatInputBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: _controller.uploadingFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _C.teal),
                          )
                        : const Icon(Icons.attach_file, color: _C.chatCloseIcon, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _C.chatInputBg,
                      border: Border.all(color: _C.chatInputBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: _chatInputCtrl,
                      style: _dmSans(size: 13, color: _C.chatInputText),
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: _dmSans(size: 13, color: _C.chatInputHint),
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: _C.teal, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.send, color: _C.msgMineText, size: 17),
                  ),
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
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF2000000), Color(0xFA020C18)],
        ),
        border: const Border(top: BorderSide(color: _C.ctrlbarBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ctrlButton(
              icon: _controller.isMuted ? Icons.mic_off : Icons.mic,
              label: _controller.isMuted ? 'Unmute' : 'Mute',
              danger: _controller.isMuted,
              onTap: _controller.isReady ? _controller.toggleMute : null,
            ),
            _ctrlButton(
              icon: _controller.isCamOff ? Icons.videocam_off : Icons.videocam,
              label: _controller.isCamOff ? 'Cam On' : 'Cam Off',
              danger: _controller.isCamOff,
              onTap: _controller.isReady ? _controller.toggleCamera : null,
            ),
            _ctrlButton(
              icon: Icons.screen_share_outlined,
              label: _controller.isScreenSharing ? 'Stop' : 'Share',
              active: _controller.isScreenSharing,
              onTap: _controller.isReady ? _controller.toggleScreenShare : null,
            ),
            if (_controller.inCall) _livePill(),
            if (_controller.inCall && _controller.connectionQuality != 'unknown')
              _qualityPill(_controller.connectionQuality),
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
              onTap: () => setState(() => _isSelfViewMinimized = !_isSelfViewMinimized),
            ),
            _ctrlButton(
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              chatOn: _controller.chatOpen,
              badge: (_controller.unreadCount > 0 && !_controller.chatOpen) ? _controller.unreadCount : null,
              onTap: () => _controller.setChatOpen(!_controller.chatOpen),
            ),
            _ctrlButton(
              icon: _controller.completing ? Icons.refresh : Icons.phone_disabled,
              label: _controller.completing ? 'Completing...' : 'Leave Call',
              end: true,
              onTap: _controller.completing ? null : () => setState(() => _endCallConfirm = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _livePill() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _C.livePillBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.livePillBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Blink(color: _C.livePillText, size: 8),
          const SizedBox(width: 7),
          Text('LIVE', style: _sora(size: 11, weight: FontWeight.w700, color: _C.livePillText, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  // Same three buckets/colors/tooltip copy as VideoCall.jsx's
  // .hc-vc__quality-pill--{good,weak,poor} — driven by
  // VideoCallController.connectionQuality (see deriveConnectionQuality).
  Widget _qualityPill(String quality) {
    final Color bg;
    final Color border;
    final Color color;
    final String tooltip;
    switch (quality) {
      case 'poor':
        bg = _C.qualityPoorBg;
        border = _C.qualityPoorBorder;
        color = _C.qualityPoorText;
        tooltip = 'Poor connection — the call may drop';
        break;
      case 'weak':
        bg = _C.qualityWeakBg;
        border = _C.qualityWeakBorder;
        color = _C.qualityWeakText;
        tooltip = 'Unstable connection — video quality may drop';
        break;
      default:
        bg = _C.qualityGoodBg;
        border = _C.qualityGoodBorder;
        color = _C.qualityGoodText;
        tooltip = 'Good connection';
    }
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Icon(Icons.wifi, color: color, size: 18),
      ),
    );
  }

  Widget _ctrlButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool danger = false,
    bool active = false,
    bool chatOn = false,
    bool end = false,
    int? badge,
  }) {
    Color bg = _C.btnBg;
    Color border = _C.btnBorder;
    Color color = _C.btnText;

    if (end) {
      bg = _C.btnEndBg;
      border = _C.btnEndBorder;
      color = _C.btnEndText;
    } else if (danger) {
      bg = _C.btnDangerBg;
      border = _C.btnDangerBorder;
      color = _C.btnDangerText;
    } else if (chatOn) {
      bg = _C.btnChatOnBg;
      border = _C.btnChatOnBorder;
      color = _C.teal;
    } else if (active) {
      bg = _C.btnActiveBg;
      border = _C.btnActiveBorder;
      color = _C.btnActiveText;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: end ? 88 : 76,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: color, size: 21),
                    if (badge != null)
                      Positioned(
                        right: -8,
                        top: -7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: const BoxDecoration(color: _C.badgeBg, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            badge > 9 ? '9+' : '$badge',
                            style: _sora(size: 10, weight: FontWeight.w700, color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: _sora(size: 10, weight: FontWeight.w600, color: color, letterSpacing: 0.3),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ported from videocall.css's `vc-ring-pulse` keyframe (two rings, 2.5s
/// each, second offset by 1.25s) — the expanding/fading teal ring behind the
/// waiting-overlay avatar.
class _PulseRing extends StatefulWidget {
  const _PulseRing();

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _ring(double delay) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = (_controller.value + delay) % 1.0;
        return Opacity(
          opacity: (0.6 * (1 - t)).clamp(0.0, 0.6),
          child: Transform.scale(
            scale: 1 + 0.7 * t,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _C.waitingRing, width: 2),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [_ring(0), _ring(0.5)],
      ),
    );
  }
}

/// Ported from videocall.css's `vc-blink` keyframe (1.1-1.2s opacity pulse) —
/// used for the live-pill dot and the join-toast dot.
class _Blink extends StatefulWidget {
  const _Blink({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> {
  bool _dim = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!mounted) return;
      setState(() => _dim = !_dim);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _dim ? 0.2 : 1,
      duration: const Duration(milliseconds: 600),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
