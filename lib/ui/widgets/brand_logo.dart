import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';

/// How long the branded loading screen is held on every launch (the app waits at least this long).
const Duration kSplashDuration = Duration(milliseconds: 2600);

/// True until [kSplashDuration] has passed since launch; the router keeps the splash on screen meanwhile.
final splashHoldProvider = StateProvider<bool>((ref) => true);

/// Brand colours — identical to the launcher icon (assets/icon/icon.png).
const Color kBrandAmber = Color(0xFFE8A33D);
const Color kBrandBlue = Color(0xFF5B8DEF);
const Color kBrandInk = Color(0xFF0B0D10);

/// Draws the Prompt Forge "A" + blue dot exactly like the app icon, on the icon's 1024 x 1024 grid.
/// [legs], [bar] and [dot] are 0..1 animation progress values (all 1 = the finished logo).
class BrandLogoPainter extends CustomPainter {
  final double legs;
  final double bar;
  final double dot;
  const BrandLogoPainter({this.legs = 1, this.bar = 1, this.dot = 1});

  static const double _stroke = 76;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1024, size.height / 1024);

    final amber = Paint()
      ..color = kBrandAmber
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final legsPath = Path()
      ..moveTo(260, 700)
      ..lineTo(448, 320)
      ..lineTo(636, 700);
    final lp = legs.clamp(0.0, 1.0);
    if (lp > 0) {
      for (final m in legsPath.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * lp), amber);
      }
    }

    final bp = bar.clamp(0.0, 1.0);
    if (bp > 0) {
      final barPaint = Paint()
        ..color = kBrandAmber
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.butt
        ..isAntiAlias = true;
      const x0 = 333.0, x1 = 563.0, y = 550.0;
      canvas.drawLine(const Offset(x0, y), Offset(x0 + (x1 - x0) * bp, y), barPaint);
    }

    if (dot > 0) {
      canvas.drawCircle(
        const Offset(767.5, 287.5),
        73.5 * dot,
        Paint()
          ..color = kBrandBlue
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandLogoPainter old) => old.legs != legs || old.bar != bar || old.dot != dot;
}

/// The logo on its own (no tile).
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: const CustomPaint(painter: BrandLogoPainter()));
}

/// The logo on the dark rounded tile used by the launcher icon.
class BrandMarkTile extends StatelessWidget {
  final double size;
  final bool glow;
  const BrandMarkTile({super.key, this.size = 84, this.glow = true});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kBrandInk,
          borderRadius: BorderRadius.circular(size * 0.24),
          border: Border.all(color: kBrandAmber.withOpacity(0.28)),
          boxShadow: glow ? [BoxShadow(color: kBrandAmber.withOpacity(0.18), blurRadius: size * 0.4, spreadRadius: size * 0.02)] : null,
        ),
        child: const CustomPaint(painter: BrandLogoPainter()),
      );
}

/// Full-screen branded loading state: the A draws itself, the blue dot pops in, a light ring orbits the tile
/// and the status line cycles while the vault opens. Respects the system "reduce motion" setting.
class BrandSplash extends StatefulWidget {
  final List<String> messages;
  final String? tip;
  const BrandSplash({
    super.key,
    this.messages = const ['Opening your vault…', 'Reading your prompts…', 'Indexing templates and patterns…', 'Almost ready…'],
    this.tip,
  });

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));
  late final AnimationController _bar = AnimationController(vsync: this, duration: kSplashDuration - const Duration(milliseconds: 250));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  Timer? _msgTimer;
  int _msg = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
      _bar.value = 1;
    } else {
      _intro.forward();
      _bar.forward();
      _loop.repeat();
    }
    if (widget.messages.length > 1) {
      final step = (kSplashDuration.inMilliseconds / widget.messages.length).round();
      _msgTimer = Timer.periodic(Duration(milliseconds: step), (_) {
        if (mounted && _msg < widget.messages.length - 1) setState(() => _msg += 1);
      });
    }
  }

  @override
  void dispose() {
    _msgTimer?.cancel();
    _intro.dispose();
    _bar.dispose();
    _loop.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b, [Curve c = Curves.easeOutCubic]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: Listenable.merge([_intro, _loop]),
            builder: (context, _) {
              final t = _intro.value;
              final pulse = 0.5 + 0.5 * math.sin(_loop.value * 2 * math.pi);
              return SizedBox(
                width: 168,
                height: 168,
                child: CustomPaint(
                  painter: _RingPainter(angle: _loop.value * 2 * math.pi, opacity: _seg(t, 0.55, 1.0)),
                  child: Center(
                    child: Opacity(
                      opacity: _seg(t, 0.0, 0.18),
                      child: Transform.scale(
                        scale: 0.92 + 0.08 * _seg(t, 0.0, 0.4) + 0.012 * pulse,
                        child: Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            color: kBrandInk,
                            borderRadius: BorderRadius.circular(27),
                            border: Border.all(color: kBrandAmber.withOpacity(0.25 + 0.2 * pulse)),
                            boxShadow: [BoxShadow(color: kBrandAmber.withOpacity(0.10 + 0.12 * pulse), blurRadius: 34, spreadRadius: 1)],
                          ),
                          child: CustomPaint(
                            painter: BrandLogoPainter(
                              legs: _seg(t, 0.05, 0.55),
                              bar: _seg(t, 0.45, 0.68),
                              dot: _seg(t, 0.62, 1.0, Curves.elasticOut),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 26),
          FadeTransition(
            opacity: CurvedAnimation(parent: _intro, curve: const Interval(0.45, 0.85, curve: Curves.easeOut)),
            child: Column(children: [
              Text('Prompt Forge', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.text)),
              const SizedBox(height: 6),
              Text('Local-first prompt workspace', style: TextStyle(fontSize: 13.5, color: p.textTertiary, letterSpacing: 0.2)),
            ]),
          ),
          const SizedBox(height: 34),
          SizedBox(
            width: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: AnimatedBuilder(
                animation: _bar,
                builder: (context, _) => LinearProgressIndicator(value: Curves.easeInOut.transform(_bar.value), minHeight: 3, backgroundColor: p.border, valueColor: const AlwaysStoppedAnimation<Color>(kBrandAmber)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(widget.messages[_msg], key: ValueKey(_msg), style: TextStyle(fontSize: 13, color: p.textSecondary)),
            ),
          ),
          if (widget.tip != null) ...[
            const SizedBox(height: 36),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(widget.tip!, textAlign: TextAlign.center, style: TextStyle(color: p.textTertiary, fontSize: 12.5, height: 1.4)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double angle;
  final double opacity;
  const _RingPainter({required this.angle, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - 4;
    final shader = SweepGradient(
      colors: [kBrandAmber.withOpacity(0), kBrandAmber.withOpacity(opacity), kBrandBlue.withOpacity(opacity * 0.9), kBrandBlue.withOpacity(0)],
      stops: const [0.0, 0.16, 0.30, 0.42],
      transform: GradientRotation(angle),
    ).createShader(rect);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.angle != angle || old.opacity != opacity;
}
