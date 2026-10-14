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
  MediaStream? _micStream;
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

  /// Initializes a sender PeerConnection and captures the screen (with separate system audio and microphone controls).
  Future<MediaStream> startScreenCapture({
    String? sourceId,
    int width = 1920,
    int height = 1080,
    int fps = 30,
    bool enableAudio = true,
    bool enableSystemAudio = true,
    bool enableMicrophone = false,
  }) async {
    MediaStream stream;
    MediaStream? secondaryAudioStream;
    MediaStream? micStream;

    final shouldCaptureSystemAudio = !Platform.isAndroid && enableAudio && enableSystemAudio;

    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('app.doscreen/media_projection_service');
        await platform.invokeMethod('startService');
        if (enableMicrophone) {
          final hasAudio = await platform.invokeMethod<bool>('hasAudioPermission') ?? false;
          if (!hasAudio) {
            await platform.invokeMethod('requestAudioPermission');
          }
        }
      } catch (_) {}
    }

    dynamic videoConstraints = true;
    if (WebRTC.platformIsDesktop) {
      try {
        final sources = await desktopCapturer.getSources(types: [SourceType.Screen]);
        final target = (sourceId != null && sources.any((s) => s.id == sourceId))
            ? sources.firstWhere((s) => s.id == sourceId)
            : null;
        if (target != null) {
          videoConstraints = {
            'deviceId': {'exact': target.id},
            'mandatory': {
              'frameRate': fps,
            },
          };
        } else {
          // Default display: omit deviceId so macOS/Windows uses the primary screen directly
          videoConstraints = {
            'mandatory': {
              'frameRate': fps,
            },
          };
        }
      } catch (_) {
        videoConstraints = {
          'mandatory': {
            'frameRate': fps,
          },
        };
      }
    }

    try {
      final mediaConstraints = <String, dynamic>{
        'audio': shouldCaptureSystemAudio,
        'video': videoConstraints,
      };
      stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
    } catch (_) {
      try {
        final fallbackConstraints = <String, dynamic>{
          'audio': false,
          'video': {
            'mandatory': {
              'frameRate': fps,
            },
          },
        };
        stream = await navigator.mediaDevices.getDisplayMedia(fallbackConstraints);
      } catch (_) {
        stream = await navigator.mediaDevices.getDisplayMedia({
          'audio': false,
          'video': true,
        });
      }
    }

    // Capture desktop audio via getUserMedia if getDisplayMedia returned no audio tracks (AGC enabled for volume boost!)
    if (!Platform.isAndroid && shouldCaptureSystemAudio && stream.getAudioTracks().isEmpty) {
      try {
        secondaryAudioStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'mandatory': {
              'googEchoCancellation': 'false',
              'googEchoCancellation2': 'false',
              'googDAEchoCancellation': 'false',
              'googNoiseSuppression': 'false',
              'googAutoGainControl': 'true',
              'googAutoGainControl2': 'true',
              'googHighpassFilter': 'false',
              'echoCancellation': 'false',
            },
            'optional': [],
          },
          'video': false,
        });
      } catch (_) {
        try {
          secondaryAudioStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          });
        } catch (e) {
          debugPrint('Audio capture fallback error: $e');
        }
      }
      if (secondaryAudioStream != null) {
        for (final track in secondaryAudioStream.getAudioTracks()) {
          track.enabled = true;
          try {
            await stream.addTrack(track);
          } catch (_) {}
        }
      }
    }

    // Capture microphone independently if enabled
    if (enableMicrophone) {
      bool canCaptureMic = true;
      if (Platform.isAndroid) {
        try {
          const platform = MethodChannel('app.doscreen/media_projection_service');
          canCaptureMic = await platform.invokeMethod<bool>('hasAudioPermission') ?? false;
        } catch (_) {
          canCaptureMic = false;
        }
      }
      if (canCaptureMic) {
        try {
          micStream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'mandatory': {
                'googEchoCancellation': 'true',
                'googNoiseSuppression': 'true',
                'googAutoGainControl': 'true',
              },
              'optional': [],
            },
            'video': false,
          });
          for (final track in micStream.getAudioTracks()) {
            track.enabled = true;
            try {
              await stream.addTrack(track);
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('Microphone capture error: $e');
        }
      }
    }

    _localStream = stream;
    _secondaryAudioStream = secondaryAudioStream;
    _micStream = micStream;

    _peerConnection = await createPeerConnection(_lowLatencyConfiguration);

    final allTracks = <MediaStreamTrack>[
      ...stream.getTracks(),
      if (secondaryAudioStream != null) ...secondaryAudioStream.getAudioTracks(),
      if (micStream != null) ...micStream.getAudioTracks(),
    ];
    final seenIds = <String>{};
    final uniqueTracks = allTracks.where((t) => t.id != null && seenIds.add(t.id!)).toList();

    for (final track in uniqueTracks) {
      await _peerConnection!.addTrack(track, stream);
    }

    // Configure video senders for smooth streaming and zero freeze:
    // 1. Cap maxBitrate to 6 Mbps to avoid Wi-Fi buffer bloat and packet drops
    // 2. Set degradationPreference to MAINTAIN_FRAMERATE to prevent freezing during minor packet loss
    try {
      final senders = await _peerConnection!.getSenders();
      for (final s in senders) {
        if (s.track?.kind == 'video') {
          final params = s.parameters;
          if (params.encodings != null && params.encodings!.isNotEmpty) {
            for (final enc in params.encodings!) {
              enc.maxFramerate = fps;
              enc.maxBitrate = 6000000;
              enc.minBitrate = 1000000;
            }
          }
          params.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
          await s.setParameters(params);
        }
      }
    } catch (_) {}

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

    var offerSdp = offer.sdp ?? '';
    offerSdp = offerSdp.replaceAll(
      'useinbandfec=1',
      'useinbandfec=1;stereo=1;sprop-stereo=1;maxaveragebitrate=192000',
    );
    final boostedOffer = RTCSessionDescription(offerSdp, offer.type);
    await _peerConnection!.setLocalDescription(boostedOffer);

    signalingClient?.send(SignalMessage(
      type: 'offer',
      payload: {'sdp': boostedOffer.sdp, 'type': boostedOffer.type},
    ));

    return stream;
  }

  /// Live toggle for microphone on sender
  void setMicrophoneEnabled(bool enabled) {
    if (_micStream != null) {
      for (final t in _micStream!.getAudioTracks()) {
        t.enabled = enabled;
      }
    }
  }

  /// Live toggle for system/media audio on sender
  void setSystemAudioEnabled(bool enabled) {
    if (_localStream != null) {
      for (final t in _localStream!.getAudioTracks()) {
        t.enabled = enabled;
      }
    }
    if (_secondaryAudioStream != null) {
      for (final t in _secondaryAudioStream!.getAudioTracks()) {
        t.enabled = enabled;
      }
    }
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

    MediaStream? currentRemoteStream;
    _peerConnection!.onTrack = (event) async {
      event.track.enabled = true;
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
        currentRemoteStream = stream;
      } else {
        currentRemoteStream ??= await createLocalMediaStream('remote_stream_${DateTime.now().millisecondsSinceEpoch}');
        stream = currentRemoteStream!;
      }
      if (!stream.getTracks().any((t) => t.id == event.track.id)) {
        try {
          await stream.addTrack(event.track);
        } catch (_) {}
      }
      for (final t in stream.getAudioTracks()) {
        t.enabled = true;
      }
      onStream(stream);
    };
    _peerConnection!.onAddStream = (stream) {
      currentRemoteStream = stream;
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
      _micStream?.getTracks().forEach((track) => track.stop());
      await _micStream?.dispose();
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (_) {}
    _localStream = null;
    _secondaryAudioStream = null;
    _micStream = null;
    _peerConnection = null;
  }
}
