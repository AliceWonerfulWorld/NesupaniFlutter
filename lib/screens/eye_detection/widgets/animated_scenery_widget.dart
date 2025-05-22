import 'package:flutter/material.dart';

class AnimatedSceneryWidget extends StatelessWidget {
  final double offset;
  final bool isEyesOpen;

  const AnimatedSceneryWidget({
    super.key,
    required this.offset,
    required this.isEyesOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          // 空
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFB3E5FC), Color(0xFFE1F5FE)],
              ),
            ),
          ),
          // 遠景ビル群
          _buildBuildings(layer: 2, speed: 80, colors: [Colors.blueGrey, Colors.grey, Colors.blueGrey.shade200]),
          // 中景ビル群
          _buildBuildings(layer: 1, speed: 160, colors: [Colors.indigo, Colors.blue, Colors.indigo.shade200]),
          // 近景ビル群
          _buildBuildings(layer: 0, speed: 320, colors: [Colors.blueGrey.shade700, Colors.blueGrey.shade900, Colors.indigo.shade700]),
          // 道路
          _buildRoad(),
          // 車
          _buildCar(left: 60 + (offset * 400) % 300, color: Colors.red),
          _buildCar(left: 200 + (offset * 350) % 300, color: Colors.blue),
          // 街路樹
          _buildTree(left: 120 + (offset * 200) % 300),
          _buildTree(left: 260 + (offset * 180) % 300),
          // 信号
          _buildTrafficLight(left: 180 + (offset * 250) % 300),
          // 雲
          _buildCloud(top: 20, left: 40 + (offset * 120) % 200),
          _buildCloud(top: 50, left: 180 + (offset * 100) % 200),
        ],
      ),
    );
  }

  Widget _buildBuildings({required int layer, required double speed, required List<Color> colors}) {
    return Positioned(
      bottom: 40 + layer * 30,
      left: -200 + (offset * speed),
      child: Row(
        children: List.generate(8, (i) {
          final height = 60.0 + (i % 3) * 30.0 + layer * 20;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 28 + (i % 2) * 8.0,
            height: height,
            decoration: BoxDecoration(
              color: colors[i % colors.length],
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(2, 2),
                ),
              ],
            ),
            child: Stack(
              children: List.generate(
                (height ~/ 18),
                (j) => Positioned(
                  left: 4,
                  top: 6.0 + j * 16,
                  child: Container(
                    width: 20,
                    height: 8,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRoad() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 36,
      child: Container(
        color: Colors.grey[800],
        child: Row(
          children: List.generate(6, (i) =>
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
                height: 4,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCar({required double left, required Color color}) {
    return Positioned(
      left: left,
      bottom: 8,
      child: Icon(Icons.directions_car, color: color, size: 28),
    );
  }

  Widget _buildTree({required double left}) {
    return Positioned(
      left: left,
      bottom: 36,
      child: Column(
        children: [
          Container(
            width: 8,
            height: 24,
            color: Colors.brown[700],
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.green[700],
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficLight({required double left}) {
    return Positioned(
      left: left,
      bottom: 60,
      child: Container(
        width: 16,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[700],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
            const SizedBox(height: 2),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.yellow, shape: BoxShape.circle)),
            const SizedBox(height: 2),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  Widget _buildCloud({required double top, required double left}) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: 60,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
} 