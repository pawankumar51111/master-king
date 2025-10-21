import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:masterking/main.dart';
import 'package:masterking/models/app_state.dart';

class ManageGamePage extends StatefulWidget {
  final String shortGameName;
  final String gameDate;
  final int infoId;

  const ManageGamePage({super.key,
    required this.shortGameName,
    required this.gameDate,
    required this.infoId
  }); // Update constructor

  @override
  State<ManageGamePage> createState() => _ManageGamePageState();
}

class _ManageGamePageState extends State<ManageGamePage> {
  Map<String, dynamic> gameInfo = {};
  List<Map<String, dynamic>> gameData = [];
  late String shortGameName = widget.shortGameName;
  bool loading = true;
  String currentMonth = '';

  final DateFormat timeFormat = DateFormat('HH:mm'); // made it global to use it in updateGame method also

  @override
  void initState() {
    super.initState();
    _fetchGameData();
  }

  Future<void> _fetchGameData() async {
    setState(() {
      loading = true;
    });

    try {
      DateTime gameDate = DateTime.parse(widget.gameDate);

      final firstDayOfMonth = DateTime.utc(gameDate.year, gameDate.month, 1);
      final lastDayOfMonth = DateTime.utc(gameDate.year, gameDate.month + 1, 0);

      currentMonth = DateFormat.yMMM().format(gameDate);

      // Combine both queries into a single request
      final response = await supabase
          .from('games')
          .select('id, game_date, off_day, pause')
          .eq('info_id', widget.infoId)
          .gte('game_date', firstDayOfMonth.toIso8601String())
          .lte('game_date', lastDayOfMonth.toIso8601String());

      final infoResponse = await supabase
          .from('game_info')
          .select('id, full_game_name, short_game_name, open_time, big_play_min, close_time_min, result_time_min, day_before, is_active')
          .eq('id', widget.infoId);

      if (response.isNotEmpty && infoResponse.isNotEmpty) {
        // Sort the data by 'game_date'
        response.sort((a, b) {
          DateTime gameDateA = DateTime.parse(a['game_date']);
          DateTime gameDateB = DateTime.parse(b['game_date']);
          return gameDateA.compareTo(gameDateB); // Ascending order
        });

        setState(() {
          shortGameName = infoResponse[0]['short_game_name'] ?? '';
          gameData = List<Map<String, dynamic>>.from(response);
          gameInfo = infoResponse[0];
        });
      }
      setState(() {
        loading = false;
      });

    } catch (e) {
      print('Error fetching game data: $e');
      setState(() {
        loading = false;
      });
    }
  }

  String _formatBoolValue(bool? boolValue) {
    if (boolValue == null) {
      return 'No';
    }
    return boolValue ? 'Yes' : 'No';
  }

  // String _addMinutesFromOpenTime(String openTime, int addMinutes) {
  //   if (addMinutes != -1) {
  //     // Parse directly from openTime string
  //     final parts = openTime.split(':');
  //     if (parts.length >= 2) {
  //       final hour = int.parse(parts[0]);
  //       final minute = int.parse(parts[1]);
  //       final newTime = DateTime.utc(0, 1, 1, hour, minute).add(Duration(minutes: addMinutes));
  //       return DateFormat('hh:mm a').format(newTime);
  //     }
  //   }
  //   return 'null'; // Handle invalid openTime or -1 addMinutes
  // }

