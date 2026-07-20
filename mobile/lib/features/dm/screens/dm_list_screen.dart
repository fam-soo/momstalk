import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../core/api_client.dart' show dioProvider, tokenStorageProvider;
import '../../../core/kst_time.dart';
import '../../../core/constants.dart' show AppConstants;
import '../../../core/main_bottom_nav.dart';

class DmListScreen extends ConsumerStatefulWidget {
  const DmListScreen({super.key});

  @override
  ConsumerState<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends ConsumerState<DmListScreen> {
  List<Map<String, dynamic>> _convs = [];
  bool _loading = true;
  StreamSubscription<String>? _sseSub;

  @override
  void initState() {
    super.initState();
    _load();
    _connectSse();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/conversations');
      if (mounted) setState(() => _convs = List<Map<String, dynamic>>.from(resp.data));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectSse() async {
    final storage = ref.read(tokenStorageProvider);
    final token = await storage.read('access_token');
    if (token == null) return;

    // baseUrl은 '/api/v1'을 포함하므로 뒤에 '/stream'만 붙임
    final sseUrl = '${AppConstants.baseUrl}/stream';
    final uri = Uri.parse(sseUrl);
    final client = http.Client();

    _sseSub = _sseLines(client, uri, token).listen(
      (line) {
        if (!line.startsWith('data:')) return;
        final raw = line.substring(5).trim();
        if (raw.isEmpty || raw == '{"type": "connected"}') return;
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          if (data['type'] == 'new_message') {
            _load(); // 대화 목록 갱신 (unread_count 포함)
          }
        } catch (_) {}
      },
      onError: (_) async {
        // 연결 끊기면 5초 후 재시도
        await Future.delayed(const Duration(seconds: 5));
        if (mounted) _connectSse();
      },
    );
  }

  /// HTTP 스트림을 한 줄씩 yield하는 헬퍼 (SSE 파싱).
  Stream<String> _sseLines(http.Client client, Uri uri, String token) async* {
    final request = http.Request('GET', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    final response = await client.send(request);
    final buffer = StringBuffer();

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      final text = buffer.toString();
      final lines = text.split('\n');
      // 마지막 줄은 아직 미완성일 수 있으므로 보류
      buffer.clear();
      buffer.write(lines.last);
      for (final line in lines.sublist(0, lines.length - 1)) {
        yield line;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('대화')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _convs.isEmpty
              ? const Center(child: Text('대화 내역이 없어요', style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _convs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final c = _convs[i];
                      final unread = (c['unread_count'] ?? 0) as int;
                      final lastAtKst = parseServerTimeToKst(c['last_message_at'] as String?);
                      final lastAt = lastAtKst != null ? DateFormat('MM.dd HH:mm').format(lastAtKst) : '';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            (c['other_nickname'] as String? ?? '?').substring(0, 1),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Row(children: [
                          Text(c['other_nickname'] ?? '알 수 없음',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(lastAt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ]),
                        subtitle: Text(
                          c['last_message'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        trailing: unread > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('$unread',
                                    style: const TextStyle(color: Colors.white, fontSize: 11)),
                              )
                            : null,
                        onTap: () async {
                          await context.push('/dm/${c['id']}', extra: c['other_nickname']);
                          _load(); // 채팅방 나왔을 때 읽음 처리 반영
                        },
                      );
                    },
                  ),
                ),
      bottomNavigationBar: const MainBottomNav(),
    );
  }
}
