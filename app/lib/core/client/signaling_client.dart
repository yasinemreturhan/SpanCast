import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../protocol/models.dart';
import '../protocol/proof.dart';

enum SignalingClientState {
  disconnected,
  connecting,
  authenticating,
  paired,
  failed,
}

typedef MessageCallback = void Function(SignalMessage message);

/// Client connecting to a receiver device's embedded signaling server.
class SignalingClient {
  final Uri serverUri;
  final String deviceName;
  final String pin;
  final String? trustToken;

  WebSocket? _socket;
  SignalingClientState _state = SignalingClientState.disconnected;
  String? _senderId;
  String? _issuedToken;
  bool _manuallyClosed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  final Map<String, List<MessageCallback>> _listeners = {};
  final List<SignalMessage> _sendQueue = [];

  SignalingClient({
    required this.serverUri,
    required this.deviceName,
    required this.pin,
    this.trustToken,
  });

  SignalingClientState get state => _state;
  String? get senderId => _senderId;
  String? get issuedToken => _issuedToken;

  void on(String type, MessageCallback callback) {
    _listeners.putIfAbsent(type, () => []).add(callback);
  }

  void _emit(String type, SignalMessage message) {
    for (final cb in _listeners[type] ?? const []) {
      try {
        cb(message);
      } catch (_) {}
    }
    for (final cb in _listeners['*'] ?? const []) {
      try {
        cb(message);
      } catch (_) {}
    }
  }

  Future<void> connect() async {
    if (_manuallyClosed) return;
    _reconnectTimer?.cancel();

    _state = SignalingClientState.connecting;
    _emit('_state', SignalMessage(type: '_state', reason: _state.name));

    final wsUri = serverUri.replace(
      scheme: serverUri.scheme == 'https' || serverUri.scheme == 'wss' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: {
        'role': 'sender',
        'name': deviceName,
      },
    );

    try {
      final socket = await WebSocket.connect(wsUri.toString())
          .timeout(const Duration(seconds: 10));
      _socket = socket;
      _reconnectAttempts = 0;
      _state = SignalingClientState.authenticating;
      _emit('_state', SignalMessage(type: '_state', reason: _state.name));

      socket.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleMessage(dynamic data) {
    if (data is! String) return;
    final msg = SignalMessage.tryParse(data);
    if (msg == null) return;

    if (msg.type == 'challenge') {
      final salt = msg.payload is Map ? msg.payload['salt'] as String? : null;
      if (trustToken != null) {
        _rawSend(SignalMessage(type: 'trust', payload: {'token': trustToken}));
      } else if (salt != null) {
        final proof = PinProof.compute(pin, salt);
        _rawSend(SignalMessage(type: 'auth', payload: {'proof': proof}));
      }
      return;
    }

    if (msg.type == 'paired') {
      _senderId = msg.from;
      if (msg.payload is Map && msg.payload['token'] is String) {
        _issuedToken = msg.payload['token'] as String;
      }
      _state = SignalingClientState.paired;
      _emit('_state', SignalMessage(type: '_state', reason: _state.name));

      // Flush queued messages
      final pending = List<SignalMessage>.from(_sendQueue);
      _sendQueue.clear();
      for (final m in pending) {
        _rawSend(m);
      }
    }

    if (msg.type == 'error') {
      final reason = msg.reason ?? 'unknown';
      // Fatal errors should not trigger reconnect loops
      const fatalErrors = {'bad-pin', 'bad-token', 'room-full', 'rate-limited'};
      if (fatalErrors.contains(reason)) {
        _state = SignalingClientState.failed;
        _emit('_state', SignalMessage(type: '_state', reason: _state.name));
        close();
      }
    }

    _emit(msg.type, msg);
  }

  void _handleDisconnect() {
    _socket = null;
    if (_state == SignalingClientState.failed) {
      return;
    }
    if (_manuallyClosed) {
      _state = SignalingClientState.disconnected;
      _emit('_state', SignalMessage(type: '_state', reason: _state.name));
      return;
    }

    _state = SignalingClientState.disconnected;
    _emit('_state', SignalMessage(type: '_state', reason: _state.name));

    // Exponential backoff: min 500ms, max 8s
    final delayMs = min(500 * pow(2, _reconnectAttempts).toInt(), 8000);
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      connect();
    });
  }

  void send(SignalMessage msg) {
    if (_state == SignalingClientState.paired && _socket != null) {
      _rawSend(msg);
    } else {
      _sendQueue.add(msg);
    }
  }

  void _rawSend(SignalMessage msg) {
    try {
      _socket?.add(msg.encode());
    } catch (_) {}
  }

  void close() {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    if (_state != SignalingClientState.failed) {
      _state = SignalingClientState.disconnected;
    }
  }
}
