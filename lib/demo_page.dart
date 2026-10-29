import 'dart:async';

import 'package:flutter/material.dart';

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _water;
  Timer? _timer;
  int _step = 0;
  bool _running = false;
  bool _rainExpected = false;
  double _sugarMoisture = 31;
  double _milletMoisture = 27;

  static const _steps = [
    ('Reading sensors', 'Moisture, tank level and local weather are checked.'),
    ('Checking the forecast', 'Rain probability is considered before pumping.'),
    ('Calculating crop doses', 'Each crop gets its own moisture target.'),
    ('Irrigating precisely', 'The shared pump sends only the required amount.'),
    ('Targets reached', 'Flow stops and the new moisture is verified.'),
  ];

  bool get _pumpOn => _running && _step == 3 && !_rainExpected;

  @override
  void initState() {
    super.initState();
    _water = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _water.dispose();
    super.dispose();
  }

  void _runDemo() {
    _timer?.cancel();
    _water.stop();
    setState(() {
      _running = true;
      _step = 0;
      _sugarMoisture = 31;
      _milletMoisture = 27;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 1350), (timer) {
      if (!mounted) return;
      if (_step == 2 && _rainExpected) {
        timer.cancel();
        setState(() {
          _step = 1;
          _running = false;
        });
        return;
      }
      if (_step >= _steps.length - 1) {
        timer.cancel();
        _water.stop();
        setState(() => _running = false);
        return;
      }
      setState(() {
        _step++;
        if (_step == 3) {
          _water.repeat();
          _sugarMoisture = 62;
          _milletMoisture = 34;
        }
        if (_step == 4) _water.stop();
      });
    });
  }

  void _toggleRain(bool value) {
    _timer?.cancel();
    _water.stop();
    setState(() {
      _rainExpected = value;
      _running = false;
      _step = value ? 1 : 0;
      _sugarMoisture = 31;
      _milletMoisture = 27;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F1),
      body: SelectionArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _DemoHero(onBack: () => Navigator.maybePop(context)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 72),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -34),
                          child: _ControlDeck(
                            pumpOn: _pumpOn,
                            running: _running,
                            rainExpected: _rainExpected,
                            onRainChanged: _toggleRain,
                            onRun: _runDemo,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _SectionIntro(
                          eyebrow: 'LIVE SYSTEM WALKTHROUGH',
                          title: _rainExpected
                              ? 'Rain is coming. Every drop stays in the tank.'
                              : 'One pump. Two crop profiles. No guesswork.',
                          body: _rainExpected
                              ? 'AquaCrop delays irrigation when the forecast can do the job for free. Turn off rain mode to watch precision irrigation.'
                              : 'The same water source serves both trays, but the software calculates a different dose for each crop.',
                        ),
                        const SizedBox(height: 28),
                        _SystemDiagram(
                          animation: _water,
                          pumpOn: _pumpOn,
                          rainExpected: _rainExpected,
                        ),
                        const SizedBox(height: 22),
                        LayoutBuilder(
                          builder: (context, box) {
                            final wide = box.maxWidth >= 900;
                            final cards = [
                              _ZoneCard(
                                zone: 'ZONE 1',
                                crop: 'Sugarcane',
                                icon: Icons.grass_rounded,
                                demand: 'High water demand',
                                moisture: _sugarMoisture,
                                target: 62,
                                allocation: '1.8 L',
                                color: const Color(0xFF16815F),
                              ),
                              _ZoneCard(
                                zone: 'ZONE 2',
                                crop: 'Pearl millet',
                                icon: Icons.eco_rounded,
                                demand: 'Low water demand',
                                moisture: _milletMoisture,
                                target: 34,
                                allocation: '0.5 L',
                                color: const Color(0xFFC58B24),
                              ),
                            ];
                            if (!wide) {
                              return Column(
                                children: [
                                  cards.first,
                                  const SizedBox(height: 16),
                                  cards.last,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: cards.first),
                                const SizedBox(width: 18),
                                Expanded(child: cards.last),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 54),
                        const _SectionIntro(
                          eyebrow: 'THE SMART LOOP',
                          title: 'From sensor reading to a verified result',
                          body: 'Every decision is explainable. The system shows what it measured, why it acted, and when it stopped.',
                        ),
                        const SizedBox(height: 24),
                        _DecisionSteps(active: _step, running: _running),
                        const SizedBox(height: 34),
                        _DecisionCard(
                          step: _step,
                          running: _running,
                          rainExpected: _rainExpected,
                          title: _steps[_step].$1,
                          detail: _rainExpected && !_running
                              ? 'Forecast says rain is likely, so AquaCrop keeps the pump OFF and checks again later.'
                              : _steps[_step].$2,
                        ),
                        const SizedBox(height: 54),
                        const _HardwareStrip(),
                      ],
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
}

class _DemoHero extends StatelessWidget {
  const _DemoHero({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 82),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF063B2F), Color(0xFF0A6A50)],
      ),
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Color(0xFF8AE0B9),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AquaCrop',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onBack,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Dashboard'),
                ),
              ],
            ),
            const SizedBox(height: 66),
            const Text(
              'SMART IRRIGATION, MADE VISIBLE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFA8E7CF),
                fontSize: 12,
                letterSpacing: 2.1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'See every drop\nmake a decision.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: MediaQuery.sizeOf(context).width < 600 ? 42 : 64,
                height: .98,
                letterSpacing: -2.3,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: const Text(
                'A two-zone prototype that combines live sensors, crop needs and local rain forecasts before starting a shared water pump.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFD2E8DF),
                  fontSize: 17,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ControlDeck extends StatelessWidget {
  const _ControlDeck({
    required this.pumpOn,
    required this.running,
    required this.rainExpected,
    required this.onRainChanged,
    required this.onRun,
  });
  final bool pumpOn;
  final bool running;
  final bool rainExpected;
  final ValueChanged<bool> onRainChanged;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFDDE9E2)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18043B2E),
          blurRadius: 28,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Wrap(
      spacing: 16,
      runSpacing: 14,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _DemoPill(
          icon: Icons.sensors_rounded,
          label: 'Sensors online',
          color: const Color(0xFF14835F),
        ),
        _DemoPill(
          icon: Icons.power_settings_new_rounded,
          label: pumpOn ? 'Pump ON' : 'Pump OFF',
          color: pumpOn ? const Color(0xFF16815F) : const Color(0xFF687A72),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_rounded, color: Color(0xFF4E76C7)),
            const SizedBox(width: 8),
            const Text(
              'Rain forecast',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Switch(value: rainExpected, onChanged: onRainChanged),
          ],
        ),
        FilledButton.icon(
          onPressed: running ? null : onRun,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0C7656),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          ),
          icon: Icon(running ? Icons.sync_rounded : Icons.play_arrow_rounded),
          label: Text(running ? 'Demo running…' : 'Run irrigation demo'),
        ),
      ],
    ),
  );
}

