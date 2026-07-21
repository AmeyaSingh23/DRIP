import 'package:flutter/material.dart';

class HangerLoadingIndicator extends StatefulWidget {
  final double size;
  const HangerLoadingIndicator({super.key, this.size = 80});

  @override
  State<HangerLoadingIndicator> createState() => _HangerLoadingIndicatorState();
}

class _HangerLoadingIndicatorState extends State<HangerLoadingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _swingAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _swingAnimation = Tween<double>(begin: -0.15, end: 0.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: widget.size * 1.5,
      height: widget.size,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // The Nail stuck in the wall
          Positioned(
            top: (widget.size * 0.2) + 2, // proportional position for nail + 2px down

            child: Container(
              width: widget.size * 0.1,
              height: widget.size * 0.1,
              decoration: const BoxDecoration(
                color: Color(0xFF6D5D61),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          // The Hanger
          Positioned(
            top: 0,
            child: RotationTransition(
              turns: _swingAnimation,
              alignment: const Alignment(0, -0.65),
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFFFFB6C1),
                          Color(0xBBFFFFFF),
                          Color(0xFFC2185B),
                        ]
                      : const [
                          Color(0xFFFF69B4),
                          Color(0x88FFFFFF),
                          Color(0xFFFFC0CB),
                        ],
                  stops: const [0.0, 0.4, 1.0],
                ).createShader(bounds),
                blendMode: BlendMode.srcATop,
                child: Icon(
                  Icons.checkroom_rounded,
                  size: widget.size,
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
