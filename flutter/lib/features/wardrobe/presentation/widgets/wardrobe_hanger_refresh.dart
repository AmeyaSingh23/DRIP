import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class WardrobeHangerRefreshControl extends StatefulWidget {
  final Future<void> Function() onRefresh;

  const WardrobeHangerRefreshControl({super.key, required this.onRefresh});

  @override
  State<WardrobeHangerRefreshControl> createState() => _WardrobeHangerRefreshControlState();
}

class _WardrobeHangerRefreshControlState extends State<WardrobeHangerRefreshControl> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _swingAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _swingAnimation = Tween<double>(begin: -0.15, end: 0.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildRefreshIndicator(
    BuildContext context,
    RefreshIndicatorMode refreshState,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
  ) {
    if (refreshState == RefreshIndicatorMode.refresh || refreshState == RefreshIndicatorMode.armed) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.animateTo(0.5, duration: const Duration(milliseconds: 300));
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // We constrain the height to pulledExtent to show the nail and hanger dropping down
    return SizedBox(
      height: pulledExtent,
      child: Center(
        child: SizedBox(
          width: 140,
          height: 100,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // The Nail stuck in the wall (BEHIND the hanger)
              Positioned(
                top: 20, // Positions the nail deep inside the hook's loop
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6D5D61), // Dark metallic
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
              // The Hanger (Swinging in FRONT of the nail)
              Positioned(
                top: 3,
                child: RotationTransition(
                  turns: _swingAnimation,
                  alignment: const Alignment(0, -0.65), // Pivot near the hook
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
                              Color(0xFFFF8DA1),
                              Color(0xFFFFFFFF),
                              Color(0xFFFF4E84),
                            ],
                      stops: const [0.0, 0.5, 1.0],
                    ).createShader(bounds),
                    blendMode: BlendMode.srcIn,
                    child: const Icon(
                      Icons.checkroom_rounded,
                      size: 72,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoSliverRefreshControl(
      onRefresh: widget.onRefresh,
      builder: _buildRefreshIndicator,
    );
  }
}


