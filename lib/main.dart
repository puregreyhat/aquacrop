import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'farm_data.dart';
import 'mqtt_farm_service.dart';

void main() => runApp(const SmartAgriApp());

FarmService createFarmService() {
  const username = String.fromEnvironment('MQTT_USERNAME');
  const password = String.fromEnvironment('MQTT_PASSWORD');
  if (username.isEmpty || password.isEmpty) return DemoFarmService();
  return MqttFarmService(
    host: '8255d88bbacc45fd89c2580a5887a138.s1.eu.hivemq.cloud',
    username: username,
    password: password,
  );
}

class SmartAgriApp extends StatelessWidget {
  const SmartAgriApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AquaCrop',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF087A55),
        surface: const Color(0xFFF6F9F7),
      ),
      scaffoldBackgroundColor: const Color(0xFFF2F6F4),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: Color(0xFFE1EAE5)),
        ),
      ),
    ),
    home: FarmShell(service: createFarmService()),
  );
}

enum AppPage {
  home('Home', Icons.home_rounded),
  dashboard('Dashboard', Icons.dashboard_rounded),
  zones('Zones', Icons.grass_rounded),
  live('Live data', Icons.sensors_rounded),
  irrigation('Irrigation', Icons.water_drop_rounded),
  weather('Weather', Icons.cloud_rounded),
  analytics('Analytics', Icons.bar_chart_rounded),
  crops('Crop profiles', Icons.eco_rounded),
  alerts('Alerts', Icons.notifications_rounded),
  settings('Settings', Icons.settings_rounded);

  const AppPage(this.label, this.icon);
  final String label;
  final IconData icon;
}

class FarmShell extends StatefulWidget {
  const FarmShell({super.key, required this.service});
  final FarmService service;

  @override
  State<FarmShell> createState() => _FarmShellState();
}

class _FarmShellState extends State<FarmShell> {
  AppPage page = AppPage.home;
  FarmSnapshot? data;
  bool automatic = true;
  bool changingPump = false;
  StreamSubscription<FarmSnapshot>? subscription;

  static const mobilePages = [
    AppPage.home,
    AppPage.zones,
    AppPage.irrigation,
    AppPage.analytics,
  ];

