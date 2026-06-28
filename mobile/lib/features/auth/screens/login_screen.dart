import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart' show dioProvider, tokenStorageProvider;
import '../../../core/constants.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  bool _agreed = false;
  bool _isAdult = false;

  /// 개발 전용: 백엔드 /auth/dev/lurker-login 호출 → 실제 JWT 저장 → /board 진입
  Future<void> _devLurkerLogin() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/dev/lurker-login');
      final storage = ref.read(tokenStorageProvider);
      await storage.write(AppConstants.tokenKey, resp.data['access_token'] as String);
      await storage.write(AppConstants.refreshTokenKey, resp.data['refresh_token'] as String);
      if (mounted) context.go('/board');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DEV 로그인 실패: $e\n(Docker 백엔드 실행 여부 확인)')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _kakaoLogin() async {
    setState(() => _loading = true);
    try {
      if (!_agreed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이용약관 및 개인정보처리방침에 동의해주세요.')),
        );
        setState(() => _loading = false);
        return;
      }
      if (!_isAdult) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('만 19세 이상 성인만 가입할 수 있습니다.')),
        );
        setState(() => _loading = false);
        return;
      }

      // ── 모바일: 카카오 SDK ──────────────────────────
      OAuthToken token;
      if (await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      await _authenticateWithBackend(token);
    } catch (e) {
      if (mounted) {
        final msg = '로그인 실패: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 카카오 토큰으로 백엔드 인증. 전화번호 동의 미완료 시 추가 동의 요청 후 재시도.
  Future<void> _authenticateWithBackend(OAuthToken token) async {
    final dio = ref.read(dioProvider);
    try {
      final resp = await dio.post('/auth/kakao', data: {'kakao_access_token': token.accessToken});

      final storage = ref.read(tokenStorageProvider);
      await storage.write(AppConstants.tokenKey, resp.data['access_token'] as String);
      await storage.write(AppConstants.refreshTokenKey, resp.data['refresh_token'] as String);

      final meResp = await dio.get('/auth/me');
      final authPending = meResp.data['auth_pending'] as bool? ?? false;

      if (!mounted) return;
      if (authPending) {
        context.go('/auth/pending');
      } else {
        context.go('/board');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        final detail = e.response?.data?['detail'] as String? ?? '가입이 제한된 계정입니다.';
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('가입 불가'),
              content: Text(detail),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
        }
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.family_restroom, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'MomsTalk',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '학부모 전용 익명 커뮤니티',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const Spacer(),
              // ── 약관 동의 체크박스 ──────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        children: [
                          const TextSpan(text: '(필수) '),
                          TextSpan(
                            text: '이용약관',
                            style: const TextStyle(
                              color: Color(0xFF4A90D9),
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => launchUrl(
                                    Uri.parse(AppConstants.termsOfServiceUrl),
                                    mode: LaunchMode.externalApplication,
                                  ),
                          ),
                          const TextSpan(text: ' 및 '),
                          TextSpan(
                            text: '개인정보처리방침',
                            style: const TextStyle(
                              color: Color(0xFF4A90D9),
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => launchUrl(
                                    Uri.parse(AppConstants.privacyPolicyUrl),
                                    mode: LaunchMode.externalApplication,
                                  ),
                          ),
                          const TextSpan(text: '에 동의합니다.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ── 성인 확인 체크박스 ──────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _isAdult,
                    onChanged: (v) => setState(() => _isAdult = v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  const Expanded(
                    child: Text(
                      '(필수) 본인은 만 19세 이상 성인입니다.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      onTap: _kakaoLogin,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: (_agreed && _isAdult) ? const Color(0xFFFEE500) : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble, size: 24,
                                color: (_agreed && _isAdult) ? const Color(0xFF3C1E1E) : Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              '카카오로 시작하기',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: (_agreed && _isAdult) ? const Color(0xFF3C1E1E) : Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
              const SizedBox(height: 16),
              // DEV 버튼: 백엔드 dev endpoint → lurker 로그인
              if (AppConstants.devMode && !_loading)
                TextButton(
                  onPressed: _devLurkerLogin,
                  child: const Text('[DEV] 백엔드 연결 lurker 로그인', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              if (AppConstants.devMode)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Docker 백엔드 실행 필요: docker-compose up -d',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                  ),
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
