import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:masterking/pages/subscription_page.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/app_state.dart';
import 'info_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isLoading = true;

  // bool isPremium = false;
  // bool isSuper = false;
  bool isGranted = false;


  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final session = supabase.auth.currentSession;
    if (session != null) {
      // Retrieve user ID from the Supabase session
      final userId = session.user.id;

      await Purchases.configure(PurchasesConfiguration("goog_ylBgrfIwNuFwbVUfGsKJybHsALg")..appUserID = userId);// Replace with your RevenueCat public SDK key
      // Initialize RevenueCat using the retrieved user ID
      // await Purchases.logIn(userEmail);
      // User is already logged in, initialize AppState
      await initPlatformState(); // Initialize RevenueCat after AppState
      await AppState().initialize();
      isGranted = AppState().granted == 'super' || AppState().granted == 'premium';

      setState(() {
        isLoading = false;
      });

      if (AppState().updateType.isNotEmpty){
        _navigateToPage(InfoPage(currentVersion: AppState().currentVersion, minVersion: AppState().minVersion, maxVersion: AppState().maxVersion, updateType: AppState().updateType));
        return;
      }

      // Check for app access
      if (AppState().appAccess == false) {
        return; // Terminate further navigation
      }

      // if (AppState().rcPremium || AppState().rcSuper || isGranted) {
      //   _navigateToPage(const MyHomePage(title: 'Home Page'));
      // }

      _navigateToPage(const MyHomePage(title: 'Home Page'));

    } else {
      // User not logged in, stop the loading state
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> initPlatformState() async {
    try {

      final customerInfo = await Purchases.getCustomerInfo();
      AppState().rcPremium = customerInfo.entitlements.all["premium"]?.isActive == true;
      AppState().rcSuper = customerInfo.entitlements.all["super"]?.isActive == true;

      // Check and update AppState().subscription if necessary
      if (AppState().rcPremium) {
        if (AppState().subscription != 'premium') {
          AppState().subscription = 'premium'; // Overwrite the subscription
        }
      } else if (AppState().rcSuper) {
        if (AppState().subscription != 'super') {
          AppState().subscription = 'super'; // Overwrite the subscription
        }
      }

    } catch (e) {
      // print("Error checking entitlements: $e");
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6A11CB), Color(0xFF2575FC)], // Purple-to-blue gradient
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Logo with subtle animation
                AnimatedScale(
                  scale: 1.0,
                  duration: const Duration(milliseconds: 700),
                  child: Image.asset(
                    'assets/launcher_icon.png',
                    height: 180,
                    width: 180,
                  ),
                ),

                const SizedBox(height: 24),

                // Title with improved styling
                const Text(
                  'Welcome to MasterKing',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle with subtle transparency
                const Text(
                  'Your Game, Your Control',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500, // Added to make it stand out more
                    color: Colors.white70,
                    height: 1.5, // Adding some line height for better readability
                  ),
                ),

                const SizedBox(height: 40),

                // Card for Sign-In Button
                Card(
                  color: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24),
                    child: isLoading
                        ? const CircularProgressIndicator()
                        : SizedBox(
                      width: 240, // Limit the button width
                      child: ElevatedButton(
                        onPressed: _onSignInOrOut,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Image.asset('assets/google_logo.png', height: 36),
                            const SizedBox(width: 12),
                            Text(
                              supabase.auth.currentUser == null ? 'Sign in with Google' : 'Sign Out',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Email Display
                if (supabase.auth.currentUser != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      '${supabase.auth.currentUser!.email}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Conditional Subscription Prompt
                // if (supabase.auth.currentUser != null &&
                //     !(AppState().rcPremium || AppState().rcSuper || isGranted) && !isLoading && AppState().appAccess != false)
                //   Padding(
                //     padding: const EdgeInsets.only(top: 16.0),
                //     child: Column(
                //       children: [
                //         const Text(
                //           "Upgrade to unlock features!",
                //           style: TextStyle(color: Colors.white, fontSize: 16),
                //         ),
                //         const SizedBox(height: 8),
                //         ElevatedButton(
                //           onPressed: () => _navigateToPage(const SubscriptionPage()),
                //           style: ElevatedButton.styleFrom(
                //             backgroundColor: Colors.blue,
                //             foregroundColor: Colors.white,
                //           ),
                //           child: const Text("Get Subscription"),
                //         ),
                //       ],
                //     ),
                //   ),

              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Handle Sign In / Sign Out
  Future<void> _onSignInOrOut() async {
    if (supabase.auth.currentUser == null) {
      // User is not signed in, sign them in
      await _signInWithGoogle();
    } else {
      _showSignOutDialog();
    }
  }

  Future<void> _showSignOutDialog() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut == true) {
      _signOut();
    }
  }

  Future<void> _signOut() async {
    try {

      setState(() {
        isLoading = true;
      });

      await supabase.auth.signOut();
      await Supabase.instance.client.dispose();

      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        // await googleSignIn.signOut();
        await googleSignIn.disconnect();
      }

      await AppState().resetState();
      // User is signed in, sign them out
      // await Purchases.logOut();
      // Sign out from Google

      setState(() {
        isLoading = false;
      }); // Update UI
      // Close the app after successful sign out
      // SystemNavigator.pop();
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
      exit(0); // Forcefully terminate the app


    } on AuthException catch (error) {
      context.showSnackBar(error.message, isError: true);
    } catch (error) {
      context.showSnackBar('Unexpected error occurred', isError: true);
    }
  }


  Future<void> _signInWithGoogle() async {
    setState(() {
      isLoading = true;
    });

    try {
      //  Replace with your actual client IDs
      const webClientId = '419450533501-nofkhbkmlbjls80spfihcf28vot1hlsi.apps.googleusercontent.com';
      const iosClientId = '419450533501-iari4b2goejvqsa2tnvh1qejb9gjf4f9.apps.googleusercontent.com';

      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: iosClientId,
        serverClientId: webClientId,
      );

      // Check if a user is already signed in and disconnect if needed
      if (await googleSignIn.isSignedIn()) {
        // await googleSignIn.signOut();
        await googleSignIn.disconnect();
      }

      // Trigger Google Sign-In
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          isLoading = false;
        });
        return; // User canceled sign-in
      }

      // Retrieve authentication tokens
      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        throw 'Authentication failed: Missing access or ID token.';
      }

      // Sign in with Supabase
      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // Validate session
      if (response.session == null || response.user == null) {
        throw Exception('Authentication failed: No session created.');
      }

      // Check if the user is authenticated
      if (response.session != null && response.user != null) {
        final String userId = response.user!.id;

        await Purchases.configure(PurchasesConfiguration("goog_ylBgrfIwNuFwbVUfGsKJybHsALg")..appUserID = userId);// Replace with your RevenueCat public SDK key

        await initPlatformState(); // Initialize RevenueCat after AppState
        await AppState().initialize();
        isGranted = AppState().granted == 'super' || AppState().granted == 'premium';

        if (AppState().updateType.isNotEmpty){
          _navigateToPage(InfoPage(currentVersion: AppState().currentVersion, minVersion: AppState().minVersion, maxVersion: AppState().maxVersion, updateType: AppState().updateType));
          return;
        }
        // Check for app access
        if (AppState().appAccess == false) {
          return; // Terminate further navigation
        }

        // if (AppState().rcPremium || AppState().rcSuper || isGranted) {
        //   _navigateToPage(const MyHomePage(title: 'Home Page'));
        // }

        _navigateToPage(const MyHomePage(title: 'Home Page'));

      } else {
        throw 'Authentication failed: No session created.';
      }
    } catch (error) {
      String errorMessage = 'Close the app completely, restart it, and try again.';

      if (error.toString().contains('Network')) {
        errorMessage = 'It seems there’s a network issue. Please check your connection and try again.';
      } else if (error.toString().contains('Authentication failed')) {
        errorMessage = 'Authentication failed. Close the app, restart it, and try again.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _navigateToPage(Widget page) {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => page));
  }

}
