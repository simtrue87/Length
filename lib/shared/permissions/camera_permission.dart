// 카메라 권한 요청·영구 거부 처리. image_picker camera 진입 전에 호출.
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 권한 결과. allowed=true면 카메라 진입 가능.
class CameraPermissionResult {
  const CameraPermissionResult({required this.allowed, this.message});
  final bool allowed;
  final String? message;
}

Future<CameraPermissionResult> ensureCameraPermission(
    BuildContext context) async {
  final status = await Permission.camera.status;
  if (status.isGranted || status.isLimited) {
    return const CameraPermissionResult(allowed: true);
  }
  if (status.isPermanentlyDenied) {
    if (context.mounted) {
      await _showSettingsDialog(context);
    }
    return const CameraPermissionResult(
        allowed: false, message: '설정에서 카메라 권한을 허용해주세요.');
  }
  final result = await Permission.camera.request();
  if (result.isGranted) {
    return const CameraPermissionResult(allowed: true);
  }
  if (result.isPermanentlyDenied && context.mounted) {
    await _showSettingsDialog(context);
  }
  return const CameraPermissionResult(
      allowed: false, message: '카메라 권한이 필요합니다.');
}

Future<void> _showSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('카메라 권한 필요'),
      content: const Text('촬영하려면 시스템 설정에서 카메라 권한을 허용해야 합니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            openAppSettings();
          },
          child: const Text('설정 열기'),
        ),
      ],
    ),
  );
}
