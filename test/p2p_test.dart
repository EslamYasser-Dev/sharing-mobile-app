import 'package:flutter_test/flutter_test.dart';
import 'package:simplefileshare/src/models.dart';
import 'package:simplefileshare/src/services/p2p_session.dart';
import 'package:simplefileshare/src/services/p2p_signaling.dart';

void main() {
  group('SseParser', () {
    test('emits a named event with its data', () {
      final parser = SseParser();
      final frames = parser.feed('event: hello\ndata: {"type":"hello"}\n\n');
      expect(frames, hasLength(1));
      expect(frames.single.event, 'hello');
      expect(frames.single.data, '{"type":"hello"}');
    });

    test('holds a frame open across chunk boundaries', () {
      final parser = SseParser();
      expect(parser.feed('event: signal\ndata: {"a"'), isEmpty);
      expect(parser.feed(':1}'), isEmpty);
      final frames = parser.feed('\n\n');
      expect(frames, hasLength(1));
      expect(frames.single.event, 'signal');
      expect(frames.single.data, '{"a":1}');
    });

    test('ignores comment heartbeats', () {
      final parser = SseParser();
      expect(parser.feed(': connected\n\n'), isEmpty);
      expect(parser.feed(': ping\n\n'), isEmpty);
    });

    test('joins multiple data lines with a newline', () {
      final frames = SseParser().feed('data: one\ndata: two\n\n');
      expect(frames.single.data, 'one\ntwo');
    });

    test('handles CRLF line endings', () {
      final frames = SseParser().feed('event: peers\r\ndata: x\r\n\r\n');
      expect(frames.single.event, 'peers');
      expect(frames.single.data, 'x');
    });

    test('defaults the event name to message', () {
      final frames = SseParser().feed('data: x\n\n');
      expect(frames.single.event, 'message');
    });

    test('does not dispatch a frame with no data', () {
      expect(SseParser().feed('event: bye\n\n'), isEmpty);
    });

    test('ignores id and retry fields', () {
      final frames = SseParser().feed('id: 7\nretry: 100\ndata: x\n\n');
      expect(frames.single.data, 'x');
    });

    test('emits several frames from one chunk', () {
      final frames = SseParser().feed(
        'event: peers\ndata: {"type":"peers"}\n\n'
        'event: hello\ndata: {"type":"hello"}\n\n',
      );
      expect(frames.map((f) => f.event), ['peers', 'hello']);
    });
  });

  group('p2pFrameFromSse', () {
    test('decodes a hello frame with its peer id and peer list', () {
      final frame = p2pFrameFromSse(
        const SseFrame(
          event: 'hello',
          data:
              '{"type":"hello","peerId":"abc",'
              '"peers":[{"id":"p1","user":"eve"},{"id":"p2"}]}',
        ),
      );
      expect(frame, isNotNull);
      expect(frame!.type, 'hello');
      expect(frame.peerId, 'abc');
      expect(frame.peers, hasLength(2));
      expect(frame.peers.first.user, 'eve');
      expect(frame.peers.last.user, isNull);
    });

    test('decodes a signal frame into a typed kind', () {
      final frame = p2pFrameFromSse(
        const SseFrame(
          event: 'signal',
          data:
              '{"type":"signal","signal":{"from":"a","to":"b",'
              '"kind":"candidate","payload":{"candidate":"cand",'
              '"sdpMid":"0","sdpMLineIndex":0}}}',
        ),
      );
      expect(frame, isNotNull);
      final signal = frame!.signal;
      expect(signal, isNotNull);
      expect(signal!.kind, P2PSignalKind.candidate);
      expect(signal.from, 'a');
      expect(signal.to, 'b');
      expect(signal.payload, isA<Map<String, dynamic>>());
    });

    test('returns null for malformed JSON', () {
      expect(
        p2pFrameFromSse(const SseFrame(event: 'peers', data: '{oops')),
        isNull,
      );
    });

    test('returns null for a non-object payload', () {
      expect(
        p2pFrameFromSse(const SseFrame(event: 'peers', data: '[1,2]')),
        isNull,
      );
      expect(p2pFrameFromSse(const SseFrame(event: 'x', data: '')), isNull);
    });

    test('returns null for a signal kind it does not know', () {
      final frame = p2pFrameFromSse(
        const SseFrame(
          event: 'signal',
          data: '{"type":"signal","signal":{"from":"a","to":"b","kind":"zz"}}',
        ),
      );
      expect(frame, isNull);
    });

    test('still decodes a peers frame with no peers', () {
      final frame = p2pFrameFromSse(
        const SseFrame(event: 'peers', data: '{"type":"peers"}'),
      );
      expect(frame, isNotNull);
      expect(frame!.peers, isEmpty);
    });
  });

  group('p2pSignalKindFrom', () {
    test('maps every wire value', () {
      expect(p2pSignalKindFrom('offer'), P2PSignalKind.offer);
      expect(p2pSignalKindFrom('answer'), P2PSignalKind.answer);
      expect(p2pSignalKindFrom('candidate'), P2PSignalKind.candidate);
      expect(p2pSignalKindFrom('bye'), P2PSignalKind.bye);
    });

    test('rejects anything else', () {
      expect(p2pSignalKindFrom(''), isNull);
      expect(p2pSignalKindFrom('renegotiate'), isNull);
      expect(p2pSignalKindFrom('OFFER'), isNull);
    });
  });

  group('P2PControlMessage', () {
    test('round-trips a meta frame', () {
      const meta = P2PControlMessage(
        type: 'meta',
        id: 't1',
        name: 'notes.txt',
        size: 4096,
        mime: 'text/plain',
      );
      final json = meta.toJson();
      expect(json['t'], 'meta');
      expect(json['size'], 4096);

      final back = P2PControlMessage.fromJson(json);
      expect(back.type, 'meta');
      expect(back.id, 't1');
      expect(back.name, 'notes.txt');
      expect(back.size, 4096);
      expect(back.mime, 'text/plain');
    });

    test('omits absent fields rather than emitting nulls', () {
      const end = P2PControlMessage(type: 'end', id: 't1');
      final json = end.toJson();
      expect(json.keys, ['t', 'id']);
      expect(P2PControlMessage.fromJson(json).size, isNull);
    });
  });

  group('P2PTransfer', () {
    P2PTransfer build({
      int size = 100,
      P2PTransferStatus status = P2PTransferStatus.connecting,
    }) => P2PTransfer(
      id: 't',
      peerId: 'p',
      name: 'f.bin',
      size: size,
      direction: P2PTransferDirection.send,
      status: status,
    );

    test('reports progress across the transfer', () {
      expect(build().progress, 0);
      expect(build().copyWith(loaded: 50).progress, closeTo(0.5, 1e-9));
      expect(build().copyWith(loaded: 100).progress, 1);
    });

    test('treats a zero-byte file as empty until it completes', () {
      expect(build(size: 0).progress, 0);
      expect(build(size: 0).isComplete, isFalse);
      expect(build(size: 0, status: P2PTransferStatus.done).progress, 1);
      expect(build(size: 0, status: P2PTransferStatus.done).isComplete, isTrue);
    });

    test('never reports more than 100 percent', () {
      expect(build().copyWith(loaded: 500).progress, 1);
    });

    test('copyWith preserves identity fields and updates the rest', () {
      final base = build();
      final next = base.copyWith(
        loaded: 10,
        status: P2PTransferStatus.active,
        error: 'boom',
      );
      expect(next.id, base.id);
      expect(next.peerId, base.peerId);
      expect(next.name, base.name);
      expect(next.size, base.size);
      expect(next.direction, base.direction);
      expect(next.loaded, 10);
      expect(next.status, P2PTransferStatus.active);
      expect(next.error, 'boom');
    });
  });

  group('p2pSafeFileName', () {
    test('keeps an ordinary name', () {
      expect(p2pSafeFileName('report.pdf'), 'report.pdf');
      expect(p2pSafeFileName('  report.pdf  '), 'report.pdf');
    });

    test('strips directory components from either separator', () {
      expect(p2pSafeFileName('../../etc/passwd'), 'passwd');
      expect(p2pSafeFileName('/etc/shadow'), 'shadow');
      expect(p2pSafeFileName(r'C:\Users\me\notes.txt'), 'notes.txt');
      expect(p2pSafeFileName('a/b/c.txt'), 'c.txt');
    });

    test('falls back for empty and traversal-only names', () {
      expect(p2pSafeFileName(''), 'received.bin');
      expect(p2pSafeFileName('   '), 'received.bin');
      expect(p2pSafeFileName('..'), 'received.bin');
      expect(p2pSafeFileName('../..'), 'received.bin');
      expect(p2pSafeFileName('.'), 'received.bin');
    });
  });
}