class _DemoPill extends StatelessWidget {
  const _DemoPill({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({
    required this.eyebrow,
    required this.title,
    required this.body,
  });
  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        eyebrow,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF12805D),
          fontSize: 12,
          letterSpacing: 1.8,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 9),
      Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: const Color(0xFF12382D),
          fontSize: MediaQuery.sizeOf(context).width < 600 ? 28 : 38,
          height: 1.1,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64766F),
            height: 1.5,
            fontSize: 16,
          ),
        ),
      ),
    ],
  );
}

class _SystemDiagram extends StatelessWidget {
  const _SystemDiagram({
    required this.animation,
    required this.pumpOn,
    required this.rainExpected,
  });
  final Animation<double> animation;
  final bool pumpOn;
  final bool rainExpected;

  @override
  Widget build(BuildContext context) => Container(
    height: 340,
    decoration: BoxDecoration(
      color: const Color(0xFFECF4EF),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFFD7E6DD)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => CustomPaint(
          painter: _FlowPainter(
            progress: animation.value,
            pumpOn: pumpOn,
            rainExpected: rainExpected,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _FlowPainter extends CustomPainter {
  const _FlowPainter({
    required this.progress,
    required this.pumpOn,
    required this.rainExpected,
  });
  final double progress;
  final bool pumpOn;
  final bool rainExpected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final left = size.width * .24;
    final right = size.width * .76;
    final pipe = Paint()
      ..color = const Color(0xFF92AFA3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final water = Paint()
      ..color = const Color(0xFF25A9E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final paths = [
      Path()
        ..moveTo(center, 63)
        ..lineTo(center, 146),
      Path()
        ..moveTo(center, 146)
        ..lineTo(left, 243),
      Path()
        ..moveTo(center, 146)
        ..lineTo(right, 243),
    ];
    for (final path in paths) {
      canvas.drawPath(path, pipe);
      if (pumpOn) canvas.drawPath(path, water);
    }

    _tank(canvas, Offset(center, 45));
    _pump(canvas, Offset(center, 146));
    _tray(canvas, Offset(left, 258), const Color(0xFF16815F), true);
    _tray(canvas, Offset(right, 258), const Color(0xFFC58B24), false);

    if (pumpOn) {
      for (var i = 0; i < 4; i++) {
        _dropOnPath(canvas, paths[0], (progress + i / 4) % 1);
        _dropOnPath(canvas, paths[1], (progress + i / 4) % 1);
      }
      for (var i = 0; i < 2; i++) {
        _dropOnPath(canvas, paths[2], (progress + i / 2) % 1);
      }
    }

    if (rainExpected) {
      final cloud = Paint()..color = const Color(0xFF7595C9);
      canvas.drawCircle(Offset(size.width - 72, 50), 20, cloud);
      canvas.drawCircle(Offset(size.width - 47, 50), 16, cloud);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width - 60, 62),
          width: 68,
          height: 27,
        ),
        cloud,
      );
      final rain = Paint()
        ..color = const Color(0xFF37A4E4)
        ..strokeWidth = 3;
      for (var i = 0; i < 4; i++) {
        final x = size.width - 85 + i * 16;
        canvas.drawLine(Offset(x, 80), Offset(x - 4, 94), rain);
      }
    }
  }

  void _tank(Canvas canvas, Offset center) {
    final tank = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 74, height: 60),
      const Radius.circular(14),
    );
    canvas.drawRRect(tank, Paint()..color = const Color(0xFFFFFFFF));
    final water = RRect.fromRectAndCorners(
      Rect.fromLTWH(center.dx - 31, center.dy, 62, 24),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );
    canvas.drawRRect(water, Paint()..color = const Color(0xFF76CDF0));
    _label(canvas, 'TANK', Offset(center.dx, center.dy - 7));
  }

