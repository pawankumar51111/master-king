import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:masterking/models/app_state.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // For launching URLs

import '../main.dart';
import 'login_page.dart';

class InfoPage extends StatefulWidget {
  final String updateType;
  final int currentVersion;
  final int minVersion;
  final int maxVersion;

  const InfoPage({super.key, required this.currentVersion, required this.minVersion, required this.maxVersion, required this.updateType});

  @override
  _InfoPageState createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  bool loading = false;
  String forceNote = '';
  String appUrl = '';
  bool isForceUpdate = false;

  final String defaultAppUrl = 'https://play.google.com/store/apps/details?id=com.kdsolution.masterking&hl=en';

  @override
  void initState() {
    super.initState();
    _fetchUpdate();
  }

  Future<void> _fetchUpdate() async {
    setState(() {
      loading = true;
    });

    if (widget.updateType != 'force_update') {
      try {
        // Fetch the configuration for the app version from Supabase
        final response = await supabase
            .from('khaiwal_app_config')
            .select('app_url')
            .eq('id', 1) // Adjust this for iOS if needed
            .maybeSingle();

        if (response != null) {
          appUrl = response['app_url'] ?? '';
        }
      } catch (error) {
        if (kDebugMode) {
          print("Error checking app version: $error");
        }
      }
      setState(() {
        loading = false;
      });
      return;
    }

    isForceUpdate = true;

    await _checkAppVersion();

    setState(() {
      loading = false;
    });
  }

  Future<void> _checkAppVersion() async {
    try {
      // Fetch the configuration for the app version from Supabase
      final response = await supabase
          .from('khaiwal_app_config')
          .select('max_force_note, app_url')
          .eq('id', 1) // Adjust this for iOS if needed
          .maybeSingle();

      if (response != null) {
        forceNote = response['max_force_note'] ?? '';
        appUrl = response['app_url'] ?? '';
      }
    } catch (error) {
      if (kDebugMode) {
        print("Error checking app version: $error");
      }
    }
  }

  Future<void> _launchAppUrl() async {
    final url = (appUrl.isNotEmpty && Uri.tryParse(appUrl)?.isAbsolute == true)
        ? appUrl
        : defaultAppUrl;

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      // Show an error if the URL cannot be opened
      debugPrint("Could not launch $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Information'),
            elevation: 0.0,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2575FC), Color(0xFF6A11CB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (isForceUpdate)
                    _buildForceUpdateUI()
                  else if (widget.currentVersion < widget.minVersion)
                    _buildMinVersionUpdateUI()
                  else
                    _buildNoUpdateUI(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildForceUpdateUI() {
    return Center(
      child: Card(
        elevation: 4.0,
        margin: const EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
              const SizedBox(height: 20),
              Text(
                forceNote.isEmpty ? 'A new update is required!' : forceNote,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _launchAppUrl,
                icon: const Icon(Icons.update, color: Colors.white),
                label: const Text('Update Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinVersionUpdateUI() {
    return Center(
      child: Card(
        elevation: 4.0,
        margin: const EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.system_update_alt, color: Colors.blue, size: 50),
              const SizedBox(height: 20),
              const Text(
                'Your app version is outdated. Please update to the latest version.',
                style: TextStyle(fontSize: 18, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _launchAppUrl,
                icon: const Icon(Icons.download, color: Colors.white),
                label: const Text('Update Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoUpdateUI() {
    return Center(
      child: Card(
        elevation: 4.0,
        margin: const EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 50),
              const SizedBox(height: 20),
              const Text(
                'You are using the latest version.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                },
                child: const Text('Done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
