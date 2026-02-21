import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../../services/service_locator.dart';
import '../../../../core/constants/app_colors.dart';

class LiveVdoPage extends StatefulWidget {
  final String roomId;
  final bool isCaller;
  final String otherParticipantName;

  const LiveVdoPage({
    super.key,
    required this.roomId,
    required this.isCaller,
    required this.otherParticipantName,
  });

  @override
  State<LiveVdoPage> createState() => _LiveVdoPageState();
}

class _LiveVdoPageState extends State<LiveVdoPage> {
  final _webSocketService = ServiceLocator.instance.websocketService;
  final _currentUser = ServiceLocator.instance.currentUser;
  
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    final Map<String, dynamic> configuration = {
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      _webSocketService.sendWebRTCSignal(widget.roomId, {
        'type': 'candidate',
        'candidate': candidate.toMap(),
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
        if (mounted) setState(() {});
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': _isFrontCamera ? 'user' : 'environment',
      },
    });

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _localRenderer.srcObject = _localStream;
    if (mounted) setState(() {});

    // Listen for signals
    _webSocketService.webrtcSignalStream.listen((data) async {
      if (data['roomId'] != widget.roomId) return;
      
      final signal = data['signal'];
      final type = signal['type'];

      if (type == 'offer') {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(signal['sdp'], signal['type']),
        );
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _webSocketService.sendWebRTCSignal(widget.roomId, {
          'type': 'answer',
          'sdp': answer.sdp,
        });
      } else if (type == 'answer') {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(signal['sdp'], signal['type']),
        );
      } else if (type == 'candidate') {
        await _peerConnection!.addCandidate(
          RTCIceCandidate(
            signal['candidate']['candidate'],
            signal['candidate']['sdpMid'],
            signal['candidate']['sdpMLineIndex'],
          ),
        );
      }
    });

    if (widget.isCaller) {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _webSocketService.sendWebRTCSignal(widget.roomId, {
        'type': 'offer',
        'sdp': offer.sdp,
      });
    }

    // Listen for call rejection/end
    _webSocketService.callRejectStream.listen((data) {
      if (data['roomId'] == widget.roomId) {
        _hangUp();
      }
    });
  }

  void _hangUp() {
    _webSocketService.rejectCall(widget.roomId, _currentUser?.id ?? '');
    _peerConnection?.close();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    if (mounted) Navigator.pop(context);
  }

  void _toggleMic() {
    setState(() {
      _isMicOn = !_isMicOn;
      _localStream?.getAudioTracks().forEach((track) {
        track.enabled = _isMicOn;
      });
    });
  }

  void _toggleCamera() {
    setState(() {
      _isCameraOn = !_isCameraOn;
      _localStream?.getVideoTracks().forEach((track) {
        track.enabled = _isCameraOn;
      });
    });
  }

  void _switchCamera() {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _localStream?.getVideoTracks().forEach((track) {
        Helper.switchCamera(track);
      });
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video (Full Screen)
          Positioned.fill(
            child: RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          
          // Local Video (Small Overlay)
          Positioned(
            top: 50,
            right: 20,
            width: 120,
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Colors.grey[900],
                child: RTCVideoView(
                  _localRenderer,
                  mirror: _isFrontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          ),

          // Header
          Positioned(
            top: 50,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherParticipantName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Connected',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  onPressed: _toggleMic,
                  icon: _isMicOn ? Icons.mic : Icons.mic_off,
                  color: _isMicOn ? Colors.white24 : Colors.red,
                ),
                _buildControlButton(
                  onPressed: _hangUp,
                  icon: Icons.call_end,
                  color: Colors.red,
                  size: 70,
                ),
                _buildControlButton(
                  onPressed: _toggleCamera,
                  icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                  color: _isCameraOn ? Colors.white24 : Colors.red,
                ),
                _buildControlButton(
                  onPressed: _switchCamera,
                  icon: Icons.cameraswitch,
                  color: Colors.white24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required VoidCallback onPressed,
    required IconData icon,
    required Color color,
    double size = 56,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}