  @override
  void initState() {
    super.initState();
    subscription = widget.service.updates.listen((value) {
      if (mounted) setState(() => data = value);
    });
    widget.service.read().then((value) {
      if (mounted) setState(() => data = value);
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    widget.service.close();
    super.dispose();
  }

  Future<void> togglePump() async {
    if (data == null || changingPump) return;
    setState(() => changingPump = true);
    final next = await widget.service.setPump(!data!.pumpOn);
    if (!mounted) return;
    setState(() {
      data = next;
      changingPump = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next.pumpOn ? 'Shared pump started' : 'Shared pump stopped',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void select(AppPage value) {
    setState(() => page = value);
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = data;
    if (snapshot == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        final compact = constraints.maxWidth < 650;
        return Scaffold(
          drawer: desktop
              ? null
              : Drawer(
                  child: SafeArea(
                    child: AppMenu(selected: page, onSelect: select),
                  ),
                ),
          appBar: desktop
              ? null
              : AppBar(
                  title: const Brand(compact: true),
                  actions: [
                    StatusPill(
                      label: snapshot.connected ? 'MQTT live' : 'Demo',
                      color: snapshot.connected
                          ? const Color(0xFF15966A)
                          : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
          body: Row(
            children: [
              if (desktop)
                SizedBox(
                  width: 248,
                  child: AppMenu(selected: page, onSelect: select),
                ),
              Expanded(
                child: SafeArea(
                  left: desktop,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 28,
                      desktop ? 26 : 16,
                      compact ? 16 : 28,
                      100,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: buildPage(snapshot),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: mobilePages.contains(page)
                      ? mobilePages.indexOf(page)
                      : 0,
                  onDestinationSelected: (index) =>
                      setState(() => page = mobilePages[index]),
                  destinations: mobilePages
                      .map(
                        (item) => NavigationDestination(
                          icon: Icon(item.icon),
                          label: item.label,
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }

  Widget buildPage(FarmSnapshot snapshot) => switch (page) {
    AppPage.home => HomePage(
      data: snapshot,
      onPump: togglePump,
      busy: changingPump,
    ),
    AppPage.dashboard => DashboardPage(
      data: snapshot,
      onPump: togglePump,
      busy: changingPump,
    ),
    AppPage.zones => ZonesPage(data: snapshot),
    AppPage.live => LiveDataPage(data: snapshot),
    AppPage.irrigation => IrrigationPage(
      data: snapshot,
      automatic: automatic,
      onMode: (value) => setState(() => automatic = value),
      onPump: togglePump,
      busy: changingPump,
    ),
    AppPage.weather => WeatherPage(data: snapshot),
    AppPage.analytics => AnalyticsPage(data: snapshot),
    AppPage.crops => CropsPage(data: snapshot),
    AppPage.alerts => const AlertsPage(),
    AppPage.settings => const SettingsPage(),
  };
}

class AppMenu extends StatelessWidget {
  const AppMenu({super.key, required this.selected, required this.onSelect});
  final AppPage selected;
  final ValueChanged<AppPage> onSelect;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF073D31),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Brand(),
          ),
          const SizedBox(height: 26),
          Expanded(
            child: ListView(
              children: AppPage.values.map((item) {
                final active = selected == item;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    selected: active,
                    selectedTileColor: Colors.white.withValues(alpha: .12),
                    textColor: const Color(0xFFD8EAE3),
                    selectedColor: Colors.white,
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () => onSelect(item),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(color: Color(0xFF2B5E51)),
          const ListTile(
            leading: CircleAvatar(child: Text('A')),
            title: Text(
              'Akash',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Project user',
              style: TextStyle(color: Color(0xFFB2CCC2)),
            ),
          ),
        ],
      ),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: compact
              ? const Color(0xFFE0F4EA)
              : Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          Icons.water_drop_rounded,
          color: compact ? const Color(0xFF087A55) : const Color(0xFF78E0AF),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AquaCrop',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 18 : 21,
                fontWeight: FontWeight.w800,
                color: compact ? const Color(0xFF12382D) : Colors.white,
              ),
            ),
            if (!compact)
              const Text(
                'Smart irrigation',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xFFB9D4CA), fontSize: 12),
              ),
          ],
        ),
      ),
    ],
  );
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.data,
    required this.onPump,
    required this.busy,
  });
  final FarmSnapshot data;
  final VoidCallback onPump;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        title: 'Good morning, Akash',
        subtitle: 'Here is what your farm needs today.',
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 760;
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpandedIf(
                enabled: wide,
                flex: 3,
                child: RecommendationCard(
                  rainProbability: data.rainProbability,
                ),
              ),
              SizedBox(width: wide ? 18 : 0, height: wide ? 0 : 18),
              ExpandedIf(
                enabled: wide,
                flex: 2,
                child: WeatherNow(data: data),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, box) {
          return ResponsiveGrid(
            columns: box.maxWidth >= 760 ? 2 : 1,
            children: data.zones
                .map((zone) => ZoneSummary(zone: zone))
                .toList(),
          );
        },
      ),
      const SizedBox(height: 20),
      PumpCard(data: data, onPump: onPump, busy: busy, simple: true),
    ],
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.data,
    required this.onPump,
    required this.busy,
  });
  final FarmSnapshot data;
  final VoidCallback onPump;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        title: 'Dashboard',
        subtitle: 'Detailed farm performance and sensor telemetry.',
      ),
      const SizedBox(height: 20),
      ResponsiveGrid(
        columns: MediaQuery.sizeOf(context).width > 1180 ? 4 : 2,
        children: [
          MetricCard(
            icon: Icons.thermostat_rounded,
            label: 'Temperature',
            value: '${data.temperature.toStringAsFixed(0)}°C',
            note: 'DHT22 · normal',
            color: const Color(0xFFF97316),
          ),
          MetricCard(
            icon: Icons.water_rounded,
            label: 'Humidity',
            value: '${data.humidity.toStringAsFixed(1)}%',
            note: 'DHT22 · comfortable',
            color: const Color(0xFF0EA5E9),
          ),
          MetricCard(
            icon: Icons.cloud_rounded,
            label: 'Rain probability',
            value: '${data.rainProbability}%',
            note: 'Within 8 hours',
            color: const Color(0xFF6366F1),
          ),
          MetricCard(
            icon: Icons.battery_4_bar_rounded,
            label: 'Tank level',
            value: '${data.tankLevel}%',
            note: 'Sufficient',
            color: const Color(0xFF15966A),
          ),
        ],
      ),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 900;
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpandedIf(
                enabled: wide,
                flex: 3,
                child: ChartCard(
                  title: 'Soil moisture · last 24 hours',
                  child: TrendChart(
                    seriesA: [68, 64, 66, 59, 57, 44, 34, 32],
                    seriesB: [60, 58, 55, 53, 48, 46, 43, 41],
                  ),
                ),
              ),
              SizedBox(width: wide ? 18 : 0, height: wide ? 0 : 18),
              ExpandedIf(
                enabled: wide,
                flex: 2,
                child: PumpCard(data: data, onPump: onPump, busy: busy),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 900;
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpandedIf(
                enabled: wide,
                child: ChartCard(
                  title: 'Water use · last 7 days',
                  child: BarChart(values: [2.5, 4, 3.2, 5.1, 2.8, 3.5, 3.2]),
                ),
              ),
              SizedBox(width: wide ? 18 : 0, height: wide ? 0 : 18),
              ExpandedIf(
                enabled: wide,
                child: SensorHealth(data: data),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 18),
      const WeeklyPlan(),
    ],
  );
}

