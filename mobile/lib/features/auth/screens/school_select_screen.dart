import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';

enum _Step { region, school }

class SchoolSelectScreen extends ConsumerStatefulWidget {
  final String smsToken;
  const SchoolSelectScreen({super.key, required this.smsToken});

  @override
  ConsumerState<SchoolSelectScreen> createState() => _SchoolSelectScreenState();
}

class _SchoolSelectScreenState extends ConsumerState<SchoolSelectScreen> {
  _Step _step = _Step.region;

  String? _selectedProvince;
  String? _selectedRegion;

  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _schools = [];
  Map<String, dynamic>? _selectedSchool;
  int _grade = 1;
  bool _searching = false;
  bool _registering = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _searchCtrl.text.trim();
    if (keyword.length < 2) return;
    setState(() { _searching = true; _schools = []; });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/schools/search', queryParameters: {'keyword': keyword});
      setState(() => _schools = List<Map<String, dynamic>>.from(resp.data));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _register() async {
    if (_selectedSchool == null || _selectedRegion == null) return;
    setState(() => _registering = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/parent/verify', data: {
        'sms_token': widget.smsToken,
        'region': _selectedRegion,
        'school_code': _selectedSchool!['school_code'],
        'school_name': _selectedSchool!['school_name'],
        'grade': _grade,
        'school_type': _selectedSchool!['school_type'],
      });
      const storage = FlutterSecureStorage();
      await storage.write(key: AppConstants.tokenKey, value: resp.data['access_token']);
      await storage.write(key: AppConstants.refreshTokenKey, value: resp.data['refresh_token']);
      if (mounted) context.go('/board');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('등록 실패: $e')));
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == _Step.region ? '지역 선택' : '학교 선택'),
        leading: _step == _Step.school
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _step = _Step.region;
                  _selectedSchool = null;
                }),
              )
            : null,
      ),
      body: _step == _Step.region ? _buildRegionStep() : _buildSchoolStep(),
    );
  }

  Widget _buildRegionStep() {
    final provinces = AppConstants.regions.keys.toList();
    final cities = _selectedProvince != null
        ? AppConstants.regions[_selectedProvince]!
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('자녀가 재학 중인 학교의 지역을 선택해주세요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                child: ListView.builder(
                  itemCount: provinces.length,
                  itemBuilder: (_, i) {
                    final p = provinces[i];
                    final selected = _selectedProvince == p;
                    return ListTile(
                      dense: true,
                      title: Text(p, style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      )),
                      selected: selected,
                      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
                      onTap: () => setState(() {
                        _selectedProvince = p;
                        _selectedRegion = null;
                      }),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: cities.length,
                  itemBuilder: (_, i) {
                    final c = cities[i];
                    final selected = _selectedRegion == c;
                    return ListTile(
                      dense: true,
                      title: Text(c, style: TextStyle(
                        fontSize: 14,
                        color: selected ? Theme.of(context).colorScheme.primary : null,
                      )),
                      trailing: selected
                          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary, size: 18)
                          : null,
                      onTap: () => setState(() => _selectedRegion = c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedRegion != null
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300],
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _selectedRegion == null
                ? null
                : () => setState(() => _step = _Step.school),
            child: Text(_selectedRegion != null
                ? '$_selectedRegion 선택 완료 →'
                : '지역을 선택해주세요'),
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            const Icon(Icons.location_on, size: 16, color: Colors.grey),
            const SizedBox(width: 4),
            Text(_selectedRegion ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: '학교명 검색 (2자 이상)',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _search, child: const Text('검색')),
          ]),
        ),
        if (_searching) const LinearProgressIndicator(),
        Expanded(
          child: _schools.isEmpty && !_searching
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.search, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text(
                      '학교명을 입력하고 검색 버튼을 눌러주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ]),
                )
              : ListView.builder(
                  itemCount: _schools.length,
                  itemBuilder: (_, i) {
                    final s = _schools[i];
                    final selected = _selectedSchool?['school_code'] == s['school_code'];
                    return ListTile(
                      title: Text(s['school_name']),
                      subtitle: Text(s['address'] ?? '', style: const TextStyle(fontSize: 12)),
                      trailing: selected
                          ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () => setState(() => _selectedSchool = s),
                    );
                  },
                ),
        ),
        if (_selectedSchool != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<int>(
              value: _grade,
              decoration: const InputDecoration(
                labelText: '학년',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: List.generate(6, (i) => i + 1)
                  .map((g) => DropdownMenuItem(value: g, child: Text('$g학년')))
                  .toList(),
              onChanged: (v) => setState(() => _grade = v!),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: (_selectedSchool != null && !_registering)
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300],
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: (_selectedSchool == null || _registering) ? null : _register,
            child: _registering
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('가입 완료'),
          ),
        ),
      ],
    );
  }
}
