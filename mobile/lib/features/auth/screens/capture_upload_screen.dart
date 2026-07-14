import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import '../../board/screens/board_screen.dart' show userProfileProvider;

class CaptureUploadScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> schoolInfo;
  /// 'initial': 최초 가입 인증 → /auth/pending으로 이동
  /// 'child_add': 자녀 추가 인증 → 완료 메시지 후 pop(true)
  final String captureType;
  const CaptureUploadScreen({
    super.key,
    required this.schoolInfo,
    this.captureType = 'initial',
  });

  @override
  ConsumerState<CaptureUploadScreen> createState() => _CaptureUploadScreenState();
}

class _CaptureUploadScreenState extends ConsumerState<CaptureUploadScreen> {
  XFile? _pickedFile;
  Uint8List? _imageBytes;
  bool _uploading = false;

  // 날짜 포맷: intl 없이 직접 처리 (로케일 의존 제거)
  String _fmt(DateTime d) => '${d.month}/${d.day}';

  String get _recentDateRange {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return '${_fmt(weekAgo)}~${_fmt(now)}';
  }

  List<String> get _exampleDocs {
    final now = DateTime.now();
    String d(int daysAgo) => _fmt(now.subtract(Duration(days: daysAgo)));
    return [
      '가정통신문 (${d(1)} 발송)',
      '알림장 — ${d(0)}자 선생님 메모',
      '급식 안내 (${d(2)}~${d(0)})',
      '학교 공지사항 (${d(3)} 발송)',
      '학년 행사 안내문 (${d(5)} 발송)',
      '${widget.schoolInfo['school_name'] ?? '학교'} 학부모 공지 (${d(1)})',
    ];
  }

  static const _allowedExtensions = {'jpg', 'jpeg', 'png', 'heic', 'heif'};

