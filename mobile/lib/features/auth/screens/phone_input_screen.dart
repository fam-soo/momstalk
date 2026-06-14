import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  Future<void> _sendCode() async {
    final phone = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 휴대폰 번호를 입력해주세요.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/sms/send', data: {'phone_number': phone});
      if (mounted) context.push('/auth/verify', extra: phone);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('전송 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _devLogin() async {
    final phone = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('테스트용 전화번호를 입력해주세요.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/dev/login', data: {
        'phone_number': phone,
        'school_code': 'TEST001',
        'school_name': '테스트초등학교',
        'grade': 1,
        'class_num': 1,
        'school_type': 'elementary',
      });

      const storage = FlutterSecureStorage();
      await storage.write(key: AppConstants.tokenKey, value: resp.data['access_token']);
      await storage.write(key: AppConstants.refreshTokenKey, value: resp.data['refresh_token']);

      if (mounted) context.go('/board');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('개발 로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MomsTalk')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text('휴대폰 번호를 입력해주세요',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('본인 확인 후 익명으로 활동합니다.\n번호는 서비스에 저장되지 않습니다.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '010-0000-0000',
                prefixIcon: Icon(Icons.phone_android),
              ),
              onSubmitted: (_) => _sendCode(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _sendCode,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('인증번호 받기'),
            ),
            if (AppConstants.devMode) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _devLogin,
                icon: const Icon(Icons.developer_mode, size: 18),
                label: const Text('[DEV] 인증 없이 바로 로그인'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
