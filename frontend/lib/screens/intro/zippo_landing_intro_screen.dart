import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../customer/customer_home_screen.dart';

class ZippoLandingIntroScreen extends StatefulWidget {
  const ZippoLandingIntroScreen({super.key});

  @override
  State<ZippoLandingIntroScreen> createState() => _ZippoLandingIntroScreenState();
}

class _ZippoLandingIntroScreenState extends State<ZippoLandingIntroScreen>
    with TickerProviderStateMixin {
  // Scooter & movement controllers
  late AnimationController _bikeController;
  late AnimationController _engineBobController;
  late AnimationController _wheelSpinController;

  // Letter reveal controllers (Z - I - P - P - O)
  late List<AnimationController> _letterControllers;

  // 6 Small Goods Pills reveal controllers
  late List<AnimationController> _pillControllers;

  // Melapalayam Tamil badge controller
  late AnimationController _tamilBadgeController;

  // Master fade out / exit controller
  late AnimationController _exitController;

  bool _hasNavigated = false;
  String _statusText = "ZIPPO rider cruising across Melapalayam...";
  double _progressValue = 0.05;

  // Letters Data: Z - I - P - P - O
  final List<Map<String, dynamic>> _lettersData = [
    {'char': 'Z', 'desc': 'Zero Wait', 'isGreen': false, 'trigger': 0.12},
    {'char': 'I', 'desc': 'Instant', 'isGreen': true, 'trigger': 0.32},
    {'char': 'P', 'desc': 'Pickup', 'isGreen': false, 'trigger': 0.52},
    {'char': 'P', 'desc': 'Parcel', 'isGreen': false, 'trigger': 0.72},
    {'char': 'O', 'desc': 'On-Demand', 'isGreen': true, 'trigger': 0.88},
  ];

  // 6 Light Pastel Goods Pills Data (revealed one by one as scooter moves)
  final List<Map<String, dynamic>> _pillsData = [
    {
      'icon': Icons.inventory_2_outlined,
      'label': 'Parcel',
      'bg': const Color(0xFFFFF7ED), // Light orange pastel
      'textColor': const Color(0xFF9A3412),
      'borderColor': const Color(0xFFFFEDD5),
      'trigger': 0.08,
      'topFactor': 0.16,
      'left': 22.0,
      'right': null,
      'bottom': null,
    },
    {
      'icon': Icons.restaurant_rounded,
      'label': 'Food & Meat',
      'bg': const Color(0xFFF0FDF4), // Light green pastel
      'textColor': const Color(0xFF166534),
      'borderColor': const Color(0xFFDCFCE7),
      'trigger': 0.24,
      'topFactor': 0.24,
      'left': null,
      'right': 22.0,
      'bottom': null,
    },
    {
      'icon': Icons.medication_outlined,
      'label': 'Medicine',
      'bg': const Color(0xFFF0F9FF), // Light sky blue pastel
      'textColor': const Color(0xFF0369A1),
      'borderColor': const Color(0xFFE0F2FE),
      'trigger': 0.40,
      'topFactor': 0.14,
      'left': null,
      'right': 30.0,
      'bottom': null,
    },
    {
      'icon': Icons.vpn_key_outlined,
      'label': 'Urgent Keys',
      'bg': const Color(0xFFFAF5FF), // Light purple pastel
      'textColor': const Color(0xFF7E22CE),
      'borderColor': const Color(0xFFF3E8FF),
      'trigger': 0.56,
      'topFactor': null,
      'left': 26.0,
      'right': null,
      'bottom': 135.0,
    },
    {
      'icon': Icons.two_wheeler_rounded,
      'label': 'Bike Lift',
      'bg': const Color(0xFFECFDF5), // Light emerald pastel
      'textColor': const Color(0xFF065F46),
      'borderColor': const Color(0xFFD1FAE5),
      'trigger': 0.72,
      'topFactor': null,
      'left': null,
      'right': 26.0,
      'bottom': 140.0,
    },
    {
      'icon': Icons.shopping_bag_outlined,
      'label': 'Bazaar Goods',
      'bg': const Color(0xFFFFFBEB), // Light amber pastel
      'textColor': const Color(0xFF92400E),
      'borderColor': const Color(0xFFFEF3C7),
      'trigger': 0.86,
      'topFactor': 0.28,
      'left': 18.0,
      'right': null,
      'bottom': null,
    },
  ];

  @override
  void initState() {
    super.initState();

    // 1. Slow & Gentle Bike Movement (3800 ms duration so the journey is smooth and readable)
    _bikeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    );

    // 2. Engine Bob (gentle suspension bob)
    _engineBobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..repeat(reverse: true);

    // 3. Wheel Spin
    _wheelSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..repeat();

    // 4. Letter reveal controllers (5 letters)
    _letterControllers = List.generate(
      5,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 650),
      ),
    );

    // 5. 6 Small Goods Pills reveal controllers
    _pillControllers = List.generate(
      6,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );

    // 6. Tamil Badge
    _tamilBadgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // 7. Exit Controller
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Listen to scooter progress to trigger letters and pills sequentially
    _bikeController.addListener(_onBikeProgress);

    // Start immediately without any initial card
    _startAnimationSequence();
  }

  void _onBikeProgress() {
    final progress = _bikeController.value;

    setState(() {
      _progressValue = progress;
    });

    // 1. Reveal letters as scooter passes each letter position
    for (int i = 0; i < _lettersData.length; i++) {
      final triggerPoint = _lettersData[i]['trigger'] as double;
      if (progress >= triggerPoint &&
          !_letterControllers[i].isCompleted &&
          !_letterControllers[i].isAnimating) {
        _letterControllers[i].forward();
        HapticFeedback.lightImpact();
      }
    }

    // 2. Reveal light pastel goods pills as scooter reaches each threshold
    for (int i = 0; i < _pillsData.length; i++) {
      final triggerPoint = _pillsData[i]['trigger'] as double;
      if (progress >= triggerPoint &&
          !_pillControllers[i].isCompleted &&
          !_pillControllers[i].isAnimating) {
        _pillControllers[i].forward();
      }
    }

    // 3. Reveal Tamil Sub-Badge when approaching the end of letters
    if (progress >= 0.88 &&
        !_tamilBadgeController.isCompleted &&
        !_tamilBadgeController.isAnimating) {
      _tamilBadgeController.forward();
    }
  }

  Future<void> _startAnimationSequence() async {
    // Very brief delay for smooth mount, then start scooter glide straightaway
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    await _bikeController.forward();

    if (!mounted) return;

    setState(() {
      _statusText = "Welcome to ZIPPO! Arrived.";
      _progressValue = 1.0;
    });

    // Brief celebratory pause at the end
    await Future.delayed(const Duration(milliseconds: 550));

    if (!mounted) return;
    _navigateToHome();
  }

  void _navigateToHome() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    _exitController.forward().then((_) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 650),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const CustomerHomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _bikeController.removeListener(_onBikeProgress);
    _bikeController.dispose();
    _engineBobController.dispose();
    _wheelSpinController.dispose();
    for (final c in _letterControllers) {
      c.dispose();
    }
    for (final c in _pillControllers) {
      c.dispose();
    }
    _tamilBadgeController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: AnimatedBuilder(
          animation: _exitController,
          builder: (context, child) {
            final exitVal = _exitController.value;
            final exitOpacity = 1.0 - exitVal;
            final exitScale = 1.0 + (exitVal * 0.08);

            return Opacity(
              opacity: exitOpacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: exitScale,
                child: child,
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Organic Light Color Waves & Subtle Melapalayam Watermark
              CustomPaint(
                size: screenSize,
                painter: _LandingCurvesAndWatermarkPainter(),
              ),

              // 2. Light Pastel Goods Pills (revealed one by one as scooter moves)
              ...List.generate(_pillsData.length, (index) {
                return _buildAnimatedPillWidget(index, screenSize);
              }),

              // 3. Foreground Column (Top Bar, ZIPPO Letters & Runway, Progress Bar)
              SafeArea(
                child: Column(
                  children: [
                    // Top Bar (Melapalayam Dispatch Badge & Skip Button)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'MELAPALAYAM DISPATCH',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _navigateToHome,
                            icon: const Text(
                              'Skip to Home',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF475569),
                              ),
                            ),
                            label: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: Color(0xFF475569),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.9),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              shadowColor: Colors.black.withValues(alpha: 0.05),
                              elevation: 1,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Centered Stage: Letters (Z I P P O) + Tamil Badge + Scooter Runway
                    _buildAnimatedLettersAndRunwayStage(screenSize),

                    const Spacer(),

                    // Bottom Progress & Status Text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                      child: Column(
                        children: [
                          Text(
                            _statusText,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              height: 6,
                              child: LinearProgressIndicator(
                                value: _progressValue,
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Individual Light Pastel Goods Pill (Pops up gently as scooter reaches its trigger)
  Widget _buildAnimatedPillWidget(int index, Size screenSize) {
    final data = _pillsData[index];
    final controller = _pillControllers[index];

    final double? top = data['topFactor'] != null
        ? screenSize.height * (data['topFactor'] as double)
        : null;
    final double? bottom = data['bottom'] as double?;
    final double? left = data['left'] as double?;
    final double? right = data['right'] as double?;

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final val = controller.value;
          final curveVal = Curves.easeOutBack.transform(val);
          final opacity = val.clamp(0.0, 1.0);
          final scale = 0.3 + (curveVal * 0.7);

          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
                decoration: BoxDecoration(
                  color: (data['bg'] as Color).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: data['borderColor'] as Color,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      data['icon'] as IconData,
                      size: 13.5,
                      color: data['textColor'] as Color,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      data['label'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: data['textColor'] as Color,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Central Stage: ZIPPO Letters Row + Tamil Sub-Badge + Road Runway with Scooter
  Widget _buildAnimatedLettersAndRunwayStage(Size screenSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ZIPPO Letters Row (Z - I - P - P - O)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (index) {
              final item = _lettersData[index];
              return _buildExtrudedLetterBox(
                char: item['char'] as String,
                desc: item['desc'] as String,
                isGreen: item['isGreen'] as bool,
                controller: _letterControllers[index],
              );
            }),
          ),
        ),

        const SizedBox(height: 16),

        // Melapalayam Tamil Badge
        _buildTamilSubBadge(),

        const SizedBox(height: 24),

        // Road Runway with Scooter gliding slowly from left to right
        _buildRoadWithMovingScooter(screenSize),
      ],
    );
  }

  // Individual 3D Extruded Letter
  Widget _buildExtrudedLetterBox({
    required String char,
    required String desc,
    required bool isGreen,
    required AnimationController controller,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final val = controller.value;
        final curveVal = Curves.elasticOut.transform(val);

        final opacity = val.clamp(0.0, 1.0);
        final scale = 0.4 + (curveVal * 0.6);
        final translateY = (1.0 - curveVal) * 35;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    char,
                    style: TextStyle(
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      color: isGreen
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF0F172A),
                      letterSpacing: -1,
                      shadows: isGreen
                          ? [
                              const Shadow(
                                offset: Offset(0, 2),
                                blurRadius: 0,
                                color: Color(0xFF15803D),
                              ),
                              const Shadow(
                                offset: Offset(0, 4),
                                blurRadius: 0,
                                color: Color(0xFF166534),
                              ),
                              Shadow(
                                offset: const Offset(0, 10),
                                blurRadius: 18,
                                color: const Color(0xFF16A34A).withValues(alpha: 0.4),
                              ),
                            ]
                          : [
                              const Shadow(
                                offset: Offset(0, 2),
                                blurRadius: 0,
                                color: Color(0xFF94A3B8),
                              ),
                              const Shadow(
                                offset: Offset(0, 4),
                                blurRadius: 0,
                                color: Color(0xFF64748B),
                              ),
                              Shadow(
                                offset: const Offset(0, 10),
                                blurRadius: 18,
                                color: Colors.black.withValues(alpha: 0.18),
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isGreen
                          ? const Color(0xFFF0FDF4)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isGreen
                            ? const Color(0xFFBBF7D0)
                            : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      desc,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: isGreen
                            ? const Color(0xFF15803D)
                            : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Melapalayam Tamil Badge
  Widget _buildTamilSubBadge() {
    return AnimatedBuilder(
      animation: _tamilBadgeController,
      builder: (context, child) {
        final val = _tamilBadgeController.value;
        final curveVal = Curves.easeOutBack.transform(val);

        return Opacity(
          opacity: val.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - curveVal) * 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 1.5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Color(0xFF10B981)],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Melapalayam',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFF475569),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '•',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'மேலப்பாளையம்',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF15803D),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 1.5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF10B981), Colors.transparent],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Road Track & Scooter Glide
  Widget _buildRoadWithMovingScooter(Size screenSize) {
    final trackWidth = screenSize.width;

    return SizedBox(
      height: 90,
      width: trackWidth,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          // Road Line Base
          Positioned(
            bottom: 22,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  height: 4,
                  color: const Color(0xFFE2E8F0),
                ),
                const SizedBox(height: 2),
                CustomPaint(
                  size: Size(trackWidth, 3),
                  painter: _DashedRoadPainter(),
                ),
              ],
            ),
          ),

          // Scooter Assembly moving gently and slowly across the screen
          AnimatedBuilder(
            animation: Listenable.merge([
              _bikeController,
              _engineBobController,
              _wheelSpinController,
            ]),
            builder: (context, child) {
              // Smooth bezier glide across full screen width
              final curvedT = Curves.easeInOutCubic.transform(_bikeController.value);
              final bikeX = -70.0 + (curvedT * (trackWidth + 90.0));
              final bobY = (_engineBobController.value - 0.5) * 4.0;

              return Positioned(
                bottom: 20 + bobY,
                left: bikeX,
                child: _buildScooterVehicle(),
              );
            },
          ),
        ],
      ),
    );
  }

  // Delivery Scooter with Headlight beam, Speed streaks, and Spinning Wheels
  Widget _buildScooterVehicle() {
    return SizedBox(
      width: 90,
      height: 65,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Speed Streaks behind scooter
          Positioned(
            left: -24,
            top: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 22,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 30,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF94A3B8).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 16,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34D399).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),

          // Forward Headlight Beam
          Positioned(
            right: -24,
            top: 14,
            child: Container(
              width: 32,
              height: 16,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(16),
                ),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFDE047).withValues(alpha: 0.6),
                    const Color(0xFFFDE047).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // The Scooter Graphics
          CustomPaint(
            size: const Size(80, 56),
            painter: _ScooterVectorPainter(wheelRotation: _wheelSpinController.value),
          ),
        ],
      ),
    );
  }
}