  String _mimeFromName(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'png': return 'image/png';
      case 'heic': return 'image/heic';
      case 'heif': return 'image/heif';
      default: return 'image/jpeg';
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1600,
      imageQuality: 75,
    );
    if (picked == null) return;
    final ext = picked.name.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JPG, PNG, HEIC 파일만 업로드할 수 있습니다.')),
        );
      }
      return;
    }
    final bytes = await picked.readAsBytes();
    setState(() { _pickedFile = picked; _imageBytes = bytes; });
  }

  /// package:http로 캡처 이미지를 업로드하고 상태 코드를 반환한다.
  /// Dio의 웹 XHR 어댑터는 대용량 멀티파트 업로드 시 브라우저 네트워크 계층에서
  /// "XMLHttpRequest onError"로 실패하는 경우가 반복 확인되어, 이 업로드만은
  /// package:http로 직접 요청을 구성한다 (토큰 갱신은 수동으로 처리).
  Future<http.StreamedResponse> _sendCaptureUpload(String accessToken) async {
    final mime = _mimeFromName(_pickedFile!.name);
    final uri = Uri.parse('${AppConstants.baseUrl}/auth/capture/upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['school_code'] = '${widget.schoolInfo['school_code'] ?? ''}'
      ..fields['school_name'] = '${widget.schoolInfo['school_name'] ?? ''}'
      ..fields['grade'] = '${widget.schoolInfo['grade'] ?? 1}'
      ..fields['school_type'] = '${widget.schoolInfo['school_type'] ?? ''}'
      ..fields['region'] = '${widget.schoolInfo['region'] ?? ''}'
      ..fields['capture_type'] = widget.captureType
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        _imageBytes!,
        filename: _pickedFile!.name,
        contentType: MediaType.parse(mime),
      ));
    if (widget.schoolInfo['class_num'] != null) {
      request.fields['class_num'] = '${widget.schoolInfo['class_num']}';
    }
    if (widget.schoolInfo['expected_entry_year'] != null) {
      request.fields['expected_entry_year'] = '${widget.schoolInfo['expected_entry_year']}';
    }
    return request.send().timeout(const Duration(minutes: 3));
  }

  /// 오류 원인을 사용자가 이해할 수 있는 한국어 메시지로 변환.
  String _koreanUploadError(Object e) {
    if (e is TimeoutException) {
      return '업로드 시간이 초과되었습니다. 네트워크 상태를 확인한 후 다시 시도해주세요.';
    }
    final text = e.toString();
    if (text.contains('XMLHttpRequest') || text.contains('ClientException') || text.contains('SocketException')) {
      return '네트워크 연결 오류로 업로드에 실패했습니다. Wi-Fi/데이터 연결을 확인한 후 다시 시도해주세요.';
    }
    return '업로드 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
  }

  /// 서버(무료 요금제 Render)는 일정 시간 요청이 없으면 슬립 상태가 되어
  /// 깨어나는 데 최대 수십 초가 걸린다. 이 사이에 업로드를 시도하면 연결이
  /// 끊기며 네트워크 오류로 보이는 경우가 많아, 실제 업로드 전에 가벼운
  /// /health 핑으로 서버를 미리 깨워둔다. 실패해도 업로드는 계속 시도한다.
  Future<void> _wakeUpServer() async {
    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final healthUri = uri.replace(path: '/health', query: '');
      await http.get(healthUri).timeout(const Duration(seconds: 40));
    } catch (_) {
      // 무시 — 실패해도 이후 실제 업로드를 시도한다.
    }
  }

  bool _isTransientNetworkError(Object e) {
    if (e is TimeoutException) return true;
    final text = e.toString();
    return text.contains('XMLHttpRequest') || text.contains('ClientException') || text.contains('SocketException');
  }

  /// 토큰 확보 + 업로드 + 401 시 1회 리프레시 후 재시도까지 포함한 단일 시도.
  Future<http.StreamedResponse?> _attemptUpload(Dio dio, dynamic tokenStorage) async {
    var token = await tokenStorage.read(AppConstants.tokenKey);
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 만료되었습니다. 다시 로그인해주세요.')));
      }
      return null;
    }

    var streamed = await _sendCaptureUpload(token);

    if (streamed.statusCode == 401) {
      final refreshed = await tryRefreshToken(dio);
      if (!refreshed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 만료되었습니다. 다시 로그인해주세요.')));
        }
        return null;
      }
      token = await tokenStorage.read(AppConstants.tokenKey);
      streamed = await _sendCaptureUpload(token!);
    }
    return streamed;
  }

  Future<void> _submit() async {
    if (_pickedFile == null || _imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('알림장 캡처 이미지를 선택해주세요.')));
      return;
    }
    setState(() => _uploading = true);
    try {
      final dio = ref.read(dioProvider);
      final tokenStorage = ref.read(tokenStorageProvider);

      // 무료 요금제 서버는 유휴 상태에서 슬립되어 있을 수 있어, 실제 업로드
      // 전에 가볍게 깨워둔다 (실패해도 무시하고 업로드를 계속 시도).
      await _wakeUpServer();

      http.StreamedResponse? streamed;
      try {
        streamed = await _attemptUpload(dio, tokenStorage);
      } catch (e) {
        // 콜드 스타트 등으로 인한 일시적 네트워크 오류는 서버가 깨어날 시간을
        // 준 뒤 한 번 더 시도한다.
        if (_isTransientNetworkError(e)) {
          await Future.delayed(const Duration(seconds: 5));
          streamed = await _attemptUpload(dio, tokenStorage);
        } else {
          rethrow;
        }
      }
      if (streamed == null) return; // 로그인 만료 등 — 이미 안내 메시지 표시함

      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        if (mounted) {
          if (widget.captureType == 'child_add') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('제출 완료! 관리자 확인 후 자녀 학교가 추가됩니다.')),
            );
            context.pop(true);
          } else {
            context.go('/auth/pending');
          }
        }
        return;
      }

      final body = await http.Response.fromStream(streamed);
      String detail = '업로드에 실패했습니다. (오류 코드 ${streamed.statusCode})';
      final match = RegExp(r'"detail"\s*:\s*"([^"]*)"').firstMatch(body.body);
      if (match != null && match.group(1)!.isNotEmpty) detail = match.group(1)!;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_koreanUploadError(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// [DEV] 이미지 없이 제출 + 즉시 정회원 승급
  Future<void> _devSkipSubmit() async {
    setState(() => _uploading = true);
    try {
      final dio = ref.read(dioProvider);

      // 1. 더미 s3_key로 캡처 제출
      await dio.post('/auth/capture/submit', data: {
        's3_key': 'dev/placeholder/${DateTime.now().millisecondsSinceEpoch}.jpg',
        'school_code': widget.schoolInfo['school_code'],
        'school_name': widget.schoolInfo['school_name'],
        'grade': widget.schoolInfo['grade'],
        'class_num': widget.schoolInfo['class_num'],
        'school_type': widget.schoolInfo['school_type'],
        'region': widget.schoolInfo['region'] ?? '',
        'expected_entry_year': widget.schoolInfo['expected_entry_year'],
      });

      if (widget.captureType == 'child_add') {
        // 자녀 추가 DEV: 즉시 캡처 승인 (admin API 불필요 — 서버에서 처리)
        ref.invalidate(userProfileProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('[DEV] 자녀 추가 제출 완료!')),
          );
          context.pop(true);
        }
      } else {
        // 최초 가입 DEV: 즉시 승인 → member_grade = 'member'
        await dio.post('/auth/dev/approve-me');
        ref.invalidate(userProfileProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('[DEV] 즉시 정회원 승급 완료!')),
          );
          context.go('/board');
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('제출 실패: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildImagePreview() {
    if (_imageBytes == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('탭하여 이미지 선택', style: TextStyle(color: Colors.grey.shade500)),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(_imageBytes!, fit: BoxFit.cover, width: double.infinity),
    );
  }

  bool get _isPreschool => widget.schoolInfo['school_type'] == 'preschool';

  @override
  Widget build(BuildContext context) {
    final schoolName = widget.schoolInfo['school_name'] as String? ?? '학교';
    final grade = widget.schoolInfo['grade'] as int? ?? 1;
    final region = widget.schoolInfo['region'] as String? ?? '';
    final headerLabel = _isPreschool ? '$region 미취학 학부모 인증' : '$schoolName $grade학년 학부모 인증';

    return Scaffold(
      appBar: AppBar(title: Text(widget.captureType == 'child_add' ? '자녀 인증' : '근거자료 등록')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 안내 ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(headerLabel,
                        style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    _isPreschool
                        ? '어린이집/유치원 알림장이나 안내문 사진을 업로드해 주세요.\n관리자 확인 후 이용할 수 있어요. (학교 게시판은 이용할 수 없고, 지역 게시판만 이용 가능해요)'
                        : widget.captureType == 'child_add'
                            ? '같은 학교 학부모들만 모이는 게시판이라 실제 재학생 학부모인지 확인이 필요해요.\n'
                              '최근 1주일 이내 학교에서 받은 자료 사진을 업로드해 주세요.\n관리자 확인 후 해당 자녀 학교가 추가됩니다.'
                            : '같은 학교·학년 학부모들만 모이는 게시판이라 실제 재학생 학부모인지 확인이 필요해요.\n'
                              '최근 1주일 이내 학교에서 받은 자료 사진을 업로드해 주세요.\n관리자 확인 후 정회원으로 승인됩니다.',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 예시 자료명 ──────────────────────────────────
            Text('인정되는 자료 예시 ($_recentDateRange 발송분)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._exampleDocs.map((doc) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('• ', style: TextStyle(color: Colors.grey, fontSize: 13)),
                Expanded(child: Text(doc, style: const TextStyle(fontSize: 13, color: Colors.grey))),
              ]),
            )),
            const SizedBox(height: 16),

            // ── 이미지 업로드 영역 ─────────────────────────
            GestureDetector(
              onTap: _uploading ? null : _pickImage,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _imageBytes != null
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    width: _imageBytes != null ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: _buildImagePreview(),
              ),
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 6),
              Center(
                child: TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('다른 이미지 선택', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],

            if (kIsWeb) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Text(
                  '웹에서는 갤러리 이미지만 선택 가능합니다.\n실제 앱에서는 카메라 촬영도 지원됩니다.',
                  style: TextStyle(fontSize: 12, color: Colors.brown),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── 제출 버튼 ────────────────────────────────────
            FilledButton(
              onPressed: _uploading ? null : _submit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _uploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('제출하기', style: TextStyle(fontSize: 15)),
            ),

            // ── DEV 즉시 승인 버튼 ──────────────────────────
            if (AppConstants.devMode) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _uploading ? null : _devSkipSubmit,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Colors.deepOrange),
                  foregroundColor: Colors.deepOrange,
                ),
                child: const Text('[DEV] 사진 없이 즉시 정회원 승급', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 4),
              const Text(
                '개발 테스트 전용 — 사진 검토 없이 자동 승인됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
