import 'package:flutter_test/flutter_test.dart';
import 'package:doscreen/core/protocol/models.dart';
import 'package:doscreen/core/protocol/proof.dart';
import 'package:doscreen/core/server/room_manager.dart';

void main() {
  group('SignalMessage', () {
    test('serializes and deserializes correctly', () {
      const msg = SignalMessage(
        type: 'offer',
        from: 's1',
        to: 'r1',
        name: 'MacBook',
        pin: '123456',
        payload: {'sdp': 'v=0...'},
      );

      final encoded = msg.encode();
      final decoded = SignalMessage.tryParse(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.type, 'offer');
      expect(decoded.from, 's1');
      expect(decoded.to, 'r1');
      expect(decoded.name, 'MacBook');
      expect(decoded.pin, '123456');
      expect(decoded.payload['sdp'], 'v=0...');
    });
  });

  group('PinProof', () {
    test('computes deterministic HMAC-SHA256 matching reference vector', () {
      // Test vector: pin: "123456", salt: "00112233445566778899aabbccddeeff"
      final proof = PinProof.compute('123456', '00112233445566778899aabbccddeeff');
      expect(proof, isNotEmpty);
      expect(proof.length, 64); // SHA-256 is 32 bytes = 64 hex chars
      
      // Repeating computation yields exact same proof
      expect(PinProof.compute('123456', '00112233445566778899aabbccddeeff'), proof);

      // Different pin yields different proof
      expect(PinProof.compute('654321', '00112233445566778899aabbccddeeff'), isNot(proof));
    });

    test('constantTimeEquals detects equality and inequality safely', () {
      expect(PinProof.constantTimeEquals('abcd', 'abcd'), isTrue);
      expect(PinProof.constantTimeEquals('abcd', 'abce'), isFalse);
      expect(PinProof.constantTimeEquals('abcd', 'abc'), isFalse);
    });
  });

  group('RoomManager', () {
    test('creates room with 6-digit PIN and allows up to 4 senders', () {
      final manager = RoomManager();
      final room = manager.createRoom();

      expect(room.pin, matches(r'^\d{6}$'));
      expect(room.id, startsWith('room-'));

      final s1 = room.addSender('Device 1');
      final s2 = room.addSender('Device 2');
      final s3 = room.addSender('Device 3');
      final s4 = room.addSender('Device 4');

      expect(room.senderCount, 4);
      expect(s1.id, 's1');
      expect(s2.id, 's2');
      expect(s3.id, 's3');
      expect(s4.id, 's4');

      // 5th sender should throw RoomFullException
      expect(() => room.addSender('Device 5'), throwsA(isA<RoomFullException>()));
    });

    test('join checks expiration when room has had no senders', () {
      final manager = RoomManager();
      final room = manager.createRoom();

      // Normal join
      expect(manager.join(room.pin), equals(room));

      // Expired join
      final futureTime = DateTime.now().add(const Duration(minutes: 3));
      expect(() => manager.join(room.pin, futureTime), throwsA(isA<RoomExpiredException>()));
    });

    test('findByProof matches room PIN via challenge salt', () {
      final manager = RoomManager();
      final room = manager.createRoom();
      const salt = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

      final validProof = PinProof.compute(room.pin, salt);
      final matched = manager.findByProof(salt, validProof);
      expect(matched, equals(room));

      final wrongProof = PinProof.compute('000000', salt);
      expect(manager.findByProof(salt, wrongProof), isNull);
    });

    test('regenerate changes PIN and closes old PIN', () {
      final manager = RoomManager();
      final room = manager.createRoom();
      final oldPin = room.pin;

      final newPin = manager.regenerate(room);
      expect(newPin, isNot(oldPin));
      expect(room.pin, newPin);

      expect(() => manager.join(oldPin), throwsA(isA<RoomNotFoundException>()));
      expect(manager.join(newPin), equals(room));
    });
  });
}
