import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import '../../board/screens/board_screen.dart' show userProfileProvider;

class CaptureUploadScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> schoolInfo;
  const CaptureUploadScreen({super.key, required this.schoolInfo});

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

  String _contentTypeFromName(String name) {
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
    final picked = await picker.pickImage(source: ImageSource.gallery);
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

  Future<void> _submit() async {
    if (_pickedFile == null || _imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('알림장 캡처 이미지를 선택해주세요.')));
      return;
    }
    setState(() => _uploading = true);
    try {
      final dio = ref.read(dioProvider);
      final contentType = _contentTypeFromName(_pickedFile!.name);

      final presignResp = await dio.post('/auth/capture/presign', data: {'content_type': contentType});
      final uploadUrl = presignResp.data['upload_url'] as String;
      final s3Key = presignResp.data['s3_key'] as String;
      final skipUpload = presignResp.data['skip_upload'] as bool? ?? false;

      if (!skipUpload) {
        final putResp = await http.put(
          Uri.parse(uploadUrl),
          body: _imageBytes,
          headers: {'Content-Type': contentType},
        );
        if (putResp.statusCode != 200 && putResp.statusCode != 204) {
          throw Exception('이미지 업로드 실패 (${putResp.statusCode})');
        }
      }

      await dio.post('/auth/capture/submit', data: {
        's3_key': s3Key,
        'school_code': widget.schoolInfo['school_code'],
        'school_name': widget.schoolInfo['school_name'],
        'grade': widget.schoolInfo['grade'],
        'class_num': widget.schoolInfo['class_num'],
        'school_type': widget.schoolInfo['school_type'],
        'region': widget.schoolInfo['region'] ?? '',
      });

      if (mounted) context.go('/auth/pending');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
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
      });

      // 2. dev 즉시 승인 → member_grade = 'member'
      await dio.post('/auth/dev/approve-me');

      // 3. 캐시된 프로필 무효화 후 board로 이동 (정회원 탭 바로 열림)
      ref.invalidate(userProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('[DEV] 즉시 정회원 승급 완료!')),
        );
        context.go('/board');
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

  @override
  Widget build(BuildContext context) {
    final schoolName = widget.schoolInfo['school_name'] as String? ?? '학교';
    final grade = widget.schoolInfo['grade'] as int? ?? 1;

    return Scaffold(
      appBar: AppBar(title: const Text('근거자료 등록')),
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
                    Text('$schoolName $grade학년 학부모 인증',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    '최근 1주일 이내 학교에서 받은 자료 사진을 업로드해 주세요.\n관리자 확인 후 정회원으로 승인됩니다.',
                    style: TextStyle(fontSize: 13, height: 1.5),
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
