import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'core/api_client.dart';
import 'core/constants.dart';
import 'core/router.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KakaoSdk.init(
    nativeAppKey: AppConstants.kakaoNativeAppKey,
    javaScriptAppKey: AppConstants.kakaoJavaScriptKey,
  );

  // Firebase 초기화 (google-services.json 없는 개발 환경에서는 무시)
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // mock 모드: 로그인 화면 없이 바로 앱 진입하도록 토큰 사전 주입
  if (AppConstants.mockMode) {
    await tokenStorage.write(AppConstants.tokenKey, 'mock_access_token_12345');
    await tokenStorage.write(AppConstants.refreshTokenKey, 'mock_refresh_token_67890');
  }

  runApp(const ProviderScope(child: MomsTalkApp()));
}

class MomsTalkApp extends ConsumerStatefulWidget {
  const MomsTalkApp({super.key});

  @override
  ConsumerState<MomsTalkApp> createState() => _MomsTalkAppState();
}

class _MomsTalkAppState extends ConsumerState<MomsTalkApp> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLink();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLink() async {
    final appLinks = AppLinks();

    // 앱이 종료된 상태에서 링크로 열린 경우
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (_) {}

    // 앱이 백그라운드 또는 포그라운드 상태에서 링크가 들어온 경우
    _linkSub = appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (_) {},
    );
  }

  void _handleDeepLink(Uri uri) {
    // momstalk://invite/{token}  또는  https://momstalk.kr/invite/{token}
    final pathSegments = uri.pathSegments;
    if (pathSegments.length >= 2 && pathSegments[0] == 'invite') {
      final token = pathSegments[1];
      // routerProvider가 준비된 후 이동
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(routerProvider).push('/invite/$token');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MomsTalk',
      theme: appTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: child!,
        ),
      ),
    );
  }
}
