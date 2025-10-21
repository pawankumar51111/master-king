import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:masterking/pages/games_page.dart';
import 'package:masterking/pages/home_page.dart';
import 'package:masterking/pages/users_page.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/app_state.dart';
import 'pages/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock the app to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, // Portrait only
    // DeviceOrientation.portraitDown, // Optional: Reverse portrait if needed
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await Supabase.initialize(
    url: 'https://fvivgnogfmiyyvadwjsw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ2aXZnbm9nZm1peXl2YWR3anN3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjQ3Njg0MjIsImV4cCI6MjA0MDM0NDQyMn0.ylWSZ2gIHeJkwemiTnh19p2cjB7zS4VjCRjQJy7pE-U',
  );

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MyApp(),
    ),
  );
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'MasterKing',
      debugShowCheckedModeBanner: false,

      home: LoginPage(),
    );
  }
}

extension ContextExtension on BuildContext {
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(this).colorScheme.error
            : Theme.of(this).snackBarTheme.backgroundColor,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int myIndex = 0;
  final List<Widget> widgetList = [
    const HomePage(),
    const GamesPage(),
    const UsersPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: myIndex == 0, // Allow pop only on HomePage
      onPopInvoked: (didPop) {
        if (!didPop) { // Only handle if pop was not handled by Navigator
          if (myIndex != 0) {
            setState(() {
              myIndex = 0;
            });
          }
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: myIndex,
          children: widgetList,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 14,
              unselectedFontSize: 12,
              showUnselectedLabels: true,
              elevation: 10,
              backgroundColor: Colors.white,
              currentIndex: myIndex,
              onTap: (index) {
                setState(() {
                  myIndex = index;
                });
              },
              selectedItemColor: myIndex == 0
                  ? Colors.blueAccent // Home
                  : myIndex == 1
                  ? Colors.orange // Games
                  : Colors.green, // Users
              unselectedItemColor: Colors.grey,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.sports_esports_outlined),
                  activeIcon: Icon(Icons.sports_esports),
                  label: 'Games',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_alt_outlined),
                  activeIcon: Icon(Icons.people_alt),
                  label: 'Users',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
