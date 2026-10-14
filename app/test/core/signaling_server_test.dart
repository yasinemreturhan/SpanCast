import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:doscreen/core/client/signaling_client.dart';
import 'package:doscreen/core/protocol/models.dart';
import 'package:doscreen/core/server/signaling_server.dart';

void main() {
  late SignalingServer server;

  setUp(() async {
    // Port 0 picks an available ephemeral port
    server = SignalingServer(name: 'TestHost', requestedPort: 0);
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  test('server starts, responds to healthz and api/info', () async {
    final client = HttpClient();
    final healthReq = await client.get('localhost', server.port, '/healthz');
    final healthRes = await healthReq.close();
    expect(healthRes.statusCode, HttpStatus.ok);

    final infoReq = await client.get('localhost', server.port, '/api/info');
    final infoRes = await infoReq.close();
    expect(infoRes.statusCode, HttpStatus.ok);
    client.close();
  });

  test('end-to-end receiver and sender pairing flow', () async {
    final receiverSocket = await WebSocket.connect('ws://localhost:${server.port}/ws?role=receiver');
    
    // 1. Receiver gets PIN
    final receiverPinCompleter = Completer<SignalMessage>();
    final receiverJoinedCompleter = Completer<SignalMessage>();
    final receiverOfferCompleter = Completer<SignalMessage>();

    receiverSocket.listen((data) {
      final msg = SignalMessage.tryParse(data as String);
      if (msg?.type == 'pin') receiverPinCompleter.complete(msg);
      if (msg?.type == 'joined') receiverJoinedCompleter.complete(msg);
      if (msg?.type == 'offer') receiverOfferCompleter.complete(msg);
    });

    final pinMsg = await receiverPinCompleter.future.timeout(const Duration(seconds: 3));
    final pin = pinMsg.pin!;
    expect(pin, matches(r'^\d{6}$'));

    // 2. Sender connects with PIN
    final senderClient = SignalingClient(
      serverUri: Uri.parse('http://localhost:${server.port}'),
      deviceName: 'SenderMac',
      pin: pin,
    );

    final senderPairedCompleter = Completer<void>();
    final senderAnswerCompleter = Completer<SignalMessage>();

    senderClient.on('paired', (_) => senderPairedCompleter.complete());
    senderClient.on('answer', (msg) => senderAnswerCompleter.complete(msg));

    await senderClient.connect();
    await senderPairedCompleter.future.timeout(const Duration(seconds: 3));
    expect(senderClient.state, SignalingClientState.paired);
    expect(senderClient.issuedToken, isNotNull);

    // 3. Receiver should have received 'joined'
    final joinedMsg = await receiverJoinedCompleter.future.timeout(const Duration(seconds: 3));
    expect(joinedMsg.name, 'SenderMac');

    // 4. Sender sends offer -> receiver receives it
    senderClient.send(const SignalMessage(type: 'offer', payload: {'sdp': 'test-offer'}));
    final offerMsg = await receiverOfferCompleter.future.timeout(const Duration(seconds: 3));
    expect(offerMsg.payload['sdp'], 'test-offer');

    // 5. Receiver sends answer back -> sender receives it
    receiverSocket.add(SignalMessage(
      type: 'answer',
      to: offerMsg.from,
      payload: {'sdp': 'test-answer'},
    ).encode());

    final answerMsg = await senderAnswerCompleter.future.timeout(const Duration(seconds: 3));
    expect(answerMsg.payload['sdp'], 'test-answer');

    // Clean up
    senderClient.close();
    await receiverSocket.close();
  });

  test('sender with wrong PIN receives bad-pin error and fails without retry', () async {
    final receiverSocket = await WebSocket.connect('ws://localhost:${server.port}/ws?role=receiver');
    
    final senderClient = SignalingClient(
      serverUri: Uri.parse('http://localhost:${server.port}'),
      deviceName: 'SenderAttacker',
      pin: '000000', // Invalid PIN
    );

    final errorCompleter = Completer<String>();
    senderClient.on('error', (msg) => errorCompleter.complete(msg.reason ?? ''));

    await senderClient.connect();
    final errorReason = await errorCompleter.future.timeout(const Duration(seconds: 3));
    expect(errorReason, 'bad-pin');
    expect(senderClient.state, SignalingClientState.failed);

    senderClient.close();
    await receiverSocket.close();
  });

  test('trusted device can connect using trust token without PIN', () async {
    final receiverSocket = await WebSocket.connect('ws://localhost:${server.port}/ws?role=receiver');
    final pinMsgCompleter = Completer<SignalMessage>();
    receiverSocket.listen((data) {
      final msg = SignalMessage.tryParse(data as String);
      if (msg?.type == 'pin') pinMsgCompleter.complete(msg);
    });

    final pinMsg = await pinMsgCompleter.future.timeout(const Duration(seconds: 3));

    // First sender pairs with PIN to get token
    final s1 = SignalingClient(
      serverUri: Uri.parse('http://localhost:${server.port}'),
      deviceName: 'Laptop',
      pin: pinMsg.pin!,
    );
    final s1Paired = Completer<void>();
    s1.on('paired', (_) => s1Paired.complete());
    await s1.connect();
    await s1Paired.future.timeout(const Duration(seconds: 3));
    final token = s1.issuedToken!;
    expect(token, isNotEmpty);
    s1.close();

    // Second connection uses trust token directly (PIN not needed!)
    final s2 = SignalingClient(
      serverUri: Uri.parse('http://localhost:${server.port}'),
      deviceName: 'Laptop',
      pin: '000000', // Dummy PIN because trust token is provided
      trustToken: token,
    );
    final s2Paired = Completer<void>();
    s2.on('paired', (_) => s2Paired.complete());
    await s2.connect();
    await s2Paired.future.timeout(const Duration(seconds: 3));
    expect(s2.state, SignalingClientState.paired);

    s2.close();
    await receiverSocket.close();
  });
}
