import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/localization/app_localizations.dart';
import '../core/services/language_provider.dart';

class SightFactsScreen extends StatelessWidget {
  const SightFactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(LanguageNotifier().languageCode);
    final List<Map<String, String>> facts = [
      {
        "title": strings.get('fact1Title'),
        "content": strings.get('fact1Content'),
        "icon": "\ud83d\udd75\ufe0f",
      },
      {
        "title": strings.get('fact2Title'),
        "content": strings.get('fact2Content'),
        "icon": "\ud83d\ude87",
      },
      {
        "title": strings.get('fact3Title'),
        "content": strings.get('fact3Content'),
        "icon": "\ud83c\udfe5",
      },
      {
        "title": strings.get('fact4Title'),
        "content": strings.get('fact4Content'),
        "icon": "\ud83c\udfa8",
      },
    ];

    return Scaffold(
      appBar: AppBar(title: Text(strings.get('sightFacts'))),
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
                      child: Semantics(
                        button: true,
                        label: strings.get('nationalSupport'),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            const url = "https://ncbm.org.my/";
                            final uri = Uri.parse(url);

                            try {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (e) {
                              debugPrint("Could not launch url: $e");
                              try {
                                await launchUrl(uri);
                              } catch (e2) {
                                debugPrint("Fallback failed: $e2");
                              }
                            }
                          },
                          icon: const Icon(Icons.public, color: Colors.white),
                          label: Text(
                            strings.get('nationalSupport'),
                            style: const TextStyle(
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
