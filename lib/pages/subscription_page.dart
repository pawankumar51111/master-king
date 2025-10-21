import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:masterking/pages/login_page.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool isLoading = true;
  Offering? offering; // To hold the available offerings

  @override
  void initState() {
    super.initState();
    _fetchOfferings(); // Fetch offerings when the page initializes
  }

  /// Fetch available offerings from RevenueCat
  Future<void> _fetchOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      setState(() {
        offering = offerings.current;
        isLoading = false;
      });
    } catch (e) {
      // print("Error fetching offerings: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Subscription"),
        elevation: 0.0, // Remove default shadow
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
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2575FC)),
        ),
      )
          : offering == null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("No subscriptions available. Please try again."),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchOfferings,
              child: const Text("Retry"),
            ),
          ],
        ),
      )
          : SafeArea(
        child: Center(
          child: PaywallView(
            offering: offering,
            onRestoreCompleted: (CustomerInfo customerInfo) {
              final restoredEntitlements = customerInfo.entitlements.active.keys.toList();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    restoredEntitlements.isNotEmpty
                        ? "Restored: ${restoredEntitlements.join(", ")}"
                        : "No subscription restored.",
                  ),
                ),
              );
              if (restoredEntitlements.isNotEmpty) {
                // Delay navigation to allow snackbar to show
                Future.delayed(const Duration(seconds: 1), () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                });
              }
            },
            onDismiss: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
            },
          ),
        ),
      ),
    );
  }


}
