import 'package:flutter/material.dart';

class SwipeButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color activeColor;
  final Future<void> Function() onSwipeComplete;

  const SwipeButton({
    Key? key,
    required this.label,
    required this.icon,
    this.activeColor = const Color(0xFF10B981),
    required this.onSwipeComplete,
  }) : super(key: key);

  @override
  State<SwipeButton> createState() => _SwipeButtonState();
}

class _SwipeButtonState extends State<SwipeButton> {
  double _dragPosition = 0.0;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    const double height = 58.0;
    const double knobSize = 48.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxDrag = constraints.maxWidth - knobSize - 10;

        return Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: widget.activeColor.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Swipe progress fill
              Container(
                width: _dragPosition + knobSize,
                height: height,
                decoration: BoxDecoration(
                  color: widget.activeColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(30),
                ),
              ),

              // Center Hint Text
              Center(
                child: Text(
                  _isLoading ? 'Updating...' : widget.label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Sliding Knob
              Positioned(
                left: 5 + _dragPosition,
                child: GestureDetector(
                  onHorizontalDragUpdate: _isLoading
                      ? null
                      : (details) {
                          setState(() {
                            _dragPosition = (_dragPosition + details.delta.dx)
                                .clamp(0.0, maxDrag);
                          });
                        },
                  onHorizontalDragEnd: _isLoading
                      ? null
                      : (details) async {
                          if (_dragPosition >= maxDrag * 0.75) {
                            setState(() {
                              _dragPosition = maxDrag;
                              _isLoading = true;
                            });
                            try {
                              await widget.onSwipeComplete();
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _dragPosition = 0.0;
                                  _isLoading = false;
                                });
                              }
                            }
                          } else {
                            setState(() {
                              _dragPosition = 0.0;
                            });
                          }
                        },
                  child: Container(
                    width: knobSize,
                    height: knobSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.activeColor,
                      boxShadow: [
                        BoxShadow(
                          color: widget.activeColor.withOpacity(0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(widget.icon, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
