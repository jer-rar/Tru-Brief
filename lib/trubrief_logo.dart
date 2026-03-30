import 'package:flutter/material.dart';
import 'dart:math' as math;

const Color _kOrange = Color(0xFFFF6200);

class TruBriefLogo extends StatelessWidget {
  final double size;
  const TruBriefLogo({super.key, this.size = 160});

  @override
  Widget build(BuildContext context) {
    final iconH = size * 0.58;
    final iconW = iconH * 0.88;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TruBriefIcon(width: iconW, height: iconH),
        SizedBox(width: size * 0.04),
        Container(width: size * 0.018, height: iconH * 0.72, color: _kOrange),
        SizedBox(width: size * 0.05),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Tru',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.315,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                      height: 1.0,
                    ),
                  ),
                  TextSpan(
                    text: 'Brief',
                    style: TextStyle(
                      color: _kOrange,
                      fontSize: size * 0.315,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'ULTIMATE NEWS',
              style: TextStyle(
                color: Colors.white60,
                fontSize: size * 0.072,
                fontWeight: FontWeight.w500,
                letterSpacing: size * 0.022,
                height: 1.4,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TruBriefIcon extends StatelessWidget {
  final double width;
  final double height;
  const TruBriefIcon({super.key, this.width = 70, this.height = 80});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _ShieldPainter()),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shield = _shieldPath(w, h);

    // Left half — white/light gray
    canvas.save();
    canvas.clipPath(shield);
    canvas.clipRect(Rect.fromLTWH(0, 0, w * 0.496, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFEFEFEF));
    _drawNewspaper(canvas, w, h);
    canvas.restore();

    // Right half — orange
    canvas.save();
    canvas.clipPath(shield);
    canvas.clipRect(Rect.fromLTWH(w * 0.504, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = _kOrange);
    _drawSignal(canvas, w, h);
    canvas.restore();

    // Center divider
    canvas.save();
    canvas.clipPath(shield);
    canvas.drawLine(
      Offset(w * 0.5, h * 0.04),
      Offset(w * 0.5, h * 0.90),
      Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..strokeWidth = w * 0.022,
    );
    canvas.restore();

    // Shield border
    canvas.drawPath(
      shield,
      Paint()
        ..color = const Color(0xFF222222)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.028
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawNewspaper(Canvas canvas, double w, double h) {
    final header = Paint()
      ..color = const Color(0xFF777777)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.048;

    final body = Paint()
      ..color = const Color(0xFFAAAAAA)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.030;

    final left = w * 0.08;
    final right = w * 0.44;
    final shortR = w * 0.36;

    canvas.drawLine(Offset(left, h * 0.30), Offset(right, h * 0.30), header);
    canvas.drawLine(Offset(left, h * 0.41), Offset(right, h * 0.41), body);
    canvas.drawLine(Offset(left, h * 0.50), Offset(right, h * 0.50), body);
    canvas.drawLine(Offset(left, h * 0.58), Offset(shortR, h * 0.58), body);
    canvas.drawLine(Offset(left, h * 0.67), Offset(right, h * 0.67), body);
    canvas.drawLine(Offset(left, h * 0.76), Offset(shortR - w * 0.04, h * 0.76), body);
  }

  void _drawSignal(Canvas canvas, double w, double h) {
    final px = w * 0.745;
    final py = h * 0.46;
    const startAngle = 197.0 * math.pi / 180.0;
    const sweepAngle = 146.0 * math.pi / 180.0;

    for (final r in [h * 0.075, h * 0.135, h * 0.195]) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(px, py), radius: r),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = h * 0.042,
      );
    }
    canvas.drawCircle(Offset(px, py), h * 0.038, Paint()..color = Colors.white);
  }

  Path _shieldPath(double w, double h) {
    final p = Path();
    p.moveTo(w * 0.15, h * 0.03);
    p.lineTo(w * 0.85, h * 0.03);
    p.quadraticBezierTo(w * 0.97, h * 0.03, w * 0.97, h * 0.15);
    p.lineTo(w * 0.97, h * 0.52);
    p.quadraticBezierTo(w * 0.97, h * 0.76, w * 0.5, h * 0.97);
    p.quadraticBezierTo(w * 0.03, h * 0.76, w * 0.03, h * 0.52);
    p.lineTo(w * 0.03, h * 0.15);
    p.quadraticBezierTo(w * 0.03, h * 0.03, w * 0.15, h * 0.03);
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LogoPreviewScreen extends StatefulWidget {
  const LogoPreviewScreen({super.key});

  @override
  State<LogoPreviewScreen> createState() => _LogoPreviewScreenState();
}

class _LogoPreviewScreenState extends State<LogoPreviewScreen> {
  double _size = 120;
  Color _bgColor = Colors.black;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Logo Preview', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: _bgColor,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TruBriefIcon(width: _size * 0.88, height: _size),
                  SizedBox(height: _size * 0.3),
                  TruBriefLogo(size: _size * 1.6),
                ],
              ),
            ),
          ),
          Container(
            color: const Color(0xFF1C1C1E),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Slider(
                  value: _size,
                  min: 50,
                  max: 200,
                  activeColor: _kOrange,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _size = v),
                ),
                Row(
                  children: [
                    const Text('Background:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(width: 8),
                    _BgButton(color: Colors.black, selected: _bgColor == Colors.black, onTap: () => setState(() => _bgColor = Colors.black)),
                    _BgButton(color: Colors.white, selected: _bgColor == Colors.white, onTap: () => setState(() => _bgColor = Colors.white)),
                    _BgButton(color: const Color(0xFF1C1C1E), selected: _bgColor == const Color(0xFF1C1C1E), onTap: () => setState(() => _bgColor = const Color(0xFF1C1C1E))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BgButton extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _BgButton({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _kOrange : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}
