// 측정 진행 중 뒤로가기 시 사용자 확인 다이얼로그.
import 'package:flutter/material.dart';

Future<bool> confirmExitMeasurement(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('측정을 종료할까요?'),
      content: const Text('진행 중인 점·보정 정보가 사라집니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('계속'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('종료'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
