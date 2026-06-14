import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';

class SchoolSelectScreen extends ConsumerStatefulWidget {
  final String smsToken;
  const SchoolSelectScreen({super.key, required this.smsToken});

  @override
  ConsumerState<SchoolSelectScreen> createState() => _SchoolSelectScreenState();
}

class _SchoolSelectScreenState extends ConsumerState<SchoolSelectScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _schools = [];
  Map<String, dynamic>? _selected;
  int _grade = 1;
  int _classNum = 1;
  bool _searching = false;
  bool _registering = false;

  Future<void> _search() async {
    final keyword = _searchCtrl.text.trim();
    if (keyword.length < 2) return;
    setState(() => _searching = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/schools/search', queryParameters: {'keyword': keyword});
      setState(() => _schools = List<Map<String, dynamic>>.from(resp.data));
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _register() async {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학교를 선택해주세요.')),
      );
      return;
    }

    setState(() => _registering = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/parent/verify', data: {
        'sms_token': widget.smsToken,
        'school_code': _selected!['school_code'],
        'school_name': _selected!['school_name'],
        'grade': _grade,
        'class_num': _classNum,
        'school_type': _selected!['school_type'],
      });

      const storage = FlutterSecureStorage();
      await storage.write(key: AppConstants.tokenKey, value: resp.data['access_token']);
      await storage.write(key: AppConstants.refreshTokenKey, value: resp.data['refresh_token']);

      if (mounted) context.go('/board');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('등록 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('학교 선택')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(hintText: '학교명 검색 (2자 이상)'),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: _search, child: const Text('검색')),
            ]),
            const SizedBox(height: 12),
            if (_searching) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _schools.length,
                itemBuilder: (ctx, i) {
                  final s = _schools[i];
                  final isSelected = _selected?['school_code'] == s['school_code'];
                  return ListTile(
                    title: Text(s['school_name']),
                    subtitle: Text(s['address'] ?? ''),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                    onTap: () => setState(() => _selected = s),
                  );
                },
              ),
            ),
            if (_selected != null) ...[
              const Divider(),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _grade,
                    decoration: const InputDecoration(labelText: '학년'),
                    items: List.generate(6, (i) => i + 1)
                        .map((g) => DropdownMenuItem(value: g, child: Text('$g학년')))
                        .toList(),
                    onChanged: (v) => setState(() => _grade = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _classNum,
                    decoration: const InputDecoration(labelText: '반'),
                    items: List.generate(20, (i) => i + 1)
                        .map((c) => DropdownMenuItem(value: c, child: Text('$c반')))
                        .toList(),
                    onChanged: (v) => setState(() => _classNum = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _registering ? null : _register,
                child: _registering
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('학부모 인증 완료'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
