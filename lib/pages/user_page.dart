import 'package:flutter/material.dart';
import 'package:masterking/main.dart'; // Assuming this is where supabase is initialized
import 'package:masterking/models/app_state.dart';
import 'package:masterking/pages/game_history_page.dart';
import 'package:masterking/pages/kplogs_page.dart';
import 'package:masterking/pages/transaction_page.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:provider/provider.dart';

class UserPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const UserPage({super.key, required this.userData});

  @override
  _UserPageState createState() => _UserPageState();
}


class _UserPageState extends State<UserPage> {
  bool loading = true;
  Map<String, dynamic> userData = {};
  // Map<String, dynamic> userSettings = {};

  @override
  void initState() {
    super.initState();
    userData = widget.userData;
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    setState(() {
      loading = true;
    });

    await AppState().fetchUserSettings(userData['kp_id']);

    setState(() {
      loading = false;
    });

    if (userData['balance'] != AppState().userSettings['balance'] || userData['null_action_count'] != AppState().userSettings['null_action_count']) {

      // Deduct action count based on currentView
      if (AppState().userSettings['allowed'] == true) {
        final user = AppState().users.firstWhere(
              (user) => user['kp_id'] == userData['kp_id'],
          orElse: () => {},
        );
        if (user.isNotEmpty) {
          user['null_action_count'] = (AppState().userSettings['null_action_count']);
        }
      }
      // else if (AppState().userSettings['allowed'] == null) {
      //   final user = AppState().pendingUsers.firstWhere(
      //         (user) => user['kp_id'] == userData['kp_id'],
      //     orElse: () => {},
      //   );
      //   if (user.isNotEmpty) {
      //     user['null_action_count'] = (AppState().userSettings['null_action_count']);
      //   }
      // } else if (AppState().userSettings['allowed'] == false) {
      //   final user = AppState().blockedUsers.firstWhere(
      //         (user) => user['kp_id'] == userData['kp_id'],
      //     orElse: () => {},
      //   );
      //   if (user.isNotEmpty) {
      //     user['null_action_count'] = (AppState().userSettings['null_action_count']);
      //   }
      // }
      // Call a method from AppState to update the user's wallet
      AppState().updateSelectedUserWallet(userData['kp_id'], AppState().userSettings['balance']);
    }
  }


