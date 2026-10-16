import 'package:flutter/material.dart';

/// Shimmer skeleton shown while async data loads — premium feel vs plain
/// spinner. Mirrors content shape so layout doesn't jump when data arrives.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: -0.5, end: 1.5),
      duration: const Duration(seconds: 2),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment(value, 0),
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: borderRadius,
                gradient: const LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0x10FFFFFF),
                    Colors.transparent,
                  ],
                  stops: [0.4, 0.5, 0.6],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shimmer list: paints N skeleton rows of a given height.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final double spacing;

  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 56,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (_, i) => Padding(
        padding: EdgeInsets.only(bottom: spacing),
        child: SkeletonBox(height: itemHeight, width: double.infinity),
      ),
    );
  }
}

/// Shimmer card for dashboard-style loading (rounded rectangle skeleton).
class SkeletonCard extends StatelessWidget {
  final double height;

  const SkeletonCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: SizedBox(
        height: height,
        child: SkeletonBox(width: double.infinity, height: height),
      ),
    );
  }
}
