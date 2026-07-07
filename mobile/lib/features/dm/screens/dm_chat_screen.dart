import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/kst_time.dart';

class DmChatScreen extends ConsumerStatefulWidget {
  final int convId;
  final String otherNickname;
  const DmChatScreen({super.key, required this.convId, required this.otherNickname});

  @override
  ConsumerState<DmChatScreen> createState() => _DmChatScreenState();
}

class _DmChatScreenState extends ConsumerState<DmChatScreen> {
  List<Map<String, dynamic>> _msgs = [];
  int? _myId;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/conversations/${widget.convId}/messages'),
        dio.get('/auth/me'),
      ]);
      setState(() {
        _msgs = List<Map<String, dynamic>>.from(results[0].data);
        _myId = results[1].data['id'] as int?;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/conversations/${widget.convId}/messages', data: {'content': text});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('전송 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherNickname)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _msgs.length,
                  itemBuilder: (ctx, i) {
                    final m = _msgs[i];
                    final isMine = m['sender_id'] == _myId;
                    final msgKst = parseServerTimeToKst(m['created_at'] as String?);
                    final time = msgKst != null ? DateFormat('HH:mm').format(msgKst) : '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMine) ...[
                            CircleAvatar(radius: 14, backgroundColor: Colors.grey[200], child: const Icon(Icons.person, size: 14, color: Colors.grey)),
                            const SizedBox(width: 8),
                          ],
                          Column(
                            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.65),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMine ? Theme.of(context).colorScheme.primary : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(18).copyWith(
                                    bottomRight: isMine ? const Radius.circular(4) : null,
                                    bottomLeft: !isMine ? const Radius.circular(4) : null,
                                  ),
                                ),
                                child: Text(
                                  m['content'] ?? '',
                                  style: TextStyle(fontSize: 14, color: isMine ? Colors.white : Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(time, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        decoration: const InputDecoration(hintText: '메시지 입력', isDense: true, border: OutlineInputBorder()),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _send,
                        child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.send, color: Colors.white, size: 20)),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}
