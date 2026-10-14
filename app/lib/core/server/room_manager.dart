import 'dart:math';
import '../protocol/proof.dart';

class RoomNotFoundException implements Exception {
  final String message;
  const RoomNotFoundException([this.message = 'Room not found']);
  @override
  String toString() => message;
}

class RoomExpiredException implements Exception {
  final String message;
  const RoomExpiredException([this.message = 'PIN expired']);
  @override
  String toString() => message;
}

class RoomFullException implements Exception {
  final String message;
  const RoomFullException([this.message = 'Room is full (max 4 senders)']);
  @override
  String toString() => message;
}

class Sender {
  final String id;
  final String name;

  const Sender({required this.id, required this.name});
}

class Room {
  final String id;
  String _pin;
  DateTime _created;
  bool _everHadSenders = false;
  int _nextSeq = 0;
  final Map<String, Sender> _senders = {};

  static const Duration pinTtl = Duration(minutes: 2);
  static const int maxSenders = 4;

  Room({required this.id, required String pin, DateTime? created})
      : _pin = pin,
        _created = created ?? DateTime.now();

  String get pin => _pin;
  DateTime get created => _created;
  List<Sender> get senders => List.unmodifiable(_senders.values);
  int get senderCount => _senders.length;

  bool isExpired([DateTime? now]) {
    final currentTime = now ?? DateTime.now();
    return !_everHadSenders && currentTime.difference(_created) > pinTtl;
  }

  void updatePin(String newPin, [DateTime? now]) {
    _pin = newPin;
    _created = now ?? DateTime.now();
  }

  Sender addSender(String name) {
    if (_senders.length >= maxSenders) {
      throw const RoomFullException();
    }
    _nextSeq++;
    final sender = Sender(id: 's$_nextSeq', name: name);
    _senders[sender.id] = sender;
    _everHadSenders = true;
    return sender;
  }

  void removeSender(String id) {
    _senders.remove(id);
  }
}

class RoomManager {
  final Map<String, Room> _byPin = {};
  final Map<String, Room> _trustTokens = {};
  final Random _random;

  RoomManager({Random? random}) : _random = random ?? Random.secure();

  String _randomPin() {
    final n = _random.nextInt(1000000);
    return n.toString().padLeft(6, '0');
  }

  String _randomId(String prefix) {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$prefix-$hex';
  }

  Room createRoom() {
    final id = _randomId('room');
    while (true) {
      final pin = _randomPin();
      if (!_byPin.containsKey(pin)) {
        final room = Room(id: id, pin: pin);
        _byPin[pin] = room;
        return room;
      }
    }
  }

  Room join(String pin, [DateTime? now]) {
    final room = _byPin[pin];
    if (room == null) {
      throw const RoomNotFoundException();
    }
    if (room.isExpired(now)) {
      _byPin.remove(pin);
      throw const RoomExpiredException();
    }
    return room;
  }

  String regenerate(Room room, [DateTime? now]) {
    _byPin.remove(room.pin);
    while (true) {
      final pin = _randomPin();
      if (!_byPin.containsKey(pin)) {
        room.updatePin(pin, now);
        _byPin[pin] = room;
        return pin;
      }
    }
  }

  void close(Room room) {
    _byPin.remove(room.pin);
    _trustTokens.removeWhere((_, r) => r == room);
  }

  Room? findByProof(String saltHex, String proof) {
    for (final room in _byPin.values) {
      final expected = PinProof.compute(room.pin, saltHex);
      if (PinProof.constantTimeEquals(expected, proof)) {
        return room;
      }
    }
    return null;
  }

  String issueTrustToken(Room room) {
    final token = _randomId('tok');
    _trustTokens[token] = room;
    return token;
  }

  Room? findByTrustToken(String token) {
    return _trustTokens[token];
  }
}
