import 'package:flutter/material.dart';
import 'vision_simulator_screen.dart';
import 'sight_facts_screen.dart';

class AwarenessMenuScreen extends StatelessWidget {
  const AwarenessMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Awareness Menu', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.visibility, size: 80, color: Colors.tealAccent),
            const SizedBox(height: 32),
            
            // Button 1: Goes to the Vision Simulator
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const VisionSimulatorScreen()),
                );
              },
              icon: const Icon(Icons.remove_red_eye_outlined, size: 28),
              label: const Text('Vision Simulator', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.purple.shade100,
                foregroundColor: Colors.purple.shade900,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Button 2: Goes to the Sight Facts
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SightFactsScreen()),
                );
              },
              icon: const Icon(Icons.lightbulb_outline, size: 28),
              label: const Text('Sight Facts', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.blue.shade100,
                foregroundColor: Colors.blue.shade900,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}