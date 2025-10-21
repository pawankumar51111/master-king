import 'package:flutter/material.dart';
import 'package:masterking/models/app_state.dart';
import 'package:masterking/pages/user_page.dart';
import 'package:provider/provider.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  _UsersPageState createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  // Option menu items
  late List<Map<String, dynamic>> _menuOptions = [
    {'label': 'Pending', 'checked': false},
    {'label': 'Blocked', 'checked': false},
  ];


  bool loading = false;
  int menuCount = 2;

  // For managing search bar focus state
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();

    // Accessing context safely after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final menuCount = context.read<AppState>().menuOption;

      setState(() {
        _menuOptions = _initializeMenuOptions(menuCount);
      });
    });

    // Listener to track focus state changes
    _searchFocusNode.addListener(() {
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });
  }

// Initialize _menuOptions based on menuCount
  List<Map<String, dynamic>> _initializeMenuOptions(int menuCount) {
    bool pendingChecked = false;
    bool blockedChecked = false;

    switch (menuCount) {
      case 1:
        pendingChecked = false;
        blockedChecked = false;
        break;
      case 2:
        pendingChecked = true;
        blockedChecked = false;
        break;
      case 3:
        pendingChecked = true;
        blockedChecked = true;
        break;
      case 4:
        pendingChecked = false;
        blockedChecked = true;
        break;
    }

    return [
      {'label': 'Pending', 'checked': pendingChecked},
      {'label': 'Blocked', 'checked': blockedChecked},
    ];
  }


  // Fetch users based on the type ('active', 'pending', 'blocked')
  Future<void> _fetchUsers() async {
    setState(() {
      loading = true;
      // currentView = type; // Set the current view
    });

    await AppState().fetchMenuUsers();

    setState(() {
      loading = false;
    });
  }

  // Handle menu item selection
  void _onMenuOptionSelected(String option, bool isChecked) {

    final currentMenu = AppState().menuOption;

    if (currentMenu == 0){
      return;
    }

    if (option == 'Pending') {
      AppState().menuOption = isChecked
          ? (currentMenu == 4 ? 3 : 2)
          : (currentMenu == 4 ? 3 : currentMenu == 3 ? 4 : currentMenu == 2 ? 1 : 2);
    } else if (option == 'Blocked') {
      AppState().menuOption = isChecked
          ? (currentMenu == 1 ? 4 : 3)
          : (currentMenu == 3 ? 2 : 1);
    }

    Navigator.pop(context);

    if (AppState().menuOption != currentMenu) {
      _fetchUsers();
      AppState().updateMenuOptions();
    }
    // if (option == 'Pending Users') {
    //   if (isChecked) {
    //     if (AppState().menuOption == 4) {
    //       AppState().menuOption = 3;
    //       _fetchUsers();
    //     } else {
    //       AppState().menuOption = 2;
    //       _fetchUsers();
    //     }
    //   } else {
    //     if (AppState().menuOption == 4) {
    //       AppState().menuOption = 3;
    //       _fetchUsers();
    //     } else if (AppState().menuOption == 3) {
    //       AppState().menuOption = 4;
    //       _fetchUsers();
    //     } else if (AppState().menuOption == 2) {
    //       AppState().menuOption = 1;
    //       _fetchUsers();
    //     } else if (AppState().menuOption == 1) {
    //       AppState().menuOption = 2;
    //       _fetchUsers();
    //     }
    //     // Handle unchecking Pending Users if necessary
    //   }
    // } else if (option == 'Blocked Users') {
    //   if (isChecked) {
    //     if (AppState().menuOption == 1) {
    //       AppState().menuOption = 4;
    //       _fetchUsers();
    //     } else {
    //       AppState().menuOption = 3;
    //       _fetchUsers();
    //     }
    //
    //   } else {
    //     if (AppState().menuOption == 3) {
    //       AppState().menuOption = 2;
    //       _fetchUsers();
    //     } else if (AppState().menuOption == 4) {
    //       AppState().menuOption = 1;
    //       _fetchUsers();
    //     }
    //     // Handle unchecking Blocked Users if necessary
    //   }
    // }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0, // Remove default shadow
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.lightGreen.shade400, Colors.green.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text('Users'), // Simplify AppBar without search
        actions: [
          PopupMenuButton<String>(
            onSelected: (String option) {
              // Handle menu option selection without changing state here
            },
            itemBuilder: (BuildContext context) {
              return _menuOptions.map((option) {
                return PopupMenuItem<String>(
                  value: option['label'],
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      return CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(option['label']),
                        value: option['checked'],
                        onChanged: (bool? value) {
                          setState(() {
                            option['checked'] = value!;
                          });
                          _onMenuOptionSelected(option['label'], option['checked']);
                        },
                      );
                    },
                  ),
                );
              }).toList();
            },
            icon: const Icon(Icons.more_vert, color: Colors.white),
          )

        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          final usersList = appState.users;

          return GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus(); // Close keyboard when tapping outside
            },
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _fetchUsers, // Refresh current view
              child: Column(
                children: [
                  // Search bar at the top
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: MediaQuery.of(context).size.width * 0.9,
                      child: TextField(
                        focusNode: _searchFocusNode,
                        onChanged: (value) {
                          _filterUsers(value);
                        },
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 0, horizontal: 16),
                          hintText: 'Search users...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25.0),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: Icon(
                            Icons.search,
                            color: _isSearchFocused ? Colors.green : Colors.grey,
                          ),
                          hintStyle: TextStyle(
                            color: _isSearchFocused ? Colors.green : Colors.grey,
                          ),
                        ),
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                  // User list or 'No users found' message
                  Expanded(
                    child: usersList.isEmpty
                        ? ListView(
                      children: const [
                        Text(
                          textAlign: TextAlign.center,
                          'No users found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ]
                    ) : ListView.builder(
                      itemCount: usersList.length,
                      itemBuilder: (context, index) {
                        final user = usersList[index];
                        final walletBalance = user['balance'] ?? 0;
                        final nullActionCount = user['null_action_count'] ?? 0;
                        final bool? isActive = user['allowed']; // Nullable bool for 'allowed'
                        final avatarUrl = user['avatar_url'];

                        final fullName = user['full_name'] != null && user['full_name'].isNotEmpty
                            ? user['full_name']
                            : 'Unknown';

                        // Extract the first valid letter, fallback to null if none found
                        final firstLetter = getFirstValidLetter(fullName);
                        final avatarColor = fullName == 'Unknown'
                            ? Colors.grey
                            : (firstLetter != null ? getColorForLetter(firstLetter) : Colors.blueGrey);

                        final Color? bgColor;
                        final String status;
                        final ColorSwatch<int>? textColor;

                        if (isActive == null) {
                          status = 'Pending';
                          textColor = Colors.orange;
                          bgColor = Colors.orange.shade50;
                        } else if (isActive == false) {
                          status = 'Blocked';
                          textColor = Colors.redAccent;
                          bgColor = Colors.red.shade50;
                        } else {
                          status = '';
                          textColor = null;
                          bgColor = null;
                        }


                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),

                          color: bgColor, // Default background if active

                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 25,
                              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              backgroundColor: avatarUrl == null || avatarUrl.isEmpty
                                  ? avatarColor // Background color for text icon
                                  : Colors.transparent,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? (firstLetter != null
                                  ? Text(
                                firstLetter,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.white,
                                ),
                              )
                                  : const Icon(
                                Icons.person,
                                size: 30,
                                color: Colors.white,
                              )) : null,
                            ),
                            title: Text(fullName),
                            subtitle: RichText(
                              text: TextSpan(
                                children: [
                                  const TextSpan(
                                    text: 'Balance: ',
                                    style: TextStyle(
                                        color: Colors.blueGrey), // Default color for "Balance:"
                                  ),
                                  TextSpan(
                                    text: walletBalance.toString(),
                                    style: TextStyle(
                                      color: walletBalance < 0
                                          ? Colors.red
                                          : walletBalance > 0
                                          ? Colors.green
                                          : Colors.black,
                                    ), // Color for both and walletBalance
                                  ),
                                ],
                              ),
                            ),
                            trailing: (nullActionCount > 0 || isActive == null || isActive == false)
                                ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Display status text if isActive is null or false
                                if (isActive == null || isActive == false)
                                  Text(
                                    status,
                                    style: TextStyle(color: textColor),
                                  ),

                                // Display pending actions icon and count if applicable
                                if (nullActionCount > 0) ...[
                                  const Icon(
                                    Icons.pending_actions,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    nullActionCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ) : null,

                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserPage(
                                    userData: user,
                                    // currentView: user['allowed'] == true ? 'Active' : user['allowed'] == false ? 'Blocked' : 'Pending', // Pass currentView here
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Search and filter users based on current view
  void _filterUsers(String query) {
    final searchQuery = query.toLowerCase();
    List<Map<String, dynamic>> filteredUsers = [];

    filteredUsers = AppState().originalUsers.where((user) {
      final fullName = user['full_name'].toLowerCase();
      return fullName.contains(searchQuery);
    }).toList();
    setState(() {
      AppState().users = filteredUsers;
    });

  }

  // Function to get background color based on the first letter
  Color getColorForLetter(String letter) {
    if (letter.isEmpty) return Colors.grey; // Default color if letter is empty

    switch (letter.toUpperCase()) {
      case 'A':
      case 'B':
      case 'C':
        return Colors.blue.shade400;
      case 'D':
      case 'E':
      case 'F':
        return Colors.orange.shade400;
      case 'G':
      case 'H':
      case 'I':
        return Colors.green.shade400;
      case 'J':
      case 'K':
      case 'L':
        return Colors.brown.shade300;
      case 'M':
      case 'N':
      case 'O':
        return Colors.teal.shade300;
      case 'P':
      case 'Q':
      case 'R':
        return Colors.red.shade400;
      case 'S':
      case 'T':
      case 'U':
        return Colors.yellow.shade700;
      case 'V':
      case 'W':
      case 'X':
        return Colors.purple.shade300;
      case 'Y':
      case 'Z':
        return Colors.pink.shade300; // 'Rose' color
      default:
        return Colors.blueGrey; // Default color for unexpected input
    }
  }

  // Helper function to get the first valid letter
  String? getFirstValidLetter(String? input) {
    if (input == null || input.isEmpty) return null;

    for (int i = 0; i < input.length; i++) {
      if (RegExp(r'[A-Za-z]').hasMatch(input[i])) {
        return input[i].toUpperCase();
      }
    }
    return null; // Return null if no valid letter is found
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }
}
