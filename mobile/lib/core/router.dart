import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/auth/screens/phone_input_screen.dart';
import '../features/auth/screens/sms_verify_screen.dart';
import '../features/auth/screens/school_select_screen.dart';
import '../features/board/screens/board_screen.dart';
import '../features/board/screens/post_detail_screen.dart';
import '../features/board/screens/post_write_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import 'constants.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/board',
    redirect: (context, state) async {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: AppConstants.tokenKey);
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      if (token == null && !isAuthRoute) return '/auth/phone';
      if (token != null && isAuthRoute) return '/board';
      return null;
    },
    routes: [
      GoRoute(path: '/auth/phone', builder: (ctx, s) => const PhoneInputScreen()),
      GoRoute(
        path: '/auth/verify',
        builder: (ctx, s) => SmsVerifyScreen(phoneNumber: s.extra as String),
      ),
      GoRoute(
        path: '/auth/school',
        builder: (ctx, s) => SchoolSelectScreen(smsToken: s.extra as String),
      ),
      GoRoute(path: '/profile', builder: (ctx, s) => const ProfileScreen()),
      GoRoute(
        path: '/board',
        builder: (ctx, s) => const BoardScreen(),
        routes: [
          GoRoute(
            path: 'write',
            builder: (ctx, s) => PostWriteScreen(boardType: s.extra as String),
          ),
          GoRoute(
            path: ':postId',
            builder: (ctx, s) => PostDetailScreen(postId: int.parse(s.pathParameters['postId']!)),
          ),
        ],
      ),
    ],
  );
});
