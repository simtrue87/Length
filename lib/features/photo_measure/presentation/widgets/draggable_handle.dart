// 사진 위에 드래그로 이동하는 원형 핸들. 4점 보정·두 점 탭 양쪽에서 재사용.
import 'package:flutter/material.dart';

class DraggableHandle extends StatelessWidget {
  const DraggableHandle({
    super.key,
    required this.position,
    required this.onDrag,
    this.onDragEnd,
    this.color,
    this.label,
    this.size = 28,
  });

  final Offset position;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset>? onDragEnd;
  final Color? color;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: GestureDetector(
        onPanUpdate: (d) => onDrag(position + d.delta),
        onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(position),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 2),
          ),
          alignment: Alignment.center,
          child: label == null
              ? null
              : Text(
                  label!,
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
        ),
      ),
    );
  }
}