// Custom Painter for Organic Light Curves and Subtle Melapalayam Watermark Text
class _LandingCurvesAndWatermarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Gentle background curves
    final greenCurvePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    final orangeCurvePaint = Paint()
      ..color = const Color(0xFFF97316).withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;

    // Top gentle green curve wave
    final topPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.22)
      ..quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.28,
        size.width * 0.35,
        size.height * 0.18,
      )
      ..quadraticBezierTo(
        size.width * 0.15,
        size.height * 0.10,
        0,
        size.height * 0.16,
      )
      ..close();
    canvas.drawPath(topPath, greenCurvePaint);

    // Bottom sweeping orange & green curve wave
    final bottomPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, size.height * 0.74)
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.82,
        size.width * 0.45,
        size.height * 0.76,
      )
      ..quadraticBezierTo(
        size.width * 0.18,
        size.height * 0.70,
        0,
        size.height * 0.80,
      )
      ..close();
    canvas.drawPath(bottomPath, orangeCurvePaint);

    // Decorative curved hairline strokes
    final strokePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final arcPath1 = Path()
      ..moveTo(0, size.height * 0.38)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.32,
        size.width,
        size.height * 0.44,
      );
    canvas.drawPath(arcPath1, strokePaint);

    final arcPath2 = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.55,
        size.height * 0.72,
        size.width,
        size.height * 0.60,
      );
    canvas.drawPath(arcPath2, strokePaint..color = const Color(0xFFF97316).withValues(alpha: 0.07));

    // 2. Subtle Watermark Text: "MELAPALAYAM" across upper section
    final melapalayamPainter = TextPainter(
      text: TextSpan(
        text: 'MELAPALAYAM',
        style: TextStyle(
          fontSize: size.width * 0.105,
          fontWeight: FontWeight.w900,
          letterSpacing: 8,
          color: const Color(0xFF0F172A).withValues(alpha: 0.025),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    melapalayamPainter.paint(
      canvas,
      Offset(
        (size.width - melapalayamPainter.width) / 2,
        size.height * 0.28,
      ),
    );

    // 3. Subtle Tamil Watermark Text: "மேலப்பாளையம்" across lower section
    final tamilPainter = TextPainter(
      text: TextSpan(
        text: 'மேலப்பாளையம்',
        style: TextStyle(
          fontSize: size.width * 0.09,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
          color: const Color(0xFF16A34A).withValues(alpha: 0.035),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    tamilPainter.paint(
      canvas,
      Offset(
        (size.width - tamilPainter.width) / 2,
        size.height * 0.62,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom Painter for the High-Precision ZIPPO Delivery Scooter
class _ScooterVectorPainter extends CustomPainter {
  final double wheelRotation;

  _ScooterVectorPainter({required this.wheelRotation});

  @override
  void paint(Canvas canvas, Size size) {
    // Drop shadow under scooter
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.48, size.height * 0.95),
        width: size.width * 0.72,
        height: 6,
      ),
      shadowPaint,
    );

    // 1. Cargo Box (Orange with Green Outline)
    final boxPaint = Paint()..color = const Color(0xFFF97316);
    final boxRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.12, size.height * 0.18, 22, 20),
      const Radius.circular(4),
    );
    canvas.drawRRect(boxRRect, boxPaint);

    final boxBorder = Paint()
      ..color = const Color(0xFFEA580C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(boxRRect, boxBorder);

    // ZIPPO Z on cargo box
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Z',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(size.width * 0.12 + 6, size.height * 0.18 + 3));

    // 2. Scooter Body / Chassis
    final bodyPaint = Paint()..color = const Color(0xFFF97316);
    final bodyPath = Path()
      ..moveTo(size.width * 0.28, size.height * 0.65)
      ..lineTo(size.width * 0.52, size.height * 0.62)
      ..lineTo(size.width * 0.68, size.height * 0.45)
      ..lineTo(size.width * 0.74, size.height * 0.48)
      ..lineTo(size.width * 0.58, size.height * 0.76)
      ..lineTo(size.width * 0.28, size.height * 0.76)
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);

    // 3. Delivery Rider
    // Body (Green Jacket)
    final riderPaint = Paint()..color = const Color(0xFF15803D);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.40, size.height * 0.26, 16, 22),
        const Radius.circular(5),
      ),
      riderPaint,
    );

    // Helmet (Green with yellow visor)
    final helmetPaint = Paint()..color = const Color(0xFF16A34A);
    canvas.drawCircle(
      Offset(size.width * 0.54, size.height * 0.18),
      9,
      helmetPaint,
    );

    // Visor
    final visorPaint = Paint()
      ..color = const Color(0xFFFACC15)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.56, size.height * 0.17),
      Offset(size.width * 0.63, size.height * 0.17),
      visorPaint,
    );

    // Handlebar & Headlight
    final handlebarPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 2.5;
    canvas.drawLine(
      Offset(size.width * 0.66, size.height * 0.36),
      Offset(size.width * 0.75, size.height * 0.38),
      handlebarPaint,
    );

    final headlightPaint = Paint()..color = const Color(0xFFFACC15);
    canvas.drawCircle(
      Offset(size.width * 0.76, size.height * 0.42),
      3.5,
      headlightPaint,
    );

    // 4. Wheels with Animated Rotation
    _drawSpinningWheel(
      canvas,
      center: Offset(size.width * 0.26, size.height * 0.78),
      radius: 11,
      rotation: wheelRotation,
    );

    _drawSpinningWheel(
      canvas,
      center: Offset(size.width * 0.70, size.height * 0.78),
      radius: 11,
      rotation: wheelRotation,
    );
  }

  void _drawSpinningWheel(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double rotation,
  }) {
    // Tire
    final tirePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, tirePaint);

    // Rim
    final rimPaint = Paint()
      ..color = const Color(0xFFF97316)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1.5, rimPaint);

    // Inner Hub
    final hubPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 3.5, hubPaint);

    // Spokes rotating
    final spokePaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.2;

    for (int i = 0; i < 4; i++) {
      final angle = (rotation * 2 * math.pi) + (i * math.pi / 2);
      final dx = math.cos(angle) * (radius - 2.5);
      final dy = math.sin(angle) * (radius - 2.5);
      canvas.drawLine(center, Offset(center.dx + dx, center.dy + dy), spokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScooterVectorPainter oldDelegate) {
    return oldDelegate.wheelRotation != wheelRotation;
  }
}

// Dashed road painter
class _DashedRoadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    double x = 0;
    const dash = 12.0;
    const gap = 8.0;

    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(x + dash, 1), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
