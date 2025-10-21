import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:masterking/main.dart';
import 'package:masterking/models/app_state.dart';
import 'package:numberpicker/numberpicker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {

  Map<String, dynamic> profileSettings = {};
  // Map to store the information for each field
  final Map<String, String> fieldInfo = {
    'full_name': 'Enter the user\'s full name. This will be displayed as the user\'s name.',
    'username': 'Your username is your unique identity within the app. It helps others recognize you and is used for personalized experiences. Usernames must be unique and can only be updated once every 30 days. Choose a username that represents you and complies with our community guidelines.',
    'rate': '(Applied on New Users only) Set the user\'s rate as a multiplier. This will be shown as default in the search.',
    'refresh_diff': 'Set the delay hours (in minutes) for the next day game. This will affect the game timing.',
    'refund_days': 'Set the number of days for the refund option. It can be 1, 2, or 3 days.',
    'edit_minutes': '(Applied on New Users only) Close Edit specifies the time window when users can no longer edit their played games in the last minutes before the game ends. For example, if set to 10 minutes, users cannot edit their games 10 minutes before close time.',
    'big_play_limit': '(Applied on New Users only) Big Play Limit sets the maximum amount a user can play on a single number after the big play time is over. For example, if set to 200, users cannot play more than 200 on any single number during the time between big play time and close time.',
    // Information for 'phone' and 'message'
    'phone': 'Enter the phone number. This will allow players to contact with you for queries or support.',
    'message': 'Enter the message or chat contact number. Players can use this to reach you for assistance or updates.',
    'email': 'Enter a valid email address. This will be used for users to contact you. Make sure it is accessible.\n\nNote: The default email address associated with your account cannot be changed, as it is used for login purposes.',
  };

  bool loading = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    setState(() {
      loading = true;
    });

    final response = await supabase
        .from('khaiwals')
        .select('full_name, email, username, avatar_url, rate, edit_minutes, big_play_limit, refresh_diff, refund_days, phone, message')
        .eq('id', AppState().khaiwalId)
        .maybeSingle();

    if (response != null) {
      setState(() {
        profileSettings = {
          'full_name': response['full_name'] ?? '',
          'username': response['username'] ?? '',
          'email': response['email'] ?? '',
          'avatar_url': response['avatar_url'],
          'phone': response['phone'] ?? '',
          'message': response['message'] ?? '',
          'rate': response['rate'] ?? 0,
          'edit_minutes': response['edit_minutes'] ?? 0,
          'big_play_limit': response['big_play_limit'] ?? 0,
          'refresh_diff': response['refresh_diff'] ?? 0,
          'refund_days': response['refund_days'] ?? 0,
        };
      });
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Failed to fetch user data.")));
    }

    setState(() {
      loading = false;
    });
  }

  // Method to update user data in Supabase
  Future<void> _updateUserSetting(String field, dynamic value) async {
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

    // Check for device mismatch
    final isMismatch = await AppState().checkDeviceMismatch(context);
    if (isMismatch) return; // Halt if there's a mismatch

    if (field == 'username') {
      // Handle the cooldown logic for username changes
      final response = await supabase
          .from('khaiwals')
          .select('last_username_change')
          .eq('id', AppState().khaiwalId)
          .maybeSingle();

      if (response == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to fetch cooldown information.")),
        );
        Navigator.of(context).pop(); // Dismiss loading dialog
        return;
      }
      String? lastChange = response['last_username_change'];
      final currentTime = AppState().currentTime;

      // Cooldown validation
      if (lastChange != null) {
        final lastChangeTime = DateTime.parse(lastChange);
        final differenceInDays = currentTime.difference(lastChangeTime).inDays;

        if (differenceInDays <= 30) {
          final daysLeft = 30 - differenceInDays; // Calculate days left for cooldown
          Navigator.of(context).pop(); // Dismiss loading dialog
          _showInfoDialog('Username update', 'Cool down period of 30 days is not over yet. Please wait $daysLeft day(s) to update your username again.');
          return;
        }
      }
      // Update username
      await _updateUsername(value, currentTime);
      AppState().notifyListeners();
      Navigator.of(context).pop(); // Dismiss loading dialog
      return;
    }

    final updateResponse = await supabase
        .from('khaiwals')
        .update({field: value, 'updated_at': AppState().currentTime.toIso8601String()})
        .eq('id', AppState().khaiwalId);

    if (updateResponse == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated successfully!")));
      setState(() {
        profileSettings[field] = value;
      });
      if (field == 'rate') {
        AppState().defaultRate = value;
      } else if (field == 'full_name') {
        AppState().khaiwalName = value;
      }
      AppState().notifyListeners();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Update failed! Please try again.")));
    }

    Navigator.of(context).pop(); // Dismiss loading dialog
  }

  Future<void> _updateUsername(String username, DateTime currentTime) async {
    try{
      // Update the username
      final updateResponse = await supabase
          .from('khaiwals')
          .update({
        'username': username.trim(),
      }).eq('id', AppState().khaiwalId);

      if (updateResponse == null) {
        await supabase
            .from('khaiwals')
            .update({
          'last_username_change': currentTime.toIso8601String(),
        }).eq('id', AppState().khaiwalId);

        setState(() {
          profileSettings['username'] = username;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Username updated successfully!")),
        );
      }
    } catch (e){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Username is already taken by someone, Choose another username")),
      );
    }
  }


  Future<void> _updateAvatarUrl(String? newUrl) async {
    try {
      final response = await supabase
          .from('khaiwals')
          .update({'avatar_url': newUrl})
          .eq('id', AppState().khaiwalId);

      if (response == null) {
        setState(() {
          profileSettings['avatar_url'] = newUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newUrl == null ? "Profile picture deleted!" : "Profile picture updated!")),
        );
      } else {
        throw Exception("Update failed");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to update profile picture! Please try again.")),
      );
    }
  }


  void _pickNewAvatar() async {
    final avatarUrl = AppState().user?.userMetadata?['avatar_url'];
    // Confirmation to use default image
    if (avatarUrl != null) {
      final useDefaultImage = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Use Default Image'),
          content: const Text(
              'Your profile picture is empty. Do you want to use the default image?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use Default'),
            ),
          ],
        ),
      );

      if (useDefaultImage == true) {
        await _updateAvatarUrl(avatarUrl);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No Default Image available to update")),
      );
    }

  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile')
      ),
      body: loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar Display
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundImage: (profileSettings['avatar_url'] != null && profileSettings['avatar_url'].isNotEmpty)
                          ? NetworkImage(profileSettings['avatar_url'])
                          : null,
                      backgroundColor: (profileSettings['avatar_url'] == null || profileSettings['avatar_url'].isEmpty)
                          ? (profileSettings['full_name'] != null && profileSettings['full_name']!.isNotEmpty)
                          ? _isNumeric(profileSettings['full_name']!)
                          ? Colors.blueGrey // Background for numeric-only names
                          : getColorForLetter(getFirstValidLetter(profileSettings['full_name'])?.toUpperCase() ?? '')
                          : Colors.grey // For null or empty names
                          : Colors.transparent,
                      child: (profileSettings['avatar_url'] == null || profileSettings['avatar_url'].isEmpty)
                          ? (getFirstValidLetter(profileSettings['full_name']) != null
                          ? Text(
                        getFirstValidLetter(profileSettings['full_name'])!.toUpperCase(),
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
                    // Mini Button: Delete or Edit
                    Positioned(
                      bottom: 5,
                      right: 5,
                      child: GestureDetector(
                        onTap: () async {
                          if (profileSettings['avatar_url'] != null &&
                              profileSettings['avatar_url']!.isNotEmpty) {
                            // Delete Confirmation
                            final shouldDelete = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Profile Picture'),
                                content: const Text(
                                    'Are you sure you want to delete your profile picture?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (shouldDelete == true) {
                              // Set avatar_url to null in Supabase
                              await _updateAvatarUrl(null);
                            }
                          } else {
                            // Edit Avatar
                            _pickNewAvatar(); // Add your image picker logic here
                          }
                        },
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: Colors.redAccent,
                          child: Icon(
                            profileSettings['avatar_url'] != null &&
                                profileSettings['avatar_url']!.isNotEmpty
                                ? Icons.delete // Delete button
                                : Icons.edit, // Edit button
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ]
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Profile',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              // First Group: Profile Information
              Card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          _buildEditableField(
                              context, 'Full Name', 'full_name', profileSettings['full_name'], isText: true),
                          const Divider(),
                          _buildEditableField(
                              context, 'Username', 'username', profileSettings['username'], isText: true),
                          const Divider(),
                          _buildEditableField(
                              context, 'Email', 'email', profileSettings['email'], isText: true),
                          const Divider(),
                          _buildEditableField(
                              context, 'Phone (optional)', 'phone', profileSettings['phone'], isText: true),
                          const Divider(),
                          _buildEditableField(
                              context, 'Message (optional)', 'message', profileSettings['message'], isText: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Settings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              // Second Group: Settings
              Card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          _buildEditableField(context, 'Default Rate', 'rate', profileSettings['rate'], min: 0, max: 100),
                          const Divider(),
                          _buildEditableField(context, 'Default Close Edit Minutes', 'edit_minutes', profileSettings['edit_minutes']),
                          const Divider(),
                          _buildEditableField(context, 'Default Limit After Big Play time', 'big_play_limit', profileSettings['big_play_limit']),
                          const Divider(),
                          _buildDurationEditableField(context, 'Refresh Delay After 12 AM', 'refresh_diff', profileSettings['refresh_diff'] ?? 0),
                          const Divider(),
                          _buildEditableField(context, 'Give Refund Option (in days)', 'refund_days', profileSettings['refund_days'], min: 1, max: 3),
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
    );
  }

  Widget _buildEditableField(
      BuildContext context,
      String title,
      String field,
      dynamic value, {
        bool isText = false,
        int? min,
        int? max,
      }) {
    String displayValue;

    // Customize the display based on the field and value
    if (field == 'edit_minutes') {
      if (value == -1) {
        displayValue = 'Disable Play';
      } else if (value == 0) {
        displayValue = 'Till Close Time';
      } else {
        displayValue = '$value minutes';
      }
    } else if (field == 'big_play_limit') {
      if (value == -1) {
        displayValue = 'No Limit';
      } else if (value == 0) {
        displayValue = 'Disabled';
      } else {
        displayValue = '$value';
      }
    } else {
      displayValue = value != null ? value.toString() : 'Not Set';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // For better alignment if text wraps
        children: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
            onPressed: () {
              String infoText = fieldInfo[field] ?? 'No information available.';
              _showInfoDialog(title, infoText);
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  style: const TextStyle(color: Colors.grey),
                  overflow: TextOverflow.ellipsis, // Truncate long text
                  maxLines: 1, // Optional to limit lines if needed
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              if (field == 'username') {
                final shouldProceed = await _showUsernameConfirmationDialog(context);
                if (!shouldProceed) return;
              }

              dynamic newValue;

              // Handle phone and message fields separately
              if (field == 'phone' || field == 'message') {
                newValue = await _showNumberEditDialog(context, field, value?.toString() ?? '');
              }
              // Use the custom dialog for 'edit_minutes'
              else if (field == 'edit_minutes') {
                newValue = await _showLastEditMinutesPickerDialog(value ?? 0); // Pass current value or default to 0
              }
              // Use the custom dialog for 'big_play_limit'
              else if (field == 'big_play_limit') {
                newValue = await _showBigPlayLimitPickerDialog(value ?? 0); // Pass current value or default to 0
              }
              // Existing logic for text fields
              else if (isText) {
                newValue = await _showEditDialog(context, field, value, TextInputType.text);
              }
              // Existing logic for numeric pickers
              else if (min != null && max != null) {
                newValue = await _showNumberPickerDialog(context, field, value, min, max);
              }

              // Update user setting only if a new value was provided
              if (newValue != null) {
                if (newValue == '') {
                  await _updateUserSetting(field, null);
                } else {
                  await _updateUserSetting(field, newValue);
                }
              }
            },
          )
        ],
      ),
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


  Widget _buildDurationEditableField(
      BuildContext context,
      String title,
      String field,
      int value,
      ) {
    // Convert stored negative minutes into positive hours and minutes for display
    String displayValue = '${-value ~/ 60}h ${-value % 60}m';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
            onPressed: () {
              _showInfoDialog(
                'Delay',
                'Set delay hours if your games close after midnight to extend into the next day.',
              );
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  style: const TextStyle(color: Colors.grey),
                  overflow: TextOverflow.ellipsis, // Ensures text does not overflow
                  maxLines: 1,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              int? newValue = await _showHourPickerDialog(context, field, value, -720, 0);
              if (newValue != null) {
                await _updateUserSetting(field, newValue);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<dynamic> _showHourPickerDialog(
      BuildContext context,
      String field,
      int currentValue,
      int min,
      int max,
      ) async {
    int pickerValue = currentValue;

    // Function to format the picker value into hours and minutes
    String formatTime(int value) {
      int hours = value ~/ 60; // Get hours
      int minutes = value % 60; // Get minutes
      return '${hours}h ${minutes}m';
    }

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Delay'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NumberPicker(
                      value: pickerValue,
                      minValue: min,
                      maxValue: max,
                      step: 30, // Step size of 30 minutes (half-hour intervals)
                      axis: Axis.vertical,
                      onChanged: (value) {
                        setState(() {
                          pickerValue = value;
                        });
                      },
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                    ),
                    // Display the selected time in the formatted 'Xh Ym' format
                    Text('Selected Delay: ${formatTime(pickerValue.abs())}'),
                  ],
                ),
              );
            },
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


  Future<dynamic> _showNumberEditDialog(
      BuildContext context, String field, String currentValue) async {
    TextEditingController controller = TextEditingController(text: currentValue);
    String? errorText;

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Edit ${field == 'phone' ? 'Phone Number' : 'Message Number'}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      maxLength: 15, // Optional: Limit the input length
                      decoration: InputDecoration(
                        hintText: 'Enter Number',
                        errorText: errorText,
                      ),
                      // Restrict input to digits only using input formatter
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (value) {
                        setState(() {
                          errorText = null; // Clear error text on change
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close without saving
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    String inputText = controller.text.trim();

                    if (inputText.isNotEmpty && inputText.length < 5) {
                      setState(() {
                        errorText = 'Input must be longer than 4 digits.';
                      });
                      return;
                    }

                    Navigator.pop(context, controller.text); // Return the valid input
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }




  Future<dynamic> _showNumberPickerDialog(BuildContext context, String field, int currentValue, int min, int max) async {
    int pickerValue = currentValue;

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit ${field == 'rate' ? 'Rate' : 'Refund Days'}'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NumberPicker(
                      value: pickerValue,
                      minValue: min,
                      maxValue: max,
                      step: 1,
                      axis: Axis.vertical,
                      onChanged: (value) {
                        setState(() {
                          pickerValue = value;
                        });
                      },
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                    ),
                    Text('Selected Value: $pickerValue'),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close without saving
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

  Future<dynamic> _showEditDialog(BuildContext context, String field, String? currentValue, TextInputType inputType) async {
    TextEditingController controller = TextEditingController(text: currentValue);
    String? errorText;

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Edit ${field == 'username' ? 'Username' : field == 'email' ? 'Email' : 'Field'}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      keyboardType: inputType,
                      maxLength: field == 'email' ? 50 : 35,
                      decoration: InputDecoration(
                        hintText: 'Enter $field',
                        errorText: errorText,
                      ),
                      onChanged: (value) {
                        setState(() {
                          errorText = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (field == 'username')
                      const Text(
                        "Guidelines for Username:\n"
                            "- Must be at least 3 characters long.\n"
                            "- Must not contain spaces.\n"
                            "- Must be in lowercase.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
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
                    String enteredText = controller.text.trim();

                    if (field == 'username') {
                      if (enteredText.length < 3) {
                        setState(() {
                          errorText = 'Must be at least 3 characters long.';
                        });
                        return;
                      }
                      if (enteredText.contains(' ')) {
                        setState(() {
                          errorText = 'Username cannot contain spaces.';
                        });
                        return;
                      }
                      if (enteredText != enteredText.toLowerCase()) {
                        setState(() {
                          errorText = 'Username must be in lowercase.';
                        });
                        return;
                      }
                    } else if (field == 'email' && enteredText.isNotEmpty) {
                      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                      if (!emailRegex.hasMatch(enteredText)) {
                        setState(() {
                          errorText = 'Enter a valid email address.';
                        });
                        return;
                      }
                    }

                    Navigator.pop(context, enteredText);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }




  Future<bool> _showUsernameConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Username Change Confirmation'),
          content: const Text(
            'You can change your username only once every 30 days. Are you sure you want to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false); // Cancel
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true); // Proceed
              },
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    ) ??
        false; // Default to false if dialog is dismissed
  }


  // Method to show info dialog
  void _showInfoDialog(String field, String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$field Info'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
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


  @override
  void dispose() {

    super.dispose();
  }
}
