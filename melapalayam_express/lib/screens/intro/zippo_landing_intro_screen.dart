import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../customer/customer_home_screen.dart';

class ZippoLandingIntroScreen extends StatefulWidget {
  const ZippoLandingIntroScreen({Key? key}) : super(key: key);

  @override
  State<ZippoLandingIntroScreen> createState() => _ZippoLandingIntroScreenState();
}

class _ZippoLandingIntroScreenState extends State<ZippoLandingIntroScreen>
    with TickerProviderStateMixin {
  // Phase controllers
  late AnimationController _logoPhaseController;
  late AnimationController _bikeController;
  late AnimationController _engineBobController;
  late AnimationController _wheelSpinController;

  // Letter reveal controllers
  late List<AnimationController> _letterControllers;

  // Tamil badge controller
  late AnimationController _tamilBadgeController;

  // Master fade out / exit controller
  late AnimationController _exitController;

  bool _isLogoPhase = true;
  bool _hasNavigated = false;
  String _statusText = "Calibrating Melapalayam delivery routes...";
  double _progressValue = 0.2;

  final List<Map<String, dynamic>> _lettersData = [
    {'char': 'Z', 'desc': 'Zero Wait', 'isGreen': false, 'trigger': 0.12},
    {'char': 'I', 'desc': 'Instant', 'isGreen': true, 'trigger': 0.32},
    {'char': 'P', 'desc': 'Pickup', 'isGreen': false, 'trigger': 0.52},
    {'char': 'P', 'desc': 'Parcel', 'isGreen': false, 'trigger': 0.72},
    {'char': 'O', 'desc': 'On-Demand', 'isGreen': true, 'trigger': 0.90},
  ];

  @override
  void initState() {
    super.initState();

    // 1. Initial Logo Phase
    _logoPhaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // 2. Bike Travel (Left to Right)
    _bikeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    // 3. Engine Bob (subtle suspension vibration)
    _engineBobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..repeat(reverse: true);

    // 4. Wheel Spin
    _wheelSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat();

    // 5. Letter controllers
    _letterControllers = List.generate(
      5,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 650),
      ),
    );

    // 6. Tamil Tag
    _tamilBadgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // 7. Exit Controller
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Listen to bike movement to trigger letters sequentially as the scooter passes them
    _bikeController.addListener(_onBikeProgress);

    // Kick off animation sequence
    _startAnimationTimeline();
  }

  void _onBikeProgress() {
    final progress = _bikeController.value;

    setState(() {
      _progressValue = 0.25 + (progress * 0.75);
    });

    for (int i = 0; i < _lettersData.length; i++) {
      final triggerPoint = _lettersData[i]['trigger'] as double;
      if (progress >= triggerPoint && !_letterControllers[i].isCompleted && !_letterControllers[i].isAnimating) {
        _letterControllers[i].forward();
        HapticFeedback.lightImpact();
      }
    }

    // When approaching the last letter, trigger the Tamil badge
    if (progress >= 0.88 && !_tamilBadgeController.isCompleted && !_tamilBadgeController.isAnimating) {
      _tamilBadgeController.forward();
    }
  }

  Future<void> _startAnimationTimeline() async {
    // 1. Show logo with scale/fade in
    await _logoPhaseController.forward();
    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;

    // Transition from Phase 1 to Phase 2
    setState(() {
      _isLogoPhase = false;
      _statusText = "ZIPPO rider cruising across Melapalayam...";
      _progressValue = 0.35;
    });

    // Start bike gliding left to right
    await _bikeController.forward();

    if (!mounted) return;

    setState(() {
      _statusText = "Welcome to ZIPPO! Arrived.";
      _progressValue = 1.0;
    });

    // Brief celebratory pause
    await Future.delayed(const Duration(milliseconds: 500));

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
    _logoPhaseController.dispose();
    _bikeController.removeListener(_onBikeProgress);
    _bikeController.dispose();
    _engineBobController.dispose();
    _wheelSpinController.dispose();
    for (final c in _letterControllers) {
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
            children: [
              // Ambient Background Glows
              Positioned(
                top: -80,
                left: -80,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF0FDF4).withOpacity(0.9),
                  ),
                ),
              ),
              Positioned(
                bottom: -80,
                right: -80,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFECFDF5).withOpacity(0.9),
                  ),
                ),
              ),

              // Main Column
              SafeArea(
                child: Column(
                  children: [
                    // Top Bar (Status & Skip Button)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
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
                              backgroundColor: const Color(0xFFF1F5F9),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Stage Area (Phase 1 Logo OR Phase 2 Animated Letters + Bike)
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 400),
                      crossFadeState: _isLogoPhase
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: _buildLogoPhaseWidget(),
                      secondChild: _buildAnimatedStageWidget(screenSize),
                    ),

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

  // Phase 1: Glowing App Logo Presentation
  Widget _buildLogoPhaseWidget() {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _logoPhaseController,
        curve: Curves.easeOut,
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(
            parent: _logoPhaseController,
            curve: Curves.easeOutBack,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    blurRadius: 30,
                    spreadRadius: 4,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFFD1FAE5),
                  width: 2,
                ),
              ),
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'MELAPALAYAM HYPER-LOCAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: Color(0xFF059669),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Starting Delivery Fleet...',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Phase 2: "Z I P P O" Letter Extrusion + Bike Runway
  Widget _buildAnimatedStageWidget(Size screenSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ZIPPO Letters Row
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

        // Road Runway with Moving Scooter
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
                                color: const Color(0xFF16A34A).withOpacity(0.4),
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
                                color: Colors.black.withOpacity(0.18),
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
                          color: Colors.black.withOpacity(0.03),
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
                        color: const Color(0xFF10B981).withOpacity(0.12),
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

          // Scooter Assembly moving left to right
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
                    color: const Color(0xFF10B981).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 30,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF94A3B8).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 16,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34D399).withOpacity(0.9),
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
                    const Color(0xFFFDE047).withOpacity(0.6),
                    const Color(0xFFFDE047).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // The Scooter Graphics (Vector / Logo Silhouette)
          CustomPaint(
            size: const Size(80, 56),
            painter: _ScooterVectorPainter(wheelRotation: _wheelSpinController.value),
          ),
        ],
      ),
    );
  }
}

// Custom Painter for the High-Precision ZIPPO Delivery Scooter
class _ScooterVectorPainter extends CustomPainter {
  final double wheelRotation;

  _ScooterVectorPainter({required this.wheelRotation});

  @override
  void paint(Canvas canvas, Size size) {
    // Drop shadow under scooter
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.48, size.height * 0.95),
        width: size.width * 0.72,
        height: 6,
      ),
      shadowPaint,
    );

    // 1. Cargo Box (Orange & Green Accent)
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