  Future<void> _updateUserSetting(String field, dynamic value) async {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to update.')),
      );
      return; // Terminate initialization if conditions are not met
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog by tapping outside
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(), // Show a circular progress indicator
        );
      },
    );

    if (field == 'allowed' && value == true && AppState().subscription == 'super' && AppState().users.length > AppState().superUsers && AppState().isResetting != true) {
      // Count active games
      final activeUsersCount = AppState().users.where((user) => user['allowed'] == true).length;

      // print('Printing active users: $activeUsersCount');

      if (activeUsersCount >= AppState().superUsers) {
        final now = AppState().currentTime;

        if (AppState().sgUpdatedAt != null) {
          final diff = now.difference(AppState().sgUpdatedAt!);
          // Show dialog only if more than 48 hours have passed
          if (diff.inHours >= 48) {
            bool shouldContinue = await _showGameLimitExceededConfirmationDialog();
            if (!shouldContinue) {
              Navigator.of(context).pop(); // Dismiss loading dialog
              return;
            }

            // Check for device mismatch
            final isMismatch = await AppState().checkDeviceMismatch(context);
            if (isMismatch) return; // Halt if there's a mismatch
          }
          if (diff.inHours > 1 && diff.inHours < 48) {
            _showDialog(
              'Cooling Period Not Over',
              'You cannot update Activeness of this user yet. The cooling period of 2 days since the last update is not over.',
            );
            Navigator.of(context).pop(); // Dismiss loading dialog
            setState(() {
              loading = false;
            });

            return;
          }

          if (diff.inHours > 48) {
            // Update sg_updated_at with the current time
            await supabase
                .from('khaiwals')
                .update({'sg_updated_at': now.toIso8601String()})
                .eq('id', AppState().khaiwalId);

            AppState().sgUpdatedAt = now;

            final response = await supabase
                .from('khaiwals_players')
                .update({field: value})
                .eq('id', userData['kp_id']);

            if (response == null) {
              AppState().userSettings[field] = value;

              if (field == 'allowed') {
                // Update the appropriate user list based on 'allowed'
                final user = AppState().users.firstWhere(
                      (user) => user['kp_id'] == userData['kp_id'],
                  orElse: () => {},
                );
                if (user.isNotEmpty) {
                  user[field] = value;
                }
              }
              AppState().isResetting = true;
            }
            Navigator.of(context).pop(); // Dismiss loading dialog
            return;
          }

        } else if (AppState().sgUpdatedAt == null) {
          bool shouldContinue = await _showGameLimitExceededConfirmationDialog();
          if (!shouldContinue) {
            Navigator.of(context).pop(); // Dismiss loading dialog
            return;
          }

          // Check for device mismatch
          final isMismatch = await AppState().checkDeviceMismatch(context);
          if (isMismatch) return; // Halt if there's a mismatch

          // print('printing when sgUpdatedAt is null');

          // Update sg_updated_at with the current time
          await supabase
              .from('khaiwals')
              .update({'sg_updated_at': now.toIso8601String()})
              .eq('id', AppState().khaiwalId);

          AppState().sgUpdatedAt = now;

          final response = await supabase
              .from('khaiwals_players')
              .update({field: value})
              .eq('id', userData['kp_id']);

          if (response == null) {
            AppState().userSettings[field] = value;

            if (field == 'allowed') {
              // Update the appropriate user list based on 'allowed'
              final user = AppState().users.firstWhere(
                    (user) => user['kp_id'] == userData['kp_id'],
                orElse: () => {},
              );
              if (user.isNotEmpty) {
                user[field] = value;
              }
            }
            AppState().isResetting = true;
          }
          // print('printing when final');
          Navigator.of(context).pop(); // Dismiss loading dialog
          return;
        }
      }

    }

    // Check for device mismatch
    final isMismatch = await AppState().checkDeviceMismatch(context);
    if (isMismatch) return; // Halt if there's a mismatch

    final response = await supabase
        .from('khaiwals_players')
        .update({field: value})
        .eq('id', userData['kp_id']);

    if (response == null) {
      setState(() {
        AppState().userSettings[field] = value;
      });
      if (field == 'allowed') {
        // Update the appropriate user list based on 'allowed'
        final user = AppState().users.firstWhere(
              (user) => user['kp_id'] == userData['kp_id'],
          orElse: () => {},
        );
        if (user.isNotEmpty) {
          user[field] = value;
        }
      }
    } else {
      // Handle update error
    }
    Navigator.of(context).pop(); // Dismiss loading dialog
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Scaffold(
          appBar: AppBar(
            // title: Text(userData['full_name'] ?? 'User'),
            title: const Text('User'),
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
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'Rename' || value == 'Renamed') {
                    _showRenameDialog(context);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: userData['is_renamed'] == true ? 'Renamed' : 'Rename',
                    child: Text(userData['is_renamed'] == true ? 'Renamed' : 'Rename'),
                  ),
                ],
              ),
            ],
          ),
          body: loading  // Use loading from AppState if needed
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _fetchUserData,
                child: SingleChildScrollView(
                  child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // User's avatar
                    CircleAvatar(
                      radius: 60,
                      backgroundImage: (userData['avatar_url'] != null && userData['avatar_url'].isNotEmpty)
                          ? NetworkImage(userData['avatar_url'])
                          : null,
                      backgroundColor: (userData['avatar_url'] == null || userData['avatar_url'].isEmpty)
                          ? (userData['full_name'] != null && userData['full_name']!.isNotEmpty)
                          ? _isNumeric(userData['full_name']!)
                          ? Colors.blueGrey // Background for numeric-only names
                          : getColorForLetter(getFirstValidLetter(userData['full_name'])?.toUpperCase() ?? '')
                          : Colors.grey // For null or empty names
                          : Colors.transparent,
                      child: (userData['avatar_url'] == null || userData['avatar_url'].isEmpty)
                          ? (getFirstValidLetter(userData['full_name']) != null
                          ? Text(
                        getFirstValidLetter(userData['full_name'])!.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 50,
                          fontWeight: FontWeight.normal,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(
                        Icons.person,
                        size: 50,
                        color: Colors.white,
                      ))
                          : null,
                    ),

                    const SizedBox(height: 16),
                    // User's full name
                    Text(
                      (userData['full_name']?.isNotEmpty == true)
                          ? userData['full_name']!
                          : 'No Name',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 16),
                    // Wallet balance section
                    Text(
                      '${appState.userSettings['balance']}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: appState.userSettings['balance'] > 0
                            ? Colors.green
                            : (appState.userSettings['balance'] < 0 ? Colors.red : Colors.black), // Black for 0, green for > 0, red for < 0
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Total balance',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft, // Align text to the left
                      child: Text(
                        'Quick actions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.history, color: Colors.green), // Icon for Game History
                            title: const Text('Game History'),
                            subtitle: const Text('For all played game records'), // Subtitle for Game History
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16), // Trailing arrow
                            onTap: () {
                              // Navigate to Game History
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => GameHistoryPage(
                                    kpId: userData['kp_id'], // Pass kpId here
                                    fullName: userData['full_name'] ?? 'User', // Pass kpId here
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          ListTile(
                              leading: const Icon(Icons.history, color: Colors.blue),
                              title: const Text('Transaction History'),
                              subtitle: const Text('For all balance debits & credits'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                // Navigate to Transaction History
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TransactionPage(
                                      kpId: userData['kp_id'],
                                      fullName: userData['full_name'] ?? 'User',// Pass kpId here
                                    ),
                                  ),
                                );
                              }),
                          const Divider(),
                          ListTile(
                              leading: const Icon(Icons.history, color: Colors.grey),
                              title: Row(
                                  children: [
                                  const Text('Request History'),
                                    if (appState.userSettings['null_action_count'] > 0)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 20.0),
                                        child: Icon(
                                          Icons.pending_actions,
                                          color: Colors.orange,
                                          size: 20,
                                        ),
                                      ),
                                    if (appState.userSettings['null_action_count'] > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4.0),
                                        child: Text(
                                          '${appState.userSettings['null_action_count']}',
                                          style: const TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],),
                              subtitle: const Text('For all requests records'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                // Determine currentView dynamically based on 'allowed' field
                                // final currentView = appState.userSettings['allowed'] == true
                                //     ? 'Active'
                                //     : appState.userSettings['allowed'] == false
                                //     ? 'Blocked'
                                //     : 'Pending';
                                // Navigate to Request History
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => KplogsPage(
                                      kpId: userData['kp_id'], // Pass kpId here
                                      // currentView: currentView, // Pass calculated currentView
                                      nullActionCount: appState.userSettings['null_action_count'], // Pass calculated currentView
                                      fullName: userData['full_name'] ?? 'User',
                                      balance: appState.userSettings['balance'],
                                    ),
                                  ),
                                );
                              }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Edit User Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Card(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                _buildEditableAllowedField('Connection Status', 'allowed', appState.userSettings['allowed']),
                                const Divider(),
                                _buildEditableField('Rate  (1 X ?)', 'rate', appState.userSettings['rate']),
                                const Divider(),
                                _buildEditableField('Commission %', 'commission', appState.userSettings['commission']),
                                const Divider(),
                                _buildEditableField('Loan Limit', 'debt_limit', appState.userSettings['debt_limit']),
                                const Divider(),
                                _buildEditableField('Close Edit', 'edit_minutes', appState.userSettings['edit_minutes']),
                                const Divider(),
                                _buildEditableField('Limit after big play time', 'big_play_limit', appState.userSettings['big_play_limit']),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                  ),
                ),
          ),
        );
      },
    );
  }


  Widget _buildEditableField(String title, String field, dynamic value) {
    String displayValue;

    // Customize the display based on the field and value
    if (field == 'edit_minutes') {
      if (value == -1) {
        displayValue = 'Disabled';
      } else if (value == 0) {
        displayValue = 'Till Close Time';
      } else {
        displayValue = '$value minutes';
      }
    } else if (field == 'debt_limit') {
      displayValue = '$value'; // Format loan limit with currency symbol
    } else if (field == 'big_play_limit') {
      if (value == -1) {
        displayValue = 'No Limit';
      } else if (value == 0) {
        displayValue = 'Disable Play';
      } else {
        displayValue = '$value';
      }
    } else {
      displayValue = value != null ? value.toString() : 'Not Set';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(title),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                onPressed: () {
                  _showInfoDialog(field); // Show a dialog with field info
                },
              ),
            ],
          ),
          Row(
            children: [
              Text(displayValue),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  dynamic newValue;
                  if (field == 'rate' || field == 'commission') {
                    newValue = await _showNumberPickerDialog(field, value);
                  } else if (field == 'debt_limit') {
                    newValue = await _showLoanLimitPickerDialog(value);
                  } else if (field == 'edit_minutes') {
                    newValue = await _showLastEditMinutesPickerDialog(value);
                  } else if (field == 'big_play_limit') {
                    newValue = await _showBigPlayLimitPickerDialog(value);
                  } else {
                    newValue = await _showEditDialog(field, value);
                  }

                  if (newValue != null) {
                    await _updateUserSetting(field, newValue);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }



  // Helper method for "Allowed" field with updated labels
  Widget _buildEditableAllowedField(String title, String field, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          DropdownButton<String>(
            value: value == null ? 'Pending' : value ? 'Connected' : 'Blocked',
            onChanged: (newValue) async {
              if (newValue != null) {
                bool? updatedValue;
                if (newValue == 'Connected') {
                  updatedValue = true;
                } else if (newValue == 'Blocked') {
                  updatedValue = false;
                } else {
                  updatedValue = null; // Disconnected
                }
                await _updateUserSetting(field, updatedValue);
                AppState().notifyListeners();
                // await AppState().fetchMenuUsers(); replaced with AppState().notifyListeners();
                // if (widget.currentView == 'Active') {
                //   await AppState().fetchUsers();
                // } else if (widget.currentView == 'Blocked') {
                //   await AppState().fetchBlockedUsers();
                // } else {
                //   await AppState().fetchPendingUsers();
                // }
              }
            },
            items: const [
              DropdownMenuItem(
                value: 'Connected',
                child: Text(
                  'Connected',
                  style: TextStyle(color: Colors.green),
                ),
              ),
              DropdownMenuItem(
                value: 'Pending',
                child: Text(
                  'Pending',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
              DropdownMenuItem(
                value: 'Blocked',
                child: Text(
                  'Blocked',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // Dialog for editing fields other than Rate/Commission
  Future<dynamic> _showEditDialog(String field, dynamic currentValue) async {
    TextEditingController controller = TextEditingController(text: currentValue?.toString() ?? '');
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit $field'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Enter new value'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, controller.text);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<dynamic> _showNumberPickerDialog(String field, int currentValue) async {
    int pickerValue = currentValue; // Use the current value as the starting value

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit $field'),
          content: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NumberPicker(
                      value: pickerValue,
                      minValue: 0,
                      maxValue: 100,
                      step: 1,
                      axis: Axis.vertical,
                      onChanged: (value) {
                        setState(() {
                          pickerValue = value; // Update the local pickerValue and rebuild the widget
                        });
                      },
                      itemCount: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                    ),
                    Text('Selected Value: $pickerValue'),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog without saving
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, pickerValue); // Return the selected value
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<dynamic> _showLoanLimitPickerDialog(int currentValue) async {
    int pickerValue = currentValue;

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Loan Limit'),
          content: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NumberPicker(
                      value: pickerValue,
                      minValue: -30000,
                      maxValue: 0,
                      step: 50,
                      axis: Axis.vertical,
                      onChanged: (value) {
                        setState(() {
                          pickerValue = value; // Update the local pickerValue and rebuild the widget
                        });
                      },
                      itemCount: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                    ),
                    Text('Selected Value: $pickerValue'),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog without saving
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, pickerValue); // Return the selected value
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<dynamic> _showLastEditMinutesPickerDialog(int currentValue) async {
    int pickerValue = currentValue;

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Last Edit Minutes'),
          content: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NumberPicker(
                      value: pickerValue,
                      minValue: -1,
                      maxValue: 120,
                      step: 1,
                      axis: Axis.vertical,
                      onChanged: (value) {
                        setState(() {
                          pickerValue = value; // Update the local pickerValue
                        });
                      },
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                      itemCount: 5,
                      // Map -1 to "Disable" and 0 to "Till Close Time"
                      textMapper: (numberText) {
                        if (numberText == '-1') {
                          return 'Disable';
                        } else if (numberText == '0') {
                          return 'Close Time';
                        } else {
                          return numberText;
                        }
                      },
                    ),
                    // Display "Disable" when pickerValue is -1, otherwise show the value in minutes
                    Text(
                      pickerValue == -1
                          ? 'Disabled'
                          : pickerValue == 0
                          ? 'Till Close Time'
                          : 'Selected Value: $pickerValue minutes',
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog without saving
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, pickerValue); // Return the selected value
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }


  Future<dynamic> _showBigPlayLimitPickerDialog(int currentValue) async {
    // Create a unique list of values: -1, 0, 50, 100, ..., 30000
    final List<int> bigPlayValues = [-1, 0, ...List.generate(600, (index) => (index + 1) * 50)];

    // Find the initial index of the current value
    int pickerIndex = bigPlayValues.indexOf(currentValue);
    if (pickerIndex == -1) {
      pickerIndex = 0; // Default to the first value if the currentValue is not in the list
    }

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Big Play Limit'),
          content: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NumberPicker(
                      value: pickerIndex, // Use the index of the current value
                      minValue: 0,
                      maxValue: bigPlayValues.length - 1,
                      onChanged: (index) {
                        setState(() {
                          pickerIndex = index; // Update the picker index
                        });
                      },
                      textMapper: (value) {
                        final int intValue = bigPlayValues[int.parse(value)];
                        if (intValue == -1) return 'No Limit';
                        if (intValue == 0) return 'Disable';
                        return intValue.toString();
                      },
                      itemCount: 5, // Adjust visible items for a better look
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Selected Value: ${bigPlayValues[pickerIndex] == -1 ? "No Limit" : bigPlayValues[pickerIndex] == 0 ? "Disable" : bigPlayValues[pickerIndex]}'),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog without saving
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, bigPlayValues[pickerIndex]); // Return the selected value
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }


  void _showRenameDialog(BuildContext context) {
    final TextEditingController renameController = TextEditingController();
    renameController.text = userData['full_name'] ?? ''; // Prefill the text field
    String? errorMessage; // Holds the error message to display
    final String? defaultName = userData['default_name']; // Store the default name

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Rename User'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (userData['is_renamed'] == true && defaultName != null) // Show only if renamed and defaultName exists
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Default Name: $defaultName',
                          style: const TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    TextField(
                      controller: renameController,
                      decoration: InputDecoration(
                        labelText: 'Enter new name',
                        hintText: 'Enter a new name for the user',
                        errorText: errorMessage, // Show error message if not null
                      ),
                      onChanged: (value) {
                        // Remove errorMessage when the user types
                        if (errorMessage != null) {
                          setState(() {
                            errorMessage = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                  },
                  child: const Text('Cancel'),
                ),
                if (userData['is_renamed'] == true) // Show only if renamed
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context); // Close dialog
                      await _useDefaultName();
                    },
                    child: const Text('Use Default'),
                  ),
                TextButton(
                  onPressed: () async {
                    final newName = renameController.text.trim();
                    if (newName.isEmpty) {
                      // Update errorMessage and refresh dialog
                      setState(() {
                        errorMessage = 'Name cannot be empty!';
                      });
                    } else {
                      Navigator.pop(context); // Close dialog
                      await _updateUserName(newName);
                    }
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }




  /// Update Player Name in Database
  Future<void> _updateUserName(String newName) async {
    try {
      final response = await supabase
          .from('khaiwals_players')
          .update({'player_renamed': newName})
          .eq('id', userData['kp_id']);

      if (response == null) {
        setState(() {
          userData['full_name'] = newName;
          userData['is_renamed'] = true;
        });
        AppState().notifyListeners();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated successfully!')),
        );
      } else {
        throw response!;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update name: $e')),
      );
    }
  }

  /// Set Default Name
  Future<void> _useDefaultName() async {
    try {
      final response = await supabase
          .from('khaiwals_players')
          .update({'player_renamed': null})
          .eq('id', userData['kp_id']);

      if (response == null) {
        setState(() {
          userData['full_name'] = userData['default_name'];
          userData['is_renamed'] = false;
        });
        AppState().notifyListeners();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default name restored!')),
        );
      } else {
        throw response!;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restore default name: $e')),
      );
    }
  }

  void _showInfoDialog(String field) {
    String infoText;

    // Add detailed information for each field
    switch (field) {
      case 'rate':
        infoText = 'Rate refers to the multiplier for a win. For example, if the rate is 90, the winning payout will be 90 times the played amount. If a user wins on any lucky number from 00 to 99, the payout will be calculated as follows: Winning Payout = Played Amount * Rate. For example, if a user plays 100 and the rate is 90, and they win on a lucky number, their winning payout will be 100 * 90 = 9000.';
        break;
      case 'commission':
        infoText = 'Commission is a percentage of the total amount played in a game. It is deducted from the total amount played, regardless of whether the user wins or loses. For example, if the commission is 10%, the user will receive 10% of their total played, regardless of the outcome of the game.';
        break;
      case 'patti':
        infoText = 'Patti refers to the card value in the game, used for specific game calculations.';
        break;
      case 'debt_limit':
        infoText = 'Loan Limit sets the maximum amount a user can borrow or play in advance. If the Loan Limit is not set or is 0 then the user must have a positive wallet balance to play games, If the Loan Limit is set to a value (e.g., -100), the user can play games until their wallet balance reaches the Loan Limit. Negative wallet balances represent advance or loan.';
        break;
      case 'edit_minutes':
        infoText = 'Close Edit specifies the time window when user no longer able to edit their played games in the last minutes before game ends.';
        break;
      case 'big_play_limit':
        infoText = 'Big Play Limit: sets the maximum limit a user can play on a single number after the big play time is over. For example, if the Big Play Limit is set to 200, the user cannot play more than 200 on any single number when the game time is between the big play time & close time.';
        break;
      case 'allowed':
        infoText = 'Allowed defines whether the user is currently permitted to participate in games or not.';
        break;
      default:
        infoText = 'No information available for this field.';
    }

    // Show a dialog with the information
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Field Information'),
          content: SingleChildScrollView(child: Text(infoText)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
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

  bool _isNumeric(String input) {
    final numericRegex = RegExp(r'^[0-9]+$');
    return numericRegex.hasMatch(input);
  }

  Future<bool> _showGameLimitExceededConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Subscription Limit Reached'),
          content: const Text(
            'You have exceeded the number of users allowed in your current subscription plan. '
                'If you proceed, you will have only 1 hour to configure the activeness of all your games & users. '
                'After this period, further changes will not be allowed for the next 2 days. '
                '\n\nWould you like to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // User chooses not to proceed
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // User chooses to proceed
              },
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    ) ?? false; // Return false if the dialog is dismissed without a choice
  }


  // Information dialog handler
  void _showDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ok'),
            ),
          ],
        );
      },
    );
  }


  @override
  void dispose() {

    super.dispose();
  }


}
