import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../../core/api_client.dart' show dioProvider, tokenStorageProvider;
import '../../../core/constants.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;

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
      // ── 웹: 카카오 SDK 미지원 ────────────────────────────
      if (kIsWeb) {
        if (AppConstants.devMode) {
          // DEV 모드: 백엔드 dev endpoint로 lurker 로그인
          await _devLurkerLogin();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('카카오 로그인은 모바일 앱에서만 지원됩니다.')),
          );
        }
        return;
      }

      // ── 모바일: 카카오 SDK 사용 ──────────────────────────
      OAuthToken token;
      if (await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        // 카카오 콘솔에서 전화번호 동의항목을 필수로 설정해두면
        // 별도 scopes 지정 없이 자동으로 전화번호 동의 화면이 표시됨
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      final dio = ref.read(dioProvider);
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      onTap: _kakaoLogin,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE500),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble, size: 24, color: Color(0xFF3C1E1E)),
                            SizedBox(width: 8),
                            Text(
                              '카카오로 시작하기',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF3C1E1E)),
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
