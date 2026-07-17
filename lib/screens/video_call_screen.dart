// video_call_screen.dart
//
// Thin presentation layer over VideoCallController — mirrors the visual
// design of the React VideoCall page (gate screens, stage, PiP, chat panel,
// control bar, confirm overlays), but owns no signaling/WebRTC logic itself.
// See lib/controllers/video_call_controller.dart for the ported behavior.
//
// Deliberately NOT ported from the web UI: screen sharing (native mobile
// screen capture needs platform-specific plumbing well beyond this app) and
// the doctor-authored prescription/notes UI (this app has no doctor login
// flow — see the controller's class doc comment).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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
      unawaited(_controller.performCleanup());
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
      return _gateScreen(spinner: true, message: 'Loading appointment…');
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
        backgroundColor: const Color(0xFF0B1626),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(),
                  if (_controller.inlineError.isNotEmpty) _inlineErrorBanner(),
                  if (_controller.reconnectStalled) _reconnectStalledBanner(),
                  Expanded(child: _buildBody()),
                  _buildControlBar(),
                  if (_controller.camError) _camErrorBanner(),
                ],
              ),
              if (_controller.prescriptionNotif != null) _prescriptionToast(),
              if (_endCallConfirm)
                _confirmOverlay(
                  title: _controller.isDoctor ? 'End Consultation?' : 'Leave Call?',
                  message: _controller.isDoctor
                      ? 'This will end the call and mark the consultation as completed.'
                      : 'You will leave the video call. The doctor will be notified.',
                  confirmLabel: _controller.isDoctor ? 'End & Complete' : 'Leave Call',
                  onCancel: () => setState(() => _endCallConfirm = false),
                  onConfirm: _handleEndCall,
                ),
              if (_leaveConfirm)
                _confirmOverlay(
                  title: 'Leave Consultation?',
                  message: 'Leaving will end your consultation session. Are you sure?',
                  confirmLabel: 'Leave',
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
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
    final other = _controller.otherParty;
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
          if (other != null)
            Expanded(
              child: Text(
                '${other['label']}: ${other['name']}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (_controller.inCall)
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text(_fmtDuration(_controller.callDuration),
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
            child: Text(_controller.inlineError,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _reconnectStalledBanner() {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Still connecting… this is taking longer than usual.",
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_controller.forceReconnect()),
            child: const Text('Reconnect', style: TextStyle(color: Colors.white)),
          ),
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
              _controller.camErrorReason.isNotEmpty
                  ? _controller.camErrorReason
                  : 'Camera or microphone access denied. Check app permissions and reload.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_controller.retryMediaPermissions()),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _prescriptionToast() {
    final diagnosis = _controller.prescriptionNotif?['diagnosis']?.toString() ?? '';
    return Positioned(
      top: 60,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1F35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.tealAccent.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Text('💊', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New prescription issued',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    if (diagnosis.isNotEmpty)
                      Text(diagnosis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
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
        if (_controller.chatOpen) SizedBox(width: 320, child: _buildChatPanel()),
      ],
    );
  }

  Widget _buildStage() {
    return Stack(
      children: [
        Positioned.fill(
          child: RTCVideoView(
            _controller.mainRenderer,
            mirror: _controller.isSwapped,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        if (!_controller.isRemoteConnected && !_controller.isSwapped)
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
                    _controller.peerJoined
                        ? 'Establishing secure connection…'
                        : 'Waiting for ${_controller.isDoctor ? "patient" : "doctor"}…',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _controller.peerJoined
                        ? 'Both participants are ready. Video starting soon.'
                        : 'Share the appointment link with the other person to begin.',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        if (_controller.peerLeft)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration:
                    BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.call_end, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text('${_controller.isDoctor ? "Patient" : "Doctor"} has left the call.',
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        if (!_isSelfViewMinimized) _buildPip() else _buildRestorePipButton(),
        if (_controller.peerJoined && !_controller.isRemoteConnected)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration:
                    BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '${_controller.isDoctor ? "Patient" : "Doctor"} joined · connecting…',
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
            final newX = (pos.dx + details.delta.dx).clamp(8.0, size.width - 128 - 8.0);
            final newY = (pos.dy + details.delta.dy).clamp(8.0, size.height - 172 - 8.0);
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
                  _controller.pipRenderer,
                  mirror: !_controller.isSwapped,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
              if (_controller.isCamOff && !_controller.isSwapped)
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
                  _controller.isSwapped
                      ? (_controller.otherParty?['label'] ?? 'Remote')
                      : 'You${_controller.isDoctor ? " (Doctor)" : ""}',
                  style:
                      const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Row(
                  children: [
                    _pipIconButton(
                        Icons.close_fullscreen, () => setState(() => _isSelfViewMinimized = true)),
                    const SizedBox(width: 4),
                    _pipIconButton(Icons.swap_horiz, _controller.toggleSwap),
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
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }

  Widget _buildRestorePipButton() {
    return Positioned(
      top: 16,
      right: 16,
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _isSelfViewMinimized = false),
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
                  onPressed: () => _controller.setChatOpen(false),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: _controller.messages.isEmpty
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
                    itemCount: _controller.messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = _controller.messages[i];
                      final mine = msg.senderId == _controller.currentUser['id'];
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
                                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              if (msg.fileUrl != null)
                                Text('📎 ${msg.fileName ?? "Attachment"}',
                                    style: const TextStyle(color: Colors.white))
                              else
                                Text(msg.text, style: const TextStyle(color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(_fmtTime(msg.createdAt),
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
                  onPressed: _controller.uploadingFile ? null : _handleAttachFile,
                  icon: _controller.uploadingFile
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
            if (_controller.inCall)
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
              onTap: () => setState(() => _isSelfViewMinimized = !_isSelfViewMinimized),
            ),
            _ctrlButton(
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              active: _controller.chatOpen,
              badge: (_controller.unreadCount > 0 && !_controller.chatOpen)
                  ? _controller.unreadCount
                  : null,
              onTap: () => _controller.setChatOpen(!_controller.chatOpen),
            ),
            _ctrlButton(
              icon: _controller.completing ? Icons.refresh : Icons.call_end,
              label: _controller.completing ? 'Ending...' : 'End Call',
              danger: true,
              onTap: _controller.completing ? null : () => setState(() => _endCallConfirm = true),
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
    final color = danger ? Colors.redAccent : (active ? Colors.tealAccent : Colors.white);

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
                          decoration:
                              const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
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
