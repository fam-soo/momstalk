import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

class SmsVerifyScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  const SmsVerifyScreen({super.key, required this.phoneNumber});

  @override
  ConsumerState<SmsVerifyScreen> createState() => _SmsVerifyScreenState();
}

class _SmsVerifyScreenState extends ConsumerState<SmsVerifyScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('6자리 인증번호를 입력해주세요.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/sms/verify', data: {
        'phone_number': widget.phoneNumber,
        'code': code,
      });
      final smsToken = resp.data['sms_token'] as String;
      if (mounted) context.push('/auth/school', extra: smsToken);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증번호가 올바르지 않습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('인증번호 확인')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text('인증번호를 입력해주세요',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${widget.phoneNumber}으로 발송된 6자리 번호',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: '000000',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }
}