class ZonesPage extends StatelessWidget {
  const ZonesPage({super.key, required this.data});
  final FarmSnapshot data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        title: 'Zones',
        subtitle: 'Two crop areas monitored by one shared pump.',
      ),
      const SizedBox(height: 20),
      ResponsiveGrid(
        columns: MediaQuery.sizeOf(context).width >= 850 ? 2 : 1,
        children: data.zones.map((zone) => ZoneDetailCard(zone: zone)).toList(),
      ),
      const SizedBox(height: 18),
      const InfoBanner(
        icon: Icons.info_outline_rounded,
        title: 'Shared irrigation line',
        text: 'Starting the pump sends water to both zones. Recommendations remain separate so the prototype can compare crop requirements.',
      ),
    ],
  );
}

class LiveDataPage extends StatelessWidget {
  const LiveDataPage({super.key, required this.data});
  final FarmSnapshot data;

  @override
  Widget build(BuildContext context) {
    final readings = [
      (
        'Zone 1 moisture',
        '${data.zones[0].moisture}%',
        Icons.grass_rounded,
        const Color(0xFF15966A),
      ),
      (
        'Soil raw (GPIO 1)',
        '${data.soilRaw} ADC',
        Icons.memory_rounded,
        const Color(0xFF64756F),
      ),
      (
        'Temperature',
        '${data.temperature.toStringAsFixed(0)}°C',
        Icons.thermostat_rounded,
        const Color(0xFFF97316),
      ),
      (
        'Humidity',
        '${data.humidity.toStringAsFixed(1)}%',
        Icons.water_rounded,
        const Color(0xFF0EA5E9),
      ),
      (
        'Rain sensor (GPIO 3)',
        data.raining ? 'WET / RAIN' : 'DRY / NO RAIN',
        Icons.cloud_rounded,
        const Color(0xFF6366F1),
      ),
      (
        'Water level (GPIO 2)',
        '${data.waterLevelRaw} ADC',
        Icons.battery_4_bar_rounded,
        const Color(0xFF15966A),
      ),
      (
        'Flow pulses (GPIO 21)',
        '${data.flowPulses} / ${data.sampleIntervalMs / 1000}s',
        Icons.speed_rounded,
        const Color(0xFF0891B2),
      ),
      (
        'Data source',
        data.connected ? 'HiveMQ live' : 'Demo values',
        Icons.cloud_sync_rounded,
        data.connected ? const Color(0xFF15966A) : const Color(0xFFF59E0B),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'Live sensor data',
          subtitle: data.connected
              ? 'ESP32-S3 telemetry received through HiveMQ.'
              : 'Demo values matching the ESP32-S3 telemetry fields.',
        ),
        const SizedBox(height: 20),
        ResponsiveGrid(
          columns: MediaQuery.sizeOf(context).width >= 1000 ? 4 : 2,
          children: readings
              .map(
                (reading) => MetricCard(
                  icon: reading.$3,
                  label: reading.$1,
                  value: reading.$2,
                  note: data.connected ? 'MQTT update' : 'Prototype demo',
                  color: reading.$4,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        const InfoBanner(
          icon: Icons.tune_rounded,
          title: 'Flow calibration required',
          text: 'The ESP sends pulse counts every 2.5 seconds. Convert them to L/min only after measuring the pulses produced by one known litre.',
        ),
      ],
    );
  }
}

class IrrigationPage extends StatelessWidget {
  const IrrigationPage({
    super.key,
    required this.data,
    required this.automatic,
    required this.onMode,
    required this.onPump,
    required this.busy,
  });
  final FarmSnapshot data;
  final bool automatic;
  final ValueChanged<bool> onMode;
  final VoidCallback onPump;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        title: 'Irrigation control',
        subtitle: 'One shared pump, protected by tank and weather checks.',
      ),
      const SizedBox(height: 20),
      RecommendationCard(rainProbability: data.rainProbability),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 760;
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpandedIf(
                enabled: wide,
                flex: 3,
                child: PumpCard(
                  data: data,
                  onPump: onPump,
                  busy: busy,
                  modeControl: false,
                ),
              ),
              SizedBox(width: wide ? 18 : 0, height: wide ? 0 : 18),
              ExpandedIf(
                enabled: wide,
                flex: 2,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Operating mode',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('Automatic'),
                            icon: Icon(Icons.auto_awesome_rounded),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text('Manual'),
                            icon: Icon(Icons.touch_app_rounded),
                          ),
                        ],
                        selected: {automatic},
                        onSelectionChanged: (values) => onMode(values.first),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        automatic
                            ? 'Weather and sensor rules decide when watering is safe.'
                            : 'You control the pump; safety checks still remain active.',
                        style: const TextStyle(
                          color: Color(0xFF5F716A),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 18),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today’s water plan',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 16),
            ...data.zones.map(
              (zone) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(zone.colorValue)
                          .withValues(alpha: .12),
                      child: Icon(
                        Icons.eco_rounded,
                        color: Color(zone.colorValue),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${zone.name} · ${zone.crop}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${zone.litresNeeded} L',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            const Row(
              children: [
                Icon(Icons.schedule_rounded),
                SizedBox(width: 10),
                Expanded(child: Text('Recheck weather at 6:00 PM')),
                Text(
                  'Delayed',
                  style: TextStyle(
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key, required this.data});
  final FarmSnapshot data;

  @override
  Widget build(BuildContext context) {
    const hours = [
      ('Now', Icons.wb_sunny_rounded, '28°', '0%'),
      ('4h', Icons.wb_sunny_rounded, '31°', '10%'),
      ('8h', Icons.cloud_rounded, '26°', '78%'),
      ('12h', Icons.thunderstorm_rounded, '24°', '80%'),
      ('18h', Icons.cloud_rounded, '23°', '45%'),
      ('24h', Icons.nights_stay_rounded, '22°', '20%'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Weather forecast',
          subtitle: 'Pune, Maharashtra · configured prototype location.',
        ),
        const SizedBox(height: 20),
        WeatherNow(data: data),
        const SizedBox(height: 18),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Next 24 hours',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: hours
                      .map(
                        (hour) => SizedBox(
                          width: 120,
                          child: Column(
                            children: [
                              Text(
                                hour.$1,
                                style: const TextStyle(
                                  color: Color(0xFF667870),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Icon(
                                hour.$2,
                                color: hour.$4 == '78%' || hour.$4 == '80%'
                                    ? const Color(0xFF4F79E7)
                                    : const Color(0xFFF6B81A),
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                hour.$3,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${hour.$4} rain',
                                style: const TextStyle(
                                  color: Color(0xFF667870),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const InfoBanner(
          icon: Icons.schedule_rounded,
          title: 'Rain delay active',
          text: 'The next irrigation check is scheduled after the high-probability rain window. Estimated saving: 1.3 L.',
        ),
      ],
    );
  }
}

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key, required this.data});
  final FarmSnapshot data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        title: 'Analytics',
        subtitle: 'Water use, moisture loss and estimated savings.',
      ),
      const SizedBox(height: 20),
      ResponsiveGrid(
        columns: MediaQuery.sizeOf(context).width > 900 ? 3 : 1,
        children: [
          const MetricCard(
            icon: Icons.water_drop_rounded,
            label: 'Water saved',
            value: '32%',
            note: 'vs. fixed schedule',
            color: Color(0xFF15966A),
          ),
          MetricCard(
            icon: Icons.opacity_rounded,
            label: 'Used today',
            value: '${data.deliveredToday} L',
            note:
                '${(data.dailyBudget - data.deliveredToday).toStringAsFixed(1)} L remaining',
            color: const Color(0xFF0EA5E9),
          ),
          const MetricCard(
            icon: Icons.currency_rupee_rounded,
            label: 'Estimated saving',
            value: '₹84',
            note: 'This month',
            color: Color(0xFFF59E0B),
          ),
        ],
      ),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 800;
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpandedIf(
                enabled: wide,
                child: ChartCard(
                  title: 'Moisture loss',
                  child: TrendChart(
                    seriesA: [68, 66, 59, 55, 47, 40, 35, 32],
                    seriesB: [61, 59, 56, 52, 48, 45, 43, 41],
                  ),
                ),
              ),
              SizedBox(width: wide ? 18 : 0, height: wide ? 0 : 18),
              ExpandedIf(
                enabled: wide,
                child: ChartCard(
                  title: 'Daily water use',
                  child: BarChart(values: [2.4, 4.8, 3.1, 5.5, 2.8, 4.1, 3.2]),
                ),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class CropsPage extends StatelessWidget {
  const CropsPage({super.key, required this.data});
  final FarmSnapshot data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        title: 'Crop profiles',
        subtitle: 'Targets used by the irrigation recommendation.',
      ),
      const SizedBox(height: 20),
      ResponsiveGrid(
        columns: MediaQuery.sizeOf(context).width >= 800 ? 2 : 1,
        children: data.zones
            .map(
              (zone) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(zone.colorValue)
                              .withValues(alpha: .12),
                          child: Icon(
                            Icons.eco_rounded,
                            color: Color(zone.colorValue),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              zone.crop,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              zone.name,
                              style: const TextStyle(color: Color(0xFF667870)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    DetailRow(
                      label: 'Target moisture',
                      value: '${zone.target}%',
                    ),
                    const DetailRow(label: 'Growth stage', value: 'Vegetative'),
                    const DetailRow(label: 'Soil type', value: 'Loam'),
                    DetailRow(
                      label: 'Current need',
                      value: '${zone.litresNeeded} L',
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    ],
  );
}

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const alerts = [
      (
        Icons.cloud_rounded,
        'Rain delay enabled',
        'Irrigation moved beyond the 8-hour rain window.',
        Color(0xFF4F79E7),
        'Now',
      ),
      (
        Icons.water_drop_rounded,
        'Zone 1 moisture is low',
        '32% measured; target is 45%.',
        Color(0xFFF59E0B),
        '10 min',
      ),
      (
        Icons.check_circle_rounded,
        'All sensors online',
        'Last reading received successfully.',
        Color(0xFF15966A),
        '18 min',
      ),
      (
        Icons.power_rounded,
        'Irrigation completed',
        '1.2 L delivered through the shared line.',
        Color(0xFF15966A),
        'Yesterday',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Alerts',
          subtitle: 'Conditions that need attention or explain a decision.',
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            children: alerts
                .map(
                  (alert) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    leading: CircleAvatar(
                      backgroundColor: alert.$4.withValues(alpha: .12),
                      child: Icon(alert.$1, color: alert.$4),
                    ),
                    title: Text(
                      alert.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(alert.$3),
                    trailing: Text(
                      alert.$5,
                      style: const TextStyle(color: Color(0xFF667870)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool telegram = true;
  bool rainDelay = true;
  bool lowTank = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        title: 'Settings',
        subtitle: 'Prototype preferences and future connection points.',
      ),
      const SizedBox(height: 20),
      AppCard(
        child: Column(
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.location_on_rounded),
              title: Text(
                'Farm location',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Pune, Maharashtra'),
              trailing: Icon(Icons.chevron_right_rounded),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: telegram,
              onChanged: (value) => setState(() => telegram = value),
              title: const Text(
                'Telegram alerts',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Notify important irrigation events'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: rainDelay,
              onChanged: (value) => setState(() => rainDelay = value),
              title: const Text(
                'Automatic rain delay',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Postpone watering when rain is likely'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: lowTank,
              onChanged: (value) => setState(() => lowTank = value),
              title: const Text(
                'Low-tank protection',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Prevent dry running'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const InfoBanner(
        icon: Icons.memory_rounded,
        title: 'ESP32 connection',
        text: 'Demo data is active. Replace DemoFarmService when the ESP32 endpoint is ready.',
      ),
    ],
  );
}

class WeeklyPlan extends StatelessWidget {
  const WeeklyPlan({super.key});

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Weekly irrigation plan',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 16),
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              PlanDay(day: 'Mon', litres: '0 L', rain: true),
              PlanDay(day: 'Tue', litres: '1.4 L'),
              PlanDay(day: 'Wed', litres: '1.0 L'),
              PlanDay(day: 'Thu', litres: '0 L', rain: true),
              PlanDay(day: 'Fri', litres: '1.6 L'),
              PlanDay(day: 'Sat', litres: '1.2 L'),
              PlanDay(day: 'Sun', litres: '0.8 L'),
            ],
          ),
        ),
      ],
    ),
  );
}

class PlanDay extends StatelessWidget {
  const PlanDay({
    super.key,
    required this.day,
    required this.litres,
    this.rain = false,
  });
  final String day;
  final String litres;
  final bool rain;

  @override
  Widget build(BuildContext context) => Container(
    width: 115,
    margin: const EdgeInsets.only(right: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: rain ? const Color(0xFFEAF2FF) : const Color(0xFFF4F8F6),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Text(day, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Icon(
          rain ? Icons.cloud_rounded : Icons.water_drop_rounded,
          color: rain ? const Color(0xFF4F79E7) : const Color(0xFF15966A),
        ),
        const SizedBox(height: 6),
        Text(litres),
      ],
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: MediaQuery.sizeOf(context).width < 500 ? 26 : 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -.7,
                color: const Color(0xFF12382D),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 15, color: Color(0xFF64756F)),
            ),
          ],
        ),
      ),
    ],
  );
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({super.key, required this.rainProbability});
  final int rainProbability;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF0E8060), Color(0xFF0B6652)],
      ),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.cloud_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SMART RECOMMENDATION',
                style: TextStyle(
                  color: Color(0xFFA7E7CF),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Delay irrigation',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$rainProbability% rain probability in 8 hours · save about 1.3 L',
                style: const TextStyle(color: Color(0xFFD8F1E7), height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class WeatherNow extends StatelessWidget {
  const WeatherNow({super.key, required this.data});
  final FarmSnapshot data;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        const Icon(Icons.wb_sunny_rounded, size: 52, color: Color(0xFFF6B81A)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${data.temperature.toStringAsFixed(0)}°C',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'Partly cloudy · Pune',
                style: TextStyle(color: Color(0xFF64756F)),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${data.humidity.toStringAsFixed(1)}% humidity',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${data.rainProbability}% rain',
              style: const TextStyle(
                color: Color(0xFF4F79E7),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class ZoneSummary extends StatelessWidget {
  const ZoneSummary({super.key, required this.zone});
  final ZoneData zone;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        MoistureRing(
          value: zone.moisture,
          color: Color(zone.colorValue),
          size: 82,
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${zone.name} · ${zone.crop}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              StatusPill(
                label: zone.live ? 'Live' : 'Demo only',
                color: zone.live
                    ? const Color(0xFF15966A)
                    : const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 7),
              Text(
                'Target ${zone.target}% · needs ${zone.litresNeeded} L',
                style: const TextStyle(color: Color(0xFF64756F)),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: zone.moisture / 100,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
                color: Color(zone.colorValue),
                backgroundColor: const Color(0xFFE8EFEB),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ZoneDetailCard extends StatelessWidget {
  const ZoneDetailCard({super.key, required this.zone});
  final ZoneData zone;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(zone.colorValue).withValues(alpha: .12),
              child: Icon(Icons.eco_rounded, color: Color(zone.colorValue)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${zone.name} · ${zone.crop}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            StatusPill(
              label: zone.live ? 'Live sensor' : 'Demo only',
              color: zone.live
                  ? const Color(0xFF15966A)
                  : const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            MoistureRing(
              value: zone.moisture,
              color: Color(zone.colorValue),
              size: 105,
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                children: [
                  DetailRow(label: 'Target moisture', value: '${zone.target}%'),
                  DetailRow(
                    label: 'Water needed',
                    value: '${zone.litresNeeded} L',
                  ),
                  const DetailRow(label: 'Soil', value: 'Loam'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Moisture trend',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: TrendChart(
            seriesA: [58, 56, 52, 48, 43, 38, 34, zone.moisture],
          ),
        ),
      ],
    ),
  );
}

class PumpCard extends StatelessWidget {
  const PumpCard({
    super.key,
    required this.data,
    required this.onPump,
    required this.busy,
    this.simple = false,
    this.modeControl = true,
  });
  final FarmSnapshot data;
  final VoidCallback onPump;
  final bool busy;
  final bool simple;
  final bool modeControl;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFE1F3EB),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.settings_input_component_rounded,
                color: Color(0xFF087A55),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shared pump',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Waters both zones',
                    style: TextStyle(color: Color(0xFF64756F)),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: data.pumpOn ? 'Running' : 'Off',
              color: data.pumpOn
                  ? const Color(0xFF15966A)
                  : const Color(0xFFEF4444),
            ),
          ],
        ),
        SizedBox(height: simple ? 20 : 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy || !data.pumpControlAvailable ? null : onPump,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    data.pumpOn ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
            label: Text(
              data.pumpControlAvailable
                  ? (data.pumpOn ? 'Stop irrigation' : 'Start irrigation')
                  : 'Add relay control to ESP code',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ),
        if (!simple) ...[
          const SizedBox(height: 18),
          DetailRow(label: 'Flow pulses', value: '${data.flowPulses} / 2.5s'),
          DetailRow(label: 'Tank level', value: '${data.tankLevel}%'),
          DetailRow(
            label: 'Used today',
            value: '${data.deliveredToday} / ${data.dailyBudget} L',
          ),
          if (modeControl)
            const DetailRow(label: 'Control mode', value: 'Automatic'),
        ],
      ],
    ),
  );
}

class SensorHealth extends StatelessWidget {
  const SensorHealth({super.key, required this.data});
  final FarmSnapshot data;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Sensor health',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
            StatusPill(
              label: data.connected ? 'MQTT live' : 'Demo mode',
              color: data.connected
                  ? const Color(0xFF15966A)
                  : const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final sensor in [
          'Zone 1 moisture',
          'DHT22',
          'Rain sensor',
          'Tank level',
          'Flow sensor',
        ])
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF15966A),
              size: 20,
            ),
            title: Text(sensor),
            trailing: const Text(
              'Healthy',
              style: TextStyle(
                color: Color(0xFF15966A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const Spacer(),
            const Icon(Icons.more_horiz_rounded, color: Color(0xFF9AABA4)),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF667870),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(
          note,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 16),
        SizedBox(height: 210, child: child),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFE7F3FF),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFCFE5FA)),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF3674C8), size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                text,
                style: const TextStyle(color: Color(0xFF4E6780), height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF667870))),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.columns,
    required this.children,
  });
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 16.0;
      final safeColumns = math.min(columns, children.length);
      final width = (box.maxWidth - gap * (safeColumns - 1)) / safeColumns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

