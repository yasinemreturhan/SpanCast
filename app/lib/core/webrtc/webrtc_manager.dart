import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../client/signaling_client.dart';
import '../protocol/models.dart';

/// Manages WebRTC PeerConnection for low-latency screen streaming and receiving.
class WebRtcManager {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _secondaryAudioStream;
  final SignalingClient? signalingClient;

  WebRtcManager({this.signalingClient});

  RTCPeerConnection? get peerConnection => _peerConnection;
  MediaStream? get localStream => _localStream;

  static const Map<String, dynamic> _lowLatencyConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'}
    ],
    'sdpSemantics': 'unified-plan',
  };

  /// Initializes a sender PeerConnection and captures the screen (with optional audio).
  Future<MediaStream> startScreenCapture({
    String? sourceId,
    int width = 1920,
    int height = 1080,
    int fps = 60,
    bool enableAudio = true,
  }) async {
    MediaStream stream;
    MediaStream? secondaryAudioStream;

    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('app.doscreen/media_projection_service');
        await platform.invokeMethod('startService');
      } catch (_) {}
    }

    dynamic videoConstraints = true;
    if (WebRTC.platformIsDesktop) {
      try {
        final sources = await desktopCapturer.getSources(types: [SourceType.Screen, SourceType.Window]);
        final target = (sourceId != null && sources.any((s) => s.id == sourceId))
            ? sources.firstWhere((s) => s.id == sourceId)
            : (sources.isNotEmpty ? sources.first : null);
        if (target != null) {
          videoConstraints = {
            'deviceId': {'exact': target.id},
            'mandatory': {
              'frameRate': fps,
            },
          };
        }
      } catch (_) {}
    }

    try {
      final mediaConstraints = <String, dynamic>{
        'audio': enableAudio,
        'video': videoConstraints,
      };
      stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
    } catch (_) {
      // If audio capture is denied or unsupported on this OS, fall back gracefully to video only
      final fallbackConstraints = <String, dynamic>{
        'audio': false,
        'video': videoConstraints,
      };
      stream = await navigator.mediaDevices.getDisplayMedia(fallbackConstraints);
    }

    // Capture device audio via getUserMedia if getDisplayMedia returned no audio tracks
    if (enableAudio && stream.getAudioTracks().isEmpty) {
      try {
        secondaryAudioStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': false,
            'noiseSuppression': false,
            'autoGainControl': false,
          },
          'video': false,
        });
        for (final track in secondaryAudioStream.getAudioTracks()) {
          track.enabled = true;
          try {
            await stream.addTrack(track);
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('Audio capture fallback error: $e');
      }
    }

    _localStream = stream;
    _secondaryAudioStream = secondaryAudioStream;

    _peerConnection = await createPeerConnection(_lowLatencyConfiguration);

    final allTracks = <MediaStreamTrack>[
      ...stream.getTracks(),
      if (secondaryAudioStream != null) ...secondaryAudioStream.getAudioTracks(),
    ];
    final seenIds = <String>{};
    final uniqueTracks = allTracks.where((t) => t.id != null && seenIds.add(t.id!)).toList();

    for (final track in uniqueTracks) {
      await _peerConnection!.addTrack(track, stream);
    }

    _peerConnection!.onIceCandidate = (candidate) {
      signalingClient?.send(SignalMessage(
        type: 'ice',
        payload: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      ));
    };

    // Low latency codec preference: prefer H264 if available
    try {
      final transceivers = await _peerConnection!.getTransceivers();
      for (final t in transceivers) {
        if (t.sender.track?.kind == 'video') {
          final capabilities = await getRtpSenderCapabilities('video');
          final codecs = capabilities.codecs;
          if (codecs != null) {
            final h264Codecs = codecs
                .where((c) => c.mimeType.toLowerCase() == 'video/h264')
                .toList();
            if (h264Codecs.isNotEmpty) {
              await t.setCodecPreferences(h264Codecs);
            }
          }
        }
      }
    } catch (_) {}

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 0,
      'offerToReceiveVideo': 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    signalingClient?.send(SignalMessage(
      type: 'offer',
      payload: {'sdp': offer.sdp, 'type': offer.type},
    ));

    return stream;
  }

  /// Handles incoming offer and creates answer (used on receiver side).
  Future<RTCSessionDescription> handleOffer(
    Map<String, dynamic> sdpMap,
    void Function(RTCIceCandidate candidate) onCandidate,
    void Function(MediaStream stream) onStream,
  ) async {
    _peerConnection = await createPeerConnection(_lowLatencyConfiguration);

    _peerConnection!.onIceCandidate = (candidate) {
      onCandidate(candidate);
    };

    _peerConnection!.onTrack = (event) {
      event.track.enabled = true;
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        if (event.track.kind == 'audio' && !stream.getAudioTracks().any((t) => t.id == event.track.id)) {
          try {
            stream.addTrack(event.track);
          } catch (_) {}
        }
        for (final t in stream.getAudioTracks()) {
          t.enabled = true;
        }
        onStream(stream);
      }
    };
    _peerConnection!.onAddStream = (stream) {
      for (final t in stream.getAudioTracks()) {
        t.enabled = true;
      }
      onStream(stream);
    };

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
    );

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> handleAnswer(Map<String, dynamic> sdpMap) async {
    if (_peerConnection != null) {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
      );
    }
  }

  Future<void> addCandidate(Map<String, dynamic> candidateMap) async {
    if (_peerConnection != null) {
      final candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
    }
  }

  Future<void> dispose() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('app.doscreen/media_projection_service');
        await platform.invokeMethod('stopService');
      } catch (_) {}
    }
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
      _secondaryAudioStream?.getTracks().forEach((track) => track.stop());
      await _secondaryAudioStream?.dispose();
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (_) {}
    _localStream = null;
    _secondaryAudioStream = null;
    _peerConnection = null;
  }
}