  void _pump(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 31, Paint()..color = const Color(0xFF0B6049));
    final icon = TextPainter(
      text: const TextSpan(
        text: 'P',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, center - Offset(icon.width / 2, icon.height / 2));
  }

  void _tray(Canvas canvas, Offset center, Color color, bool tall) {
    final soil = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 116, height: 28),
      const Radius.circular(8),
    );
    canvas.drawRRect(soil, Paint()..color = const Color(0xFF815A3B));
    final plant = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final stemTop = center.dy - (tall ? 64 : 47);
    canvas.drawLine(
      Offset(center.dx, center.dy - 10),
      Offset(center.dx, stemTop),
      plant,
    );
    for (final side in [-1, 1]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + side * 15, stemTop + (tall ? 18 : 14)),
          width: 30,
          height: 13,
        ),
        plant,
      );
    }
    _label(
      canvas,
      tall ? 'SUGARCANE' : 'PEARL MILLET',
      Offset(center.dx, center.dy + 30),
    );
  }

  void _dropOnPath(Canvas canvas, Path path, double position) {
    final metrics = path.computeMetrics().first;
    final tangent = metrics.getTangentForOffset(metrics.length * position);
    if (tangent != null) {
      canvas.drawCircle(
        tangent.position,
        6,
        Paint()..color = const Color(0xFFBCEBFF),
      );
    }
  }

  void _label(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF25483D),
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: .8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _FlowPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.pumpOn != pumpOn ||
      oldDelegate.rainExpected != rainExpected;
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.zone,
    required this.crop,
    required this.icon,
    required this.demand,
    required this.moisture,
    required this.target,
    required this.allocation,
    required this.color,
  });
  final String zone;
  final String crop;
  final IconData icon;
  final String demand;
  final double moisture;
  final int target;
  final String allocation;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFDCE8E1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zone,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    crop,
                    style: const TextStyle(
                      color: Color(0xFF173C31),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            _DemoPill(
              icon: Icons.water_drop_rounded,
              label: demand,
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Text(
              'Soil moisture',
              style: TextStyle(color: Color(0xFF65766F)),
            ),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(end: moisture),
              duration: const Duration(milliseconds: 850),
              builder: (context, value, _) => Text(
                '${value.round()}%',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        TweenAnimationBuilder<double>(
          tween: Tween(end: moisture / 100),
          duration: const Duration(milliseconds: 850),
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 10,
            borderRadius: BorderRadius.circular(99),
            color: color,
            backgroundColor: color.withValues(alpha: .12),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _Value(label: 'Target', value: '$target%'),
            ),
            Container(width: 1, height: 38, color: const Color(0xFFE0E9E4)),
            Expanded(
              child: _Value(label: 'Calculated dose', value: allocation),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(color: Color(0xFF71817A))),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
      ),
    ],
  );
}