class ExpandedIf extends StatelessWidget {
  const ExpandedIf({
    super.key,
    required this.enabled,
    required this.child,
    this.flex = 1,
  });
  final bool enabled;
  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) => enabled
      ? Expanded(flex: flex, child: child)
      : SizedBox(width: double.infinity, child: child);
}

class MoistureRing extends StatelessWidget {
  const MoistureRing({
    super.key,
    required this.value,
    required this.color,
    required this.size,
  });
  final int value;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.square(
          dimension: size,
          child: CircularProgressIndicator(
            value: value / 100,
            strokeWidth: 9,
            strokeCap: StrokeCap.round,
            color: color,
            backgroundColor: const Color(0xFFE7EEEA),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value%',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: size * .22,
              ),
            ),
            Text(
              'moisture',
              style: TextStyle(
                fontSize: size * .1,
                color: const Color(0xFF667870),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.seriesA, this.seriesB});
  final List<num> seriesA;
  final List<num>? seriesB;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TrendPainter(seriesA, seriesB),
    child: const SizedBox.expand(),
  );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.a, this.b);
  final List<num> a;
  final List<num>? b;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE6ECE9)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    drawLine(canvas, size, a, const Color(0xFF15966A));
    if (b != null) drawLine(canvas, size, b!, const Color(0xFF27A5DF));
  }

  void drawLine(Canvas canvas, Size size, List<num> values, Color color) {
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        i * size.width / (values.length - 1),
        size.height - values[i] / 80 * size.height,
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.a != a || oldDelegate.b != b;
}

class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.values});
  final List<num> values;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BarPainter(values), child: const SizedBox.expand());
}

class _BarPainter extends CustomPainter {
  const _BarPainter(this.values);
  final List<num> values;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.reduce(math.max).toDouble();
    final step = size.width / values.length;
    for (var i = 0; i < values.length; i++) {
      final height = values[i] / maxValue * (size.height - 20);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * step + step * .2,
          size.height - height,
          step * .58,
          height,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = i == values.length - 1
              ? const Color(0xFF087A55)
              : const Color(0xFF72CDA6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.values != values;
}
