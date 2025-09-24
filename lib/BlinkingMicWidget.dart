import 'package:flutter/material.dart';

class BlinkingMicWidget extends StatefulWidget {
  final bool isListening;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? inactiveColor;
  final Color? activeColor;

  const BlinkingMicWidget({
    Key? key,
    required this.isListening,
    this.onPressed,
    this.tooltip,
    this.size = 24.0,
    this.inactiveColor,
    this.activeColor,
  }) : super(key: key);

  @override
  _BlinkingMicWidgetState createState() => _BlinkingMicWidgetState();
}

class _BlinkingMicWidgetState extends State<BlinkingMicWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(BlinkingMicWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _animationController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _animationController.stop();
      _animationController.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: widget.isListening
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: (widget.activeColor ?? Colors.green)
                      .withOpacity(_animation.value * 0.3),
                  boxShadow: [
                    BoxShadow(
                      color: (widget.activeColor ?? Colors.green)
                          .withOpacity(_animation.value * 0.5),
                      blurRadius: 8.0 + (_animation.value * 4.0),
                      spreadRadius: 2.0 + (_animation.value * 2.0),
                    ),
                  ],
                )
              : null,
          child: IconButton(
            icon: Icon(
              widget.isListening ? Icons.mic : Icons.mic_none,
              size: widget.size,
              color: widget.isListening
                  ? (widget.activeColor ?? Colors.green)
                  : (widget.inactiveColor ?? Colors.grey),
            ),
            onPressed: widget.onPressed,
            tooltip: widget.tooltip,
          ),
        );
      },
    );
  }
}

// Alternative simpler version for suffix icons
class BlinkingMicSuffixIcon extends StatefulWidget {
  final bool isListening;
  final VoidCallback? onPressed;
  final double size;
  final Color? inactiveColor;
  final Color? activeColor;

  const BlinkingMicSuffixIcon({
    Key? key,
    required this.isListening,
    this.onPressed,
    this.size = 20.0,
    this.inactiveColor,
    this.activeColor,
  }) : super(key: key);

  @override
  _BlinkingMicSuffixIconState createState() => _BlinkingMicSuffixIconState();
}

class _BlinkingMicSuffixIconState extends State<BlinkingMicSuffixIcon>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(BlinkingMicSuffixIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _animationController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _animationController.stop();
      _animationController.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: widget.isListening
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: (widget.activeColor ?? Colors.green)
                      .withOpacity(_animation.value * 0.3),
                  boxShadow: [
                    BoxShadow(
                      color: (widget.activeColor ?? Colors.green)
                          .withOpacity(_animation.value * 0.5),
                      blurRadius: 6.0 + (_animation.value * 3.0),
                      spreadRadius: 1.0 + (_animation.value * 1.5),
                    ),
                  ],
                )
              : null,
          child: IconButton(
            icon: Icon(
              Icons.mic,
              size: widget.size,
              color: widget.isListening
                  ? (widget.activeColor ?? Colors.green)
                  : (widget.inactiveColor ?? Colors.grey),
            ),
            onPressed: widget.onPressed,
          ),
        );
      },
    );
  }
}
