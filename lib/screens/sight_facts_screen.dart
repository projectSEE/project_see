import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; 

class SightFactsScreen extends StatelessWidget {
  const SightFactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> facts = [
      {
        "title": "The Silent Thief",
        "content":
            "Glaucoma is often called the 'silent thief of sight' because it gradually steals vision without any early symptoms or pain.",
        "icon": "🕵️",
      },
      {
        "title": "Tunnel Vision",
        "content":
            "Advanced Glaucoma typically results in 'tunnel vision', where you lose your side (peripheral) vision first.",
        "icon": "🚇",
      },
      {
        "title": "Regular Checks",
        "content":
            "Vision lost to Glaucoma cannot be recovered. Regular eye exams are the only way to catch it early and stop it.",
        "icon": "🏥",
      },
      {
        "title": "Inclusive Design",
        "content":
            "High contrast buttons (like in this app!) help people with low vision distinguish elements easier.",
        "icon": "🎨",
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Sight Facts")),
      body: PageView.builder(
        itemCount: facts.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      facts[index]["icon"]!,
                      style: const TextStyle(fontSize: 80),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      facts[index]["title"]!,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      facts[index]["content"]!,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.5,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(),

                    // --- UPDATED BUTTON (Force Launch Logic) ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          const url = "https://ncbm.org.my/";
                          final uri = Uri.parse(url);
                          
                          // We use try-catch instead of 'canLaunchUrl' to force the intent
                          // This fixes the "no response" issue on Android 11+
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            debugPrint("Could not launch url: $e");
                            // Fallback: Try launching without specific mode if the above fails
                            try {
                              await launchUrl(uri);
                            } catch (e2) {
                              debugPrint("Fallback failed: $e2");
                            }
                          }
                        },
                        icon: const Icon(Icons.public, color: Colors.white),
                        label: const Text(
                          "National Support (NCBM)",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade800, 
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    // -----------------------------
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "${index + 1} of ${facts.length}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                        if (index < facts.length - 1) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: Colors.grey,
                          ),
                        ],
                      ],
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
}