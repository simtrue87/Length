// AR 측정 화면. W1 PoC: ARCore 가용성 자동 확인 + 미지원 시 사진 모드 폴백 안내.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../domain/ar_session.dart';
import '../infrastructure/arcore_session.dart';

class ArMeasureScreen extends StatefulWidget {
  const ArMeasureScreen({super.key});

  @override
  State<ArMeasureScreen> createState() => _ArMeasureScreenState();
}

class _ArMeasureScreenState extends State<ArMeasureScreen> {
  final ArSession _session = ArcoreSession();
  ArAvailability _availability = ArAvailability.unknown;
  String _status = '가용성 확인 중...';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void dispose() {
    _session.release();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    setState(() => _busy = true);
    try {
      final a = await _session.checkAvailability();
      if (!mounted) return;
      setState(() {
        _availability = a;
        _status = switch (a) {
          ArAvailability.supported => '준비 완료. AR 세션을 시작할 수 있습니다.',
          ArAvailability.needsInstall =>
            'Google Play Services for AR 설치가 필요합니다.',
          ArAvailability.unsupported => '이 기기는 AR을 지원하지 않습니다.',
          ArAvailability.unknown => '확인할 수 없습니다.',
        };
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _availability = ArAvailability.unknown;
        _status = '오류: ${e.message}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSession() async {
    setState(() {
      _busy = true;
      _status = '세션 생성 중...';
    });
    try {
      if (_availability == ArAvailability.needsInstall) {
        final install = await _session.requestInstall();
        if (install == ArInstallStatus.installRequested) {
          setState(() {
            _busy = false;
            _status = '설치 안내가 표시되었습니다. 완료 후 다시 시도해주세요.';
          });
          return;
        }
      }
      await _session.create();
      if (!mounted) return;
      setState(() => _status = '세션 생성 성공 (PoC).');
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _status = '실패: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AR 측정 (PoC)')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _availability == ArAvailability.unsupported
              ? _buildFallback()
              : _buildSupported(),
    );
  }

  Widget _buildSupported() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _startSession,
              child: const Text('ARCore 세션 시작'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Icon(
            Icons.do_not_disturb_alt,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '사진 기반 측정 모드를 사용해 측정할 수 있습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.crop_free),
            onPressed: () => context.go('/photo/reference'),
            label: const Text('사진 — 참조 객체'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.straighten),
            onPressed: () => context.go('/photo/calibration'),
            label: const Text('사진 — 캘리브레이션'),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => context.go('/'),
            child: const Text('모드 선택으로'),
          ),
        ],
      ),
    );
  }
}
