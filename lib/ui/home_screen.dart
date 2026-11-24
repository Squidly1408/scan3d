import 'package:flutter/material.dart';

import 'scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Image.asset('assets/brand/mark.png', width: 80, height: 80),
              const SizedBox(height: 16),
              Text('Scan3D', style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                'Walk around with your camera to build a 3D map of the space.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              const _Tip(Icons.directions_walk, 'Move slowly and keep the phone steady.'),
              const _Tip(Icons.light_mode_outlined, 'Good lighting and textured surfaces work best.'),
              const _Tip(Icons.threesixty, 'Sweep walls, floor and furniture from a few angles.'),
              const _Tip(Icons.sensors, 'LiDAR iPhones/iPads give the densest maps.'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(18)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Start scanning'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
}