class _DecisionSteps extends StatelessWidget {
  const _DecisionSteps({required this.active, required this.running});
  final int active;
  final bool running;

  static const labels = [
    'Sense',
    'Forecast',
    'Calculate',
    'Irrigate',
    'Verify',
  ];
  static const icons = [
    Icons.sensors_rounded,
    Icons.cloud_rounded,
    Icons.calculate_rounded,
    Icons.water_drop_rounded,
    Icons.verified_rounded,
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 900;
      return Flex(
        direction: compact ? Axis.vertical : Axis.horizontal,
        children: List.generate(labels.length, (index) {
          final selected = index == active;
          final complete = index < active || (!running && active == 4);
          return ExpandedIf(
            enabled: !compact,
            child: Padding(
              padding: EdgeInsets.only(
                right: compact ? 0 : (index == labels.length - 1 ? 0 : 8),
                bottom: compact ? 8 : 0,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF0B7154)
                      : complete
                      ? const Color(0xFFE0F2E9)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE7E1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      complete ? Icons.check_rounded : icons[index],
                      size: 19,
                      color: selected ? Colors.white : const Color(0xFF167B5D),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      labels[index],
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFF24483D),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      );
    },
  );
}

class ExpandedIf extends StatelessWidget {
  const ExpandedIf({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => enabled
      ? Expanded(child: child)
      : SizedBox(width: double.infinity, child: child);
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.step,
    required this.running,
    required this.rainExpected,
    required this.title,
    required this.detail,
  });
  final int step;
  final bool running;
  final bool rainExpected;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 350),
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: rainExpected ? const Color(0xFFEAF1FC) : const Color(0xFF073D31),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: rainExpected
                ? const Color(0xFF4F76BD).withValues(alpha: .12)
                : Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            rainExpected
                ? Icons.umbrella_rounded
                : step == 4
                ? Icons.check_circle_rounded
                : Icons.auto_awesome_rounded,
            color: rainExpected ? const Color(0xFF4F76BD) : Colors.white,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Column(
              key: ValueKey('$step-$rainExpected-$running'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: rainExpected
                        ? const Color(0xFF284C75)
                        : Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  detail,
                  style: TextStyle(
                    color: rainExpected
                        ? const Color(0xFF57708B)
                        : const Color(0xFFB9D4CA),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _HardwareStrip extends StatelessWidget {
  const _HardwareStrip();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E8),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFF0DFB7)),
    ),
    child: Column(
      children: [
        const Text(
          'THE PHYSICAL PROTOTYPE',
          style: TextStyle(
            color: Color(0xFF9B6917),
            letterSpacing: 1.4,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 13),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: const [
            _HardwareItem(Icons.memory_rounded, 'ESP32-S3'),
            _HardwareItem(Icons.sensors_rounded, 'Soil sensors'),
            _HardwareItem(Icons.thermostat_rounded, 'DHT22'),
            _HardwareItem(Icons.water_rounded, 'Rain + flow'),
            _HardwareItem(Icons.power_rounded, 'Relay + pump'),
            _HardwareItem(Icons.cloud_sync_rounded, 'MQTT + weather'),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Sensor data travels through MQTT to the Flutter app. The same Dart interface runs on Web, Android, iOS, macOS and Windows.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF735C33), height: 1.45),
        ),
      ],
    ),
  );
}

class _HardwareItem extends StatelessWidget {
  const _HardwareItem(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .75),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF9B6917)),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
