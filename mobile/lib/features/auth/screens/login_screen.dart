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
import '../../../core/saved_accounts.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  bool _agreed = false;
  bool _isAdult = false;
  List<SavedAccount> _savedAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await SavedAccountsStorage.load();
    if (mounted) setState(() => _savedAccounts = accounts);
  }

  Future<void> _removeAccount(SavedAccount account) async {
    await SavedAccountsStorage.remove(account.nickname);
    await _loadSavedAccounts();
  }

  /// 저장된 계정 탭 → 약관 동의 없이 바로 카카오 로그인
  /// Prompt.selectAccount: 기존 세션이 있어도 계정 선택 화면을 강제 표시
  Future<void> _quickLogin() async {
    setState(() => _loading = true);
    try {
      OAuthToken token;
      if (!kIsWeb && await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount(
          prompts: [Prompt.selectAccount],
        );
      }
      await _authenticateWithBackend(token);
    } catch (e) {
      if (mounted) _showKakaoError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _kakaoLogin() async {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이용약관 및 개인정보처리방침에 동의해주세요.')),
      );
      return;
    }
    if (!_isAdult) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('만 19세 이상 성인만 가입할 수 있습니다.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      OAuthToken token;
      if (!kIsWeb && await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount(
          prompts: [Prompt.selectAccount],
        );
      }
      await _authenticateWithBackend(token);
    } catch (e) {
      if (mounted) _showKakaoError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showKakaoError(String err) {
    String msg;
    if (err.contains('cancel') || err.contains('Cancel')) {
      msg = '카카오 로그인이 취소되었습니다.';
    } else if (err.contains('network') || err.contains('Network') || err.contains('SocketException')) {
      msg = '네트워크 연결을 확인해주세요.';
    } else {
      msg = '카카오 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
    );
  }

  Future<void> _authenticateWithBackend(OAuthToken token) async {
    final dio = ref.read(dioProvider);
    try {
      final resp = await dio.post('/auth/kakao', data: {'kakao_access_token': token.accessToken});

      final storage = ref.read(tokenStorageProvider);
      await storage.write(AppConstants.tokenKey, resp.data['access_token'] as String);
      await storage.write(AppConstants.refreshTokenKey, resp.data['refresh_token'] as String);

      final meResp = await dio.get('/auth/me');
      final data = meResp.data as Map<String, dynamic>;
      final memberGrade = data['member_grade'] as String? ?? 'lurker';
      final isAdmin = data['is_admin'] as bool? ?? false;

      // 로그인 성공 시 계정 정보 저장
      await SavedAccountsStorage.upsert(SavedAccount(
        nickname: data['nickname'] as String? ?? '',
        schoolName: data['school_name'] as String? ?? '',
        memberGrade: memberGrade,
      ));

      if (!mounted) return;
      if (memberGrade == 'member' || isAdmin) {
        context.go('/region');
      } else {
        context.go('/auth/pending');
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 403) {
        final detail = e.response?.data?['detail'] as String? ?? '가입이 제한된 계정입니다.';
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('로그인 불가'),
              content: Text(detail),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
            ),
          );
        }
        return;
      }
      if (statusCode == 429) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('잠시 후 다시 시도해주세요. (요청 횟수 초과)')),
          );
        }
        return;
      }
      rethrow;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final hasSavedAccounts = _savedAccounts.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Icon(Icons.family_restroom, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'MomsTalk',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('학부모 전용 익명 커뮤니티', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 36),

              // ── 저장된 계정 목록 ─────────────────────────────
              if (hasSavedAccounts) ...[
                Text('계정 선택', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                ...(_savedAccounts.map((account) => _AccountTile(
                  account: account,
                  onTap: _loading ? null : _quickLogin,
                  onRemove: () => _removeAccount(account),
                ))),
                const SizedBox(height: 16),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('다른 계정으로 로그인', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 16),
              ],

              // ── 약관 동의 (신규 가입자용) ─────────────────────
              if (!hasSavedAccounts) ...[
                _CheckRow(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      children: [
                        const TextSpan(text: '(필수) '),
                        TextSpan(
                          text: '이용약관',
                          style: const TextStyle(color: Color(0xFF4A90D9), decoration: TextDecoration.underline),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => launchUrl(Uri.parse(AppConstants.termsOfServiceUrl), mode: LaunchMode.externalApplication),
                        ),
                        const TextSpan(text: ' 및 '),
                        TextSpan(
                          text: '개인정보처리방침',
                          style: const TextStyle(color: Color(0xFF4A90D9), decoration: TextDecoration.underline),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => launchUrl(Uri.parse(AppConstants.privacyPolicyUrl), mode: LaunchMode.externalApplication),
                        ),
                        const TextSpan(text: '에 동의합니다.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _CheckRow(
                  value: _isAdult,
                  onChanged: (v) => setState(() => _isAdult = v ?? false),
                  child: const Text('(필수) 본인은 만 19세 이상 성인입니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(height: 12),
              ],

              // ── 카카오 로그인 버튼 ────────────────────────────
              _loading
                  ? const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 14), child: CircularProgressIndicator()))
                  : GestureDetector(
                      onTap: hasSavedAccounts ? _quickLogin : _kakaoLogin,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: (!hasSavedAccounts && (!_agreed || !_isAdult))
                              ? Colors.grey.shade300
                              : const Color(0xFFFEE500),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble,
                              size: 22,
                              color: (!hasSavedAccounts && (!_agreed || !_isAdult))
                                  ? Colors.grey
                                  : const Color(0xFF3C1E1E),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hasSavedAccounts ? '카카오로 로그인' : '카카오로 시작하기',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: (!hasSavedAccounts && (!_agreed || !_isAdult))
                                    ? Colors.grey
                                    : const Color(0xFF3C1E1E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

              // 저장 계정 있을 때 약관은 접혀 있음 — 처음 가입한 게 아니므로 생략
              if (hasSavedAccounts) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _savedAccounts = [];  // 임시로 숨겨서 신규 가입 폼 표시
                    }),
                    child: const Text('처음 가입하시나요?', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              if (AppConstants.devMode && !_loading)
                TextButton(
                  onPressed: _devLurkerLogin,
                  child: const Text('[DEV] 백엔드 연결 lurker 로그인', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 저장된 계정 타일 ──────────────────────────────────────────────

class _AccountTile extends StatelessWidget {
  final SavedAccount account;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  const _AccountTile({required this.account, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isMember = account.memberGrade == 'member';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isMember
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.grey.shade200,
                child: Icon(
                  Icons.person,
                  size: 20,
                  color: isMember
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(
                      account.displaySchool,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
                onPressed: onRemove,
                tooltip: '계정 목록에서 제거',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 체크박스 행 헬퍼 ─────────────────────────────────────────────

class _CheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final Widget child;

  const _CheckRow({required this.value, required this.onChanged, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(value: value, onChanged: onChanged, visualDensity: VisualDensity.compact),
        Expanded(child: child),
      ],
    );
  }
}