  String? _addMinutes(String openTime, String addMinutes) {
    if (addMinutes != '-1' && addMinutes.isNotEmpty) {

      final int minutesToAdd = int.tryParse(addMinutes) ?? 0;
      // Parse directly from openTime string
      final parts = openTime.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final newTime = DateTime.utc(0, 1, 1, hour, minute).add(Duration(minutes: minutesToAdd));
        return timeFormat.format(newTime);
      }
    }
    return null; // Handle invalid openTime or -1 addMinutes
  }

  // String _formatOpenTime(String openTime) {
  //   // Parse the openTime string directly
  //   final parts = openTime.split(':');
  //   // Ensure parts have at least 2 components (hour and minute)
  //   if (parts.length >= 2) {
  //     final hour = int.parse(parts[0]);
  //     final minute = int.parse(parts[1]);
  //     // Format using the hour and minute
  //     return DateFormat('hh:mm a').format(DateTime.utc(0, 1, 1, hour, minute));
  //   }
  //   return 'null'; // Handle case for invalid openTime
  // }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${gameInfo['full_game_name'] ?? ''} ( $shortGameName )'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'Select Month':
                  _showSelectMonthDialog();
                  break;
                case 'Edit Game':
                  _showEditGameDialog();  // Pass gameData to the edit dialog
                  break;
                case 'Delete Game':
                  _showDeleteDialog();  // Pass gameData to the edit dialog
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(
                  value: 'Select Month',
                  child: Text('Select Month'),
                ),
                const PopupMenuItem<String>(
                  value: 'Edit Game',
                  child: Text('Edit Game'),
                ),
                const PopupMenuItem<String>(
                  value: 'Delete Game',
                  child: Text('Delete Game'),
                ),
              ];
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: DataTable(
              columns: const <DataColumn>[
                DataColumn(label: Text('Game Date')),
                DataColumn(label: Text('Day Off')),
                DataColumn(label: Text('Pause')),
                DataColumn(label: Text('Edit')),
              ],
              rows: gameData
                  .map((game) => DataRow(
                cells: <DataCell>[
                  DataCell(Text(AppState().formatGameDate(game['game_date']))),
                  DataCell(Text(_formatBoolValue(game['off_day']))),
                  DataCell(Text(_formatBoolValue(game['pause']))),
                  DataCell(
                    ElevatedButton(
                      onPressed: () {
                        _showEditSingleGame(
                          context,
                          game['id'],
                          game['off_day'] ?? false,
                          game['pause'] ?? false,
                          game['game_date'], // Pass the game date as well
                        );
                      },
                      child: const Text('Edit'),
                    ),
                  ),
                ],
              ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditSingleGame(
      BuildContext context,
      int gameId,
      bool offDay,
      bool pause,
      String gameDate,
      ) async {

    bool isOffDay = offDay;
    bool isPaused = pause;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Edit Game for ${AppState().formatGameDate(gameDate)}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Open Time with Clock Icon
                    // Row(
                    //   children: [
                    //     IconButton(
                    //       icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                    //       onPressed: () => showInfoDialog('This option allows the game to open one day earlier.'),
                    //     ),
                    //     Expanded(
                    //       child: TextField(
                    //         controller: openTimeController,
                    //         decoration: const InputDecoration(labelText: 'Open Time'),
                    //         readOnly: true,
                    //         onTap: () => _selectTime(context, openTimeController),
                    //       ),
                    //     ),
                    //     IconButton(
                    //       icon: const Icon(Icons.access_time, color: Colors.green,),
                    //       onPressed: () => _clearTime(openTimeController),
                    //     ),
                    //   ],
                    // ),
                    //
                    // // Last Big Play Time with Clock Icon
                    // Row(
                    //   children: [
                    //     IconButton(
                    //       icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                    //       onPressed: () => showInfoDialog('This option allows the game to open one day earlier.'),
                    //     ),
                    //     Expanded(
                    //       child: TextField(
                    //         controller: lastBigPlayTimeController,
                    //         decoration: const InputDecoration(labelText: 'Last Big Play Time'),
                    //         readOnly: true,
                    //         onTap: () => _selectTime(context, lastBigPlayTimeController),
                    //       ),
                    //     ),
                    //     IconButton(
                    //       icon: const Icon(Icons.access_time, color: Colors.blue,),
                    //       onPressed: () => _clearTime(lastBigPlayTimeController),
                    //     ),
                    //   ],
                    // ),
                    //
                    // // Close Time with Clock Icon
                    // Row(
                    //   children: [
                    //     IconButton(
                    //       icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                    //       onPressed: () => showInfoDialog('This option allows the game to open one day earlier.'),
                    //     ),
                    //     Expanded(
                    //       child: TextField(
                    //         controller: closeTimeController,
                    //         decoration: const InputDecoration(labelText: 'Close Time'),
                    //         readOnly: true,
                    //         onTap: () => _selectTime(context, closeTimeController),
                    //       ),
                    //     ),
                    //     IconButton(
                    //       icon: const Icon(Icons.access_time, color: Colors.red,),
                    //       onPressed: () => _clearTime(closeTimeController),
                    //     ),
                    //   ],
                    // ),
                    //
                    // // Result Time with Clock Icon
                    // Row(
                    //   children: [
                    //     IconButton(
                    //       icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                    //       onPressed: () => showInfoDialog('This option allows the game to open one day earlier.'),
                    //     ),
                    //     Expanded(
                    //       child: TextField(
                    //         controller: resultTimeController,
                    //         decoration: const InputDecoration(labelText: 'Result Time'),
                    //         readOnly: true,
                    //         onTap: () => _selectTime(context, resultTimeController),
                    //       ),
                    //     ),
                    //     IconButton(
                    //       icon: const Icon(Icons.access_time, color: Colors.orange,),
                    //       onPressed: () => _clearTime(resultTimeController),
                    //     ),
                    //   ],
                    // ),

                    // Off Day Switch
                    SwitchListTile(
                      title: const Text('Off Day'),
                      value: isOffDay,
                      onChanged: (value) {
                        setState(() {
                          isOffDay = value;
                        });
                      },
                      activeTrackColor: Colors.green,
                      activeColor: Colors.white,
                    ),

                    // Pause Switch
                    SwitchListTile(
                      title: const Text('Pause'),
                      value: isPaused,
                      onChanged: (value) {
                        setState(() {
                          isPaused = value;
                        });
                      },
                      activeTrackColor: Colors.green,
                      activeColor: Colors.white,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Pass data such as game['id'], openTimeController.text, lastBigPlayTimeController.text, closeTimeController.text, resultTimeController.text, offDay, pause
                    _updateSingleDay(
                        gameId,
                        isOffDay,
                        isPaused,
                        gameDate,
                        offDay,
                        pause
                    );

                    Navigator.pop(context);
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


  Future<void> _fetchDataForSelectedMonth(String selectedMonth) async {
    setState(() {
      loading = true;
    });
    try {
      final DateFormat format = DateFormat.yMMM();
      final DateTime monthDate = format.parse(selectedMonth);
      final firstDayOfMonth = DateTime(monthDate.year, monthDate.month, 1);
      final lastDayOfMonth = DateTime(monthDate.year, monthDate.month + 1, 0);
      // Combine both queries into a single request
      final response = await supabase
          .from('games')
          .select('id, game_date, off_day, pause')
          .eq('info_id', widget.infoId)
          .gte('game_date', firstDayOfMonth.toIso8601String())
          .lte('game_date', lastDayOfMonth.toIso8601String());

      final infoResponse = await supabase
          .from('game_info')
          .select('id, full_game_name, short_game_name, open_time, big_play_min, close_time_min, result_time_min, day_before, is_active')
          .eq('id', widget.infoId);

      if (response.isNotEmpty && infoResponse.isNotEmpty) {
        // Sort the data by 'game_date'
        response.sort((a, b) {
          DateTime gameDateA = DateTime.parse(a['game_date']);
          DateTime gameDateB = DateTime.parse(b['game_date']);
          return gameDateA.compareTo(gameDateB); // Ascending order
        });

        setState(() {
          shortGameName = infoResponse[0]['short_game_name'] ?? '';
          gameData = List<Map<String, dynamic>>.from(response);
          gameInfo = infoResponse[0];
        });
      }

      setState(() {
        loading = false;
      });

    } catch (e) {
      print('Error fetching game data: $e');

      setState(() {
        loading = false;
      });
    }
  }

  // DateTime _getFirstDayOfMonth() {
  //   // Find the minimum date from gameData
  //   return gameData.map((game) => DateTime.parse(game['game_date']))
  //       .reduce((a, b) => a.isBefore(b) ? a : b);
  // }
  //
  // DateTime _getLastDayOfMonth() {
  //   // Find the maximum date from gameData
  //   return gameData.map((game) => DateTime.parse(game['game_date']))
  //       .reduce((a, b) => a.isAfter(b) ? a : b);
  // }
  //
  // // Function to find the most frequent value (int or String)
  // String _getMostFrequentOpenTime(dynamic value) {
  //   Map<dynamic, int> openTimeCount = {}; // Use dynamic for both key and value
  //
  //   // Count the occurrences of each value
  //   for (var game in gameData) {
  //     var openTime = game[value]; // It can be either int or String
  //     if (openTime != null && openTime.toString().isNotEmpty) {
  //       openTimeCount[openTime] = (openTimeCount[openTime] ?? 0) + 1;
  //     }
  //   }
  //
  //   // Determine the most frequent value
  //   dynamic mostFrequentOpenTime;
  //   int maxCount = 0;
  //
  //   openTimeCount.forEach((openTime, count) {
  //     if (count > maxCount) {
  //       maxCount = count;
  //       mostFrequentOpenTime = openTime;
  //     }
  //   });
  //
  //   // Return the most frequent value as a string
  //   return mostFrequentOpenTime.toString();
  // }


  Future<void> _showEditGameDialog() async {
    TextEditingController fullGameNameController = TextEditingController(text: gameInfo['full_game_name']);
    TextEditingController shortGameNameController = TextEditingController(text: shortGameName);
    // String mostOpenTime = _getMostFrequentOpenTime('open_time');
    DateTime parsedOpenTime = timeFormat.parse(gameInfo['open_time']);
    String formattedOpenTime = timeFormat.format(parsedOpenTime);
    TextEditingController openTimeController = TextEditingController(text: formattedOpenTime);
    // String mostLastBigPlayMin = _getMostFrequentOpenTime('last_big_play_min');
    TextEditingController lastBigPlayTimeController = TextEditingController(text: _addMinutes(gameInfo['open_time'], gameInfo['big_play_min'].toString()));
    // String mostCloseTimeMin = _getMostFrequentOpenTime('close_time_min');
    TextEditingController closeTimeController = TextEditingController(text: _addMinutes(gameInfo['open_time'], gameInfo['close_time_min'].toString()));
    // String mostResultTimeMin = _getMostFrequentOpenTime('result_time_min');
    TextEditingController resultTimeController = TextEditingController(text: _addMinutes(gameInfo['open_time'], gameInfo['result_time_min'].toString()));

    // Extract off days where 'off_day' is true
    List<DateTime> offDays = gameData
        .where((game) => game['off_day'] == true) // Filter for off days
        .map<DateTime>((game) => DateTime.parse(game['game_date'])) // Parse the game_date
        .toList(); // Convert to a list of DateTime

    DateTime selectedDay = DateTime.parse(gameData[0]['game_date']);

    bool openDayBefore = gameInfo['day_before'] ?? false; // Set from gameData
    bool isActive = gameInfo['is_active'] ?? true; // Set from gameData

    Future<void> selectTime(BuildContext context, TextEditingController controller) async {
      TimeOfDay initialTime;

      if (controller.text.isEmpty) {
        // If the controller's text is empty, show the current time
        initialTime = TimeOfDay.now();
      } else {
        try {
          // Try to parse the time from the controller's text
          DateTime initialDateTime = timeFormat.parse(controller.text);
          initialTime = TimeOfDay(hour: initialDateTime.hour, minute: initialDateTime.minute);
        } catch (e) {
          // If parsing fails, fall back to current time
          initialTime = TimeOfDay.now();
        }
      }

      // Open the TimePicker with the determined initial time
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: initialTime,
      );

      if (picked != null) {
        final time = DateTime(0, 0, 0, picked.hour, picked.minute);
        controller.text = timeFormat.format(time); // Update the controller with the selected time
      }
    }

    void clearTime(TextEditingController controller) {
      controller.clear();
    }

    // Create a copy of the initial offDays list to revert to if cancel is pressed
    List<DateTime> initialOffDays = List<DateTime>.from(offDays);

    void showOffDaysDialog() {

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return AlertDialog(
                title: const Text('Select Off Days'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      DateTime.utc(selectedDay.year, selectedDay.month + 1, 0).day,
                          (index) {
                        DateTime day = DateTime.utc(selectedDay.year, selectedDay.month, index + 1);

                        // Custom function to check if the day is in offDays (ignoring time)
                        bool isOffDay(DateTime day) {
                          return offDays.any((offDay) =>
                          offDay.year == day.year &&
                              offDay.month == day.month &&
                              offDay.day == day.day);
                        }

                        return CheckboxListTile(
                          title: Text(DateFormat('EEEE, dd MMMM').format(day)), // Display day and date
                          value: isOffDay(day),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                offDays.add(day);
                              } else {
                                offDays.removeWhere((offDay) =>
                                offDay.year == day.year &&
                                    offDay.month == day.month &&
                                    offDay.day == day.day);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      // Reset offDays to its initial state
                      setState(() {
                        offDays = List<DateTime>.from(initialOffDays);
                      });
                      Navigator.of(context).pop(); // Close dialog
                    },
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(), // Save and close
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          );
        },
      );
    }


    final shouldEditGame = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Game'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: fullGameNameController,
                      decoration: const InputDecoration(labelText: 'Full Game Name'),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(20), // Limit to 20 characters
                      ],
                    ),
                    TextField(
                      controller: shortGameNameController,
                      decoration: const InputDecoration(labelText: 'Short Game Name'),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(5), // Limit to 5 characters
                      ],
                    ),
                    const SizedBox(height: 4),
                    // const Divider(),
                    // const SizedBox(height: 4),
                    // Open Time with Clock Icon
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                          onPressed: () => showInfoDialog('This option set the open time of the game.'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: openTimeController,
                            decoration: const InputDecoration(labelText: 'Open Time'),
                            readOnly: true,
                            onTap: () => selectTime(context, openTimeController),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.access_time, color: Colors.green,),
                          onPressed: () => clearTime(openTimeController),
                        ),
                      ],
                    ),

                    // Last Big Play Time with Clock Icon
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                          onPressed: () => showInfoDialog('This option set the last big play time of game and after this time the user cannot play more than the limit you set for him on any single number when the game time is between the big play time & close time.'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: lastBigPlayTimeController,
                            decoration: const InputDecoration(labelText: 'Last Big Play Time'),
                            readOnly: true,
                            onTap: () => selectTime(context, lastBigPlayTimeController),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.access_time, color: Colors.blue,),
                          onPressed: () => clearTime(lastBigPlayTimeController),
                        ),
                      ],
                    ),

                    // Close Time with Clock Icon
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                          onPressed: () => showInfoDialog('This option set the close time of the game.'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: closeTimeController,
                            decoration: const InputDecoration(labelText: 'Close Time'),
                            readOnly: true,
                            onTap: () => selectTime(context, closeTimeController),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.access_time, color: Colors.red,),
                          onPressed: () => clearTime(closeTimeController),
                        ),
                      ],
                    ),

                    // Result Time with Clock Icon
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                          onPressed: () => showInfoDialog('This option set the result time of the game and users can expect the result around this time you set.'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: resultTimeController,
                            decoration: const InputDecoration(labelText: 'Result Time'),
                            readOnly: true,
                            onTap: () => selectTime(context, resultTimeController),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.access_time, color: Colors.orange,),
                          onPressed: () => clearTime(resultTimeController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Divider(),
                    const SizedBox(height: 4),

                    // Open a day before with Info Icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                          onPressed: () => showInfoDialog('This option allows the game to open one day earlier. (Mostly for games like DS)'),
                        ),
                        const Text('Open a day before'),
                        Switch(
                          value: openDayBefore,
                          onChanged: (value) {
                            setState(() {
                              openDayBefore = value;
                            });
                          },
                          activeTrackColor: Colors.green,
                          // inactiveTrackColor: Colors.grey,
                          activeColor: Colors.white,
                          // inactiveThumbColor: Colors.red,
                        ),
                      ],
                    ),

                    // Activate with Info Icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                          onPressed: () => showInfoDialog('This option can be used to Activate/Deactivate the game.'),
                        ),
                        const Text('Activate'),
                        Switch(
                          value: isActive,
                          onChanged: (value) {
                            setState(() {
                              isActive = value;
                            });
                          },
                          activeTrackColor: Colors.green,
                          activeColor: Colors.white,
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                          onPressed: () => showInfoDialog('This options is to set off days for the game.'),
                        ),
                        TextButton(
                          onPressed: showOffDaysDialog, // Show off days dialog on button press
                          child: const Text('Select Off Days'),
                        ),
                      ],
                    ),
                    const Divider(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    // Validate Full Game Name and Short Game Name
                    if (fullGameNameController.text.isEmpty || shortGameNameController.text.isEmpty) {
                      _showErrorDialog(context, 'Full Game Name and Short Game Name are mandatory');
                      return;
                    }
                    // Parse openTime and closeTime
                    if (openTimeController.text.isEmpty || closeTimeController.text.isEmpty) {
                      _showErrorDialog(context, 'Open Time and Close Time are mandatory');
                      return;
                    }

                    final DateTime openTime = timeFormat.parse(openTimeController.text);
                    final DateTime closeTime = timeFormat.parse(closeTimeController.text);
                    // Check if open time and close time are the same
                    if (openTime.isAtSameMomentAs(closeTime)) {
                      _showErrorDialog(context, 'Open Time and Close Time cannot be the same');
                      return;
                    }

                    // Check if Last Big Play Time is filled and within range
                    if (lastBigPlayTimeController.text.isNotEmpty) {
                      final DateTime lastBigPlayTime = timeFormat.parse(lastBigPlayTimeController.text);
                      if (lastBigPlayTime.isAfter(closeTime)) {
                        _showErrorDialog(context, 'Last Big Play Time must be before Close Time');
                        return;
                      }
                    }

                    // Validate Result Time (if filled)
                    if (resultTimeController.text.isNotEmpty) {
                      final DateTime resultTime = timeFormat.parse(resultTimeController.text);
                      if (!resultTime.isAfter(closeTime)) {
                        _showErrorDialog(context, 'Result Time must be after Close Time');
                        return;
                      }
                    }

                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldEditGame == true) {
      // Parse openTime and lastBigPlayTime into DateTime objects
      final DateTime openTime = timeFormat.parse(openTimeController.text);
      final DateTime closeTime = timeFormat.parse(closeTimeController.text);

      // Calculate the difference in minutes
      int closeTimeMin;

      // Check if closeTime is before openTime, which means closeTime is on the next day
      if (closeTime.isBefore(openTime)) {
        // Add one day (24 hours) to closeTime to handle the next day case
        closeTimeMin = closeTime.add(const Duration(days: 1)).difference(openTime).inMinutes;
      } else {
        // Regular case where closeTime is after openTime on the same day
        closeTimeMin = closeTime.difference(openTime).inMinutes;
      }

      int lastBigPlayMin = -1;
      if (lastBigPlayTimeController.text.isNotEmpty) {
        final DateTime lastBigPlayTime = timeFormat.parse(lastBigPlayTimeController.text);
        // Check if lastBigPlayTime is before openTime, which means it's on the next day
        if (closeTime.isBefore(openTime)) {
          // Add one day to lastBigPlayTime to handle the next day case
          lastBigPlayMin = lastBigPlayTime.add(const Duration(days: 1)).difference(openTime).inMinutes;
        } else {
          // Regular case where lastBigPlayTime is after openTime on the same day
          lastBigPlayMin = lastBigPlayTime.difference(openTime).inMinutes;
        }
      }

      int resultTimeMin = -1;
      if (resultTimeController.text.isNotEmpty) {
        final DateTime resultTime = timeFormat.parse(resultTimeController.text);

        // Check if resultTime is before openTime, which means it's on the next day
        if (closeTime.isBefore(openTime)) {
          // Add one day to resultTime to handle the next day case
          resultTimeMin = resultTime.add(const Duration(days: 1)).difference(openTime).inMinutes;
        } else {
          // Regular case where resultTime is after openTime on the same day
          resultTimeMin = resultTime.difference(openTime).inMinutes;
        }
      }
      // Perform the update here by calling your update method
      await _updateGame(
        fullGameNameController.text.trim(),
        shortGameNameController.text.trim(),
        openTimeController.text,
        lastBigPlayMin,
        closeTimeMin,
        resultTimeMin,
        offDays,
        openDayBefore,
        isActive,
        formattedOpenTime,
        gameInfo['big_play_min'],
        gameInfo['close_time_min'],
        gameInfo['result_time_min'],
        initialOffDays,
      );
    }
  }

  Future<void> _updateGame(
    String fullGameNames,
    String shortGameNames,
    String openTime,
    int lastBigPlayMin,
    int closeTimeMin,
    int resultTimeMin,
    List<DateTime> offDays,
    bool openDayBefore,
    bool isActive,
    String currentOpenTime,
    int currentBigPlayMin,
    int currentCloseTimeMin,
    int currentResultTimeMin,
    List<DateTime> initialOffDays,
  ) async {
    try {

      if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please get a subscription to update.')),
        );
        return; // Terminate initialization if conditions are not met
      }

      final now1 = AppState().currentTime;
      // DateTime? sgUpdatedAt;
      // DateTime? pgUpdatedAt;

      if (gameInfo['is_active'] != isActive && AppState().subscription == 'super' && AppState().gameNames.length > AppState().superGames && AppState().isResetting != true) {
        // final lastUpdate = await supabase
        //     .from('khaiwals')
        //     .select('sg_updated_at')
        //     .eq('id', AppState().khaiwalId)
        //     .maybeSingle();
        //
        // sgUpdatedAt = lastUpdate?['sg_updated_at'] != null
        //     ? DateTime.parse(lastUpdate?['sg_updated_at'])
        //     : null;

        if (AppState().sgUpdatedAt != null) {
          final diff = now1.difference(AppState().sgUpdatedAt!);
          // Show dialog only if more than 48 hours have passed
          if (diff.inHours >= 48) {
            bool shouldContinue = await _showGameLimitExceededConfirmationDialog();
            if (!shouldContinue) return;
          }

        } else if (AppState().sgUpdatedAt == null) {
          bool shouldContinue = await _showGameLimitExceededConfirmationDialog();
          if (!shouldContinue) return;
        }

      } else if (gameInfo['is_active'] != isActive && AppState().subscription == 'premium' && AppState().gameNames.length > AppState().premiumGames) {
        // final lastUpdate = await supabase
        //     .from('khaiwals')
        //     .select('pg_updated_at')
        //     .eq('id', AppState().khaiwalId)
        //     .maybeSingle();
        //
        // pgUpdatedAt = lastUpdate?['pg_updated_at'] != null
        //     ? DateTime.parse(lastUpdate?['pg_updated_at'])
        //     : null;

        if (AppState().pgUpdatedAt != null) {
          final diff = now1.difference(AppState().pgUpdatedAt!);
          // Show dialog only if more than 48 hours have passed
          if (diff.inHours >= 48) {
            bool shouldContinue = await _showGameLimitExceededConfirmationDialog();
            if (!shouldContinue) return;
          }

        } else if (AppState().pgUpdatedAt == null) {
          bool shouldContinue = await _showGameLimitExceededConfirmationDialog();
          if (!shouldContinue) return;
        }

      }
      setState(() {
        loading = true;
      });

      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      final onlineNow = AppState().currentTime;
      final onlineCurrentTime = DateTime(1970, 1, 1, onlineNow.hour, onlineNow.minute +1);
      final parsedCurrentOpenTime = timeFormat.parse(currentOpenTime);
      final newCloseTime = parsedCurrentOpenTime.add(Duration(minutes: closeTimeMin));


      final now = AppState().getLiveTime();
      final currentTime = DateTime(1970, 1, 1, now.hour, now.minute);
      final currentDate = DateTime(now.year, now.month, now.day);
      final tomorrowDate = DateTime(now.year, now.month, now.day + 1);

      bool changeOpenTime = true;

      // Fetch game data for the current month
      for (var day in gameData) {
        DateTime gameDate = DateTime.parse(day['game_date']);
        // String time = day['open_time'];
        // String timeOpen = time.substring(0, time.length -3);

        if ((gameDate == currentDate) || (gameDate == tomorrowDate)){
          // DateTime parsedCurrentOpenTime = DateFormat('HH:mm').parse(currentOpenTime);

          String? currentCloseTime = _addMinutes(currentOpenTime, currentCloseTimeMin.toString());
          DateTime parsedCurrentCloseTime = timeFormat.parse(currentCloseTime!);

          // Query to check if game play exists
          final gamePlayData = await supabase
              .from('game_play')
              .select('id, is_win')
              .eq('game_id', day['id'])
              .limit(1);

          if (gamePlayData.isEmpty) continue;

          // bool gamePlayExist = gamePlayData.isNotEmpty;
          bool? isWin = gamePlayData[0]['is_win'] as bool?;
          // print('printing declared: $isWin');
          // Check for open time modification
          if ((currentOpenTime != openTime) && (currentTime.isAfter(parsedCurrentOpenTime) && currentTime.isBefore(parsedCurrentCloseTime))) {
            // print('rechanging timeOpen: $timeOpen and open time is: $openTime');
            changeOpenTime = false;

            _showDialog('Cannot Update Game Open Time', 'The game on ${DateFormat('yyyy-MM-dd').format(gameDate)} contains ongoing gameplay. You cannot update the open time for an ongoing game.');
            return;
          }
          // Check for close time modification
          if ((currentCloseTimeMin != closeTimeMin) && (newCloseTime.isBefore(onlineCurrentTime) && newCloseTime.isBefore(parsedCurrentCloseTime)) && isWin == null) {

            if (changeOpenTime) {
              _showDialog('Cannot Reduce Close Time', 'The game on ${DateFormat('yyyy-MM-dd').format(gameDate)} contains ongoing gameplay. You cannot reduce the close time for an ongoing game from current time.');
            }
            return;
          }
          // Check for day before modification
          if ((gameInfo['day_before'] != openDayBefore) && isWin == null) {

            _showDialog('Cannot Update Open A Day Before', 'The game on ${DateFormat('yyyy-MM-dd').format(gameDate)} contains ongoing gameplay. You cannot change (a day before) for an ongoing game.');

            return;
          }
          // Check for day before modification
          if ((gameInfo['is_active'] != isActive && isActive == false) && isWin == null) {

            _showDialog('Cannot Deactivate', 'The game on ${DateFormat('yyyy-MM-dd').format(gameDate)} contains ongoing gameplay. You cannot change it to inactive for an ongoing game.');

            return;
          }
        }
      }

      if (shortGameNames != shortGameName) {
        // Check for existing game with same khaiwal_id, matching short or full game name, excluding the current game by id
        final existingGame = await supabase
            .from('game_info')
            .select('id')
            .eq('khaiwal_id', AppState().khaiwalId)
            .or('short_game_name.ilike.%$shortGameNames%')
            .neq('id', widget.infoId);

        if (existingGame.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Short game name already exists'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            loading = false;
          });
          return;
        }
      }

      if (fullGameNames != gameInfo['full_game_name']) {
        // Check for existing game with same khaiwal_id, matching short or full game name, excluding the current game by id
        final existingGame = await supabase
            .from('game_info')
            .select('id')
            .eq('khaiwal_id', AppState().khaiwalId)
            .or('full_game_name.ilike.%$fullGameNames%')
            .neq('id', widget.infoId);

        if (existingGame.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Full game name already exists'),
              backgroundColor: Colors.red,
            ),
          );

          setState(() {
            loading = false;
          });
          return;
        }
      }



      if ((currentOpenTime != openTime) || (currentBigPlayMin != lastBigPlayMin) || (currentCloseTimeMin != closeTimeMin) || (currentResultTimeMin != resultTimeMin) || (gameInfo['day_before'] != openDayBefore) || shortGameNames != shortGameName || fullGameNames != gameInfo['full_game_name'] || isActive != gameInfo['is_active']) {

        if (gameInfo['is_active'] != isActive) {
          final activeGamesCount = AppState().games.where((game) => game['is_active'] == true).length;

          final now = AppState().currentTime;

          if (AppState().subscription == 'super' && activeGamesCount >= AppState().superGames && AppState().gameNames.length > AppState().superGames) {

            if (AppState().sgUpdatedAt != null) {
              final diff = now.difference(AppState().sgUpdatedAt!);

              if (diff.inHours >= 1 && diff.inHours < 48) {
                _showDialog(
                  'Cooling Period Not Over',
                  'You cannot update Activeness of this game yet. The cooling period of 2 days since the last update is not over.',
                );
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
                AppState().isResetting = true;
              }
            } else if (AppState().sgUpdatedAt == null) {
              // Update sg_updated_at with the current time
              await supabase
                  .from('khaiwals')
                  .update({'sg_updated_at': now.toIso8601String()})
                  .eq('id', AppState().khaiwalId);

              AppState().sgUpdatedAt = now;
              AppState().isResetting = true;
            }

          } else if (AppState().subscription == 'premium' && activeGamesCount >= AppState().premiumGames && AppState().gameNames.length > AppState().superGames) {

            if (AppState().pgUpdatedAt != null) {
              final diff = now.difference(AppState().pgUpdatedAt!);

              if (diff.inHours >= 1 && diff.inHours < 48) {
                _showDialog(
                  'Cooling Period Not Over',
                  'You cannot update Activeness of this game yet. The cooling period of 2 days since the last update is not over.',
                );
                setState(() {
                  loading = false;
                });
                return;
              }
              if (diff.inHours > 48) {
                // Update pg_updated_at with the current time
                await supabase
                    .from('khaiwals')
                    .update({'pg_updated_at': now.toIso8601String()})
                    .eq('id', AppState().khaiwalId);

                AppState().pgUpdatedAt = now;
                AppState().isResetting = true;
              }
            } else if (AppState().pgUpdatedAt == null) {
              // Update sg_updated_at with the current time
              await supabase
                  .from('khaiwals')
                  .update({'pg_updated_at': now.toIso8601String()})
                  .eq('id', AppState().khaiwalId);

              AppState().pgUpdatedAt = now;
              AppState().isResetting = true;
            }

          }
        }


        final response = await supabase
            .from('game_info')
            .update({
          if (currentOpenTime != openTime) 'open_time': openTime,
          if (currentBigPlayMin != lastBigPlayMin) 'big_play_min': lastBigPlayMin,
          if (currentCloseTimeMin != closeTimeMin) 'close_time_min': closeTimeMin,
          if (currentResultTimeMin != resultTimeMin) 'result_time_min': resultTimeMin,
          if (gameInfo['day_before'] != openDayBefore) 'day_before': openDayBefore,
          if (shortGameNames != shortGameName) 'short_game_name': shortGameNames,
          if (fullGameNames != gameInfo['full_game_name']) 'full_game_name': fullGameNames,
          if (gameInfo['is_active'] != isActive) 'is_active': isActive,
        }) // Update the specific field
            .eq('id', widget.infoId);

        if (response != null) {
          throw response.error!;
        }
      }

      if (shortGameNames != shortGameName) shortGameName = shortGameNames;

      if (initialOffDays.toString() != offDays.toString()) {
        // Loop through gameData and update each day by its id
        for (var day in gameData) {
          DateTime gameDate = DateTime.parse(day['game_date']);

          // Check if the current gameDate is in the offDays list
          final bool isOffDay = offDays.any((offDay) =>
          offDay.year == gameDate.year &&
              offDay.month == gameDate.month &&
              offDay.day == gameDate.day);

          // Check if the gameDate is equal to currentDate or tomorrowDate
          if ((gameDate == currentDate && isOffDay) || (gameDate == tomorrowDate && isOffDay)) {
            // Query the 'game_play' table to check if there's an existing game play
            final gamePlayData = await supabase
                .from('game_play')
                .select('id') // Only selecting the id to check if the entry exists
                .eq('game_id', day['id'])
                .limit(1);

            // If game play exists, show an alert dialog and skip updating this game
            if (gamePlayData.isNotEmpty) {
              // Show alert dialog to inform the user about refunding
              _showDialog('Cannot Update Off Day', 'The game on ${DateFormat('yyyy-MM-dd').format(gameDate)} contains gameplay of users. Please refund them before updating.');
              // Skip this game and continue with the next one
              continue;
            }
          }

          // Update the 'off_day' field for this game by its id
          await supabase
              .from('games')
              .update({'off_day': isOffDay})
              .eq('id', day['id']); // Update by id directly
        }
      }


      // Optionally reload the game data if needed after update
      await _fetchDataForSelectedMonth(currentMonth);
      await AppState().fetchGameNamesAndResults();
      await AppState().fetchGamesForCurrentDateOrTomorrow();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game updated Successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (kDebugMode) {
        print('Error updating : $error');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update game data in Supabase')),
      );
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _updateSingleDay(
      int gameId,
      // String openTime,
      // int lastBigPlayMin,
      // int closeTimeMin,
      // int resultTimeMin,
      bool offDay,
      bool pause,
      String gameDate,
      // String currentOpenTime,
      // String currentCloseTime,
      // int currentLastBigPlayMin,
      // int currentCloseTimeMin,
      // int currentResultTimeMin,
      bool currentOffDay,
      bool currentPause,
      ) async {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to update')),
      );
      return; // Terminate initialization if conditions are not met
    }

    setState(() {
      loading = true;
    });
    try {
      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch
      // bool changeOpenTime = true;
      // bool changeCloseTime = true;
      bool gamePlayExist;
      // Query the 'game_play' table to check if there's an existing gameplay
      final gamePlayData = await supabase
          .from('game_play')
          .select('id')
          .eq('game_id', gameId)
          .limit(1);
      if (gamePlayData.isNotEmpty) {
        gamePlayExist = true;
      } else {
        gamePlayExist = false;
      }

      final now = AppState().getLiveTime();
      // final currentTime = DateTime(1970, 1, 1, now.hour, now.minute);
      final currentDate = DateTime(now.year, now.month, now.day);
      final tomorrowDate = DateTime(now.year, now.month, now.day + 1);
      DateTime date = DateTime.parse(gameDate);

      // // Parse formattedOpenTime and openTime for time comparison
      // DateTime parsedCurrentOpenTime = DateFormat('HH:mm').parse(currentOpenTime);
      // DateTime parsedCurrentCloseTime = DateFormat('HH:mm').parse(currentCloseTime);
      //
      //
      // if ( ((date == currentDate) || (date == tomorrowDate)) && (currentOpenTime != openTime) && currentTime.isAfter(parsedCurrentOpenTime) && currentTime.isBefore(parsedCurrentCloseTime) && gamePlayExist) {
      //   changeOpenTime = false;
      //   _showDialog('Cannot Update Game Open Time', 'The game on ${DateFormat('yyyy-MM-dd').format(
      //       date)} contains ongoing gameplay. You cannot update the open time for an ongoing game.');
      // }
      //
      // if ( ((date == currentDate) || (date == tomorrowDate)) && (currentCloseTimeMin != closeTimeMin) && (closeTimeMin < currentCloseTimeMin) && gamePlayExist){
      //   changeCloseTime = false;
      //   if (changeOpenTime) {
      //     _showDialog('Cannot Reduce Close Time', 'The game on ${DateFormat('yyyy-MM-dd').format(
      //         date)} contains ongoing gameplay. You cannot Reduce the close time for an ongoing game.');
      //   }
      // }

      if (currentPause != pause) {
        final response = await supabase
            .from('games')
            .update({
          // if (changeOpenTime && currentOpenTime != openTime) 'open_time': openTime,
          // if (changeOpenTime && currentLastBigPlayMin != lastBigPlayMin) 'last_big_play_min': lastBigPlayMin,
          // if (changeCloseTime && currentCloseTimeMin != closeTimeMin) 'close_time_min': closeTimeMin,
          // if (changeOpenTime && currentResultTimeMin != resultTimeMin)'result_time_min': resultTimeMin,
          if (currentPause != pause) 'pause': pause,
        }) // Update the specific field
            .eq('id', gameId);

        if (response != null) {
          throw response.error!;
        }
      }

      // Check if the gameDate is equal to currentDate or tomorrowDate
      if ((date == currentDate && offDay) || (date == tomorrowDate || offDay)) {
        // print('current date or tomorrow date');
        // If game play exists, show an alert dialog and skip updating this game
        if (gamePlayExist) {
          // Show alert dialog to inform the user about refunding
          _showDialog('Cannot Update Game', 'The game on ${DateFormat('yyyy-MM-dd').format(date)} contains gameplay of users. Please refund them before updating.');
        } else {
          await supabase
              .from('games')
              .update({if (currentOffDay != offDay) 'off_day': offDay})
              .eq('id', gameId); // Update by id directly
        }
      } else {
        await supabase
            .from('games')
            .update({if (currentOffDay != offDay) 'off_day': offDay})
            .eq('id', gameId); // Update by id directly
      }


      // Optionally reload the game data if needed after update
      await _fetchDataForSelectedMonth(currentMonth);
      await AppState().fetchGameNamesAndResults();
      await AppState().fetchGamesForCurrentDateOrTomorrow();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game updated Successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (kDebugMode) {
        print('Error updating : $error');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update game data')),
      );
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<bool> _showGameLimitExceededConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Subscription Limit Reached'),
          content: const Text(
            'You have exceeded the number of games allowed in your current subscription plan. '
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



  Future<List<String>> _fetchGameMonths() async {
    try {
      final response = await supabase
          .from('games')
          .select('game_date')
          .eq('info_id', widget.infoId);

      List<dynamic> data = response as List<dynamic>;
      Set<String> months = data.map((game) {
        DateTime date = DateTime.parse(game['game_date']);
        return DateFormat.yMMM().format(date);
      }).toSet();
      return months.toList();
    } catch (error) {
      context.showSnackBar('Error fetching months', isError: true);
      return [];
    }
  }

  Future<void> _showSelectMonthDialog() async {
    List<String> months = await _fetchGameMonths();
    if (months.isEmpty) {
      context.showSnackBar('No months available', isError: true);
      return;
    }

    final selectedMonth = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Month'),
          content: SingleChildScrollView(
            child: Column(
              children: months.map((month) {
                return ListTile(
                  title: Text(month),
                  onTap: () => Navigator.of(context).pop(month),
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selectedMonth != null) {
      setState(() {
        loading = true;
      });
      currentMonth = selectedMonth;
      await _fetchDataForSelectedMonth(selectedMonth);
      setState(() {
        loading = false;
      });
      context.showSnackBar('Selected month: $selectedMonth');
    }
  }

  // Information dialog handler
  void showInfoDialog(String info) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Information'),
          content: Text(info),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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

  void _showDeleteDialog() async {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to delete')),
      );
      return; // Terminate initialization if conditions are not met
    }

    // Show confirmation dialog
    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Game'),
          content: const Text(
            'This action cannot be undone and will delete the game from all months. Do you still want to delete?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes, Delete'),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      setState(() {
        loading = true;
      });
      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch
      // Proceed with deletion if confirmed
      final deleteResponse = await supabase
          .from('game_info')
          .delete()
          .eq('id', widget.infoId);

      if (deleteResponse != null) {
        setState(() {
          loading = false;
        });
        context.showSnackBar('Failed to delete game', isError: true);
      } else {
        context.showSnackBar('Game deleted successfully');
        await AppState().fetchGameNamesAndResults();
        await AppState().fetchGamesForCurrentDateOrTomorrow();
        setState(() {
          loading = false;
        });
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }


  
  @override
  void dispose() {
    super.dispose();
  }

}
