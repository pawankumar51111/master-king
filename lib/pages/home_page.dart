import 'dart:io';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:masterking/main.dart';
import 'package:masterking/models/app_state.dart';
import 'package:masterking/pages/manage_game_page.dart';
import 'package:masterking/pages/play_page.dart';
import 'package:masterking/pages/profile_page.dart';
import 'package:masterking/pages/subscription_page.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  bool isLoading = true;
  late DateTime selectMonth;

  final List<Map<String, dynamic>> _tempGameData = [];


  @override
  void initState() {
    super.initState();
    if(!AppState().initialized){
      initializeAppState();
    } else {
      setState(() {
        selectMonth = context.read<AppState>().currentTime;
        isLoading = false;
      });
    }
  }

  Future<void> initializeAppState() async {
    await AppState().initialize();
    setState(() {
      selectMonth = context.read<AppState>().currentTime;
      isLoading = false;
    });
  }



  Future<void> _showSelectMonthDialog() async {
    if (isLoading) return;
    // Show progress indicator while the data is being fetched
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog by tapping outside
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(), // Show a circular progress indicator
        );
      },
    );
    // Fetch the map of months and associated info_ids
    Map<String, List<int>> monthsMap = await fetchUserMonths();

    Navigator.of(context).pop();

    if (monthsMap.isEmpty) {
      context.showSnackBar('No months available to show', isError: true);
      return;
    }

    // Extract the list of months (keys from the map)
    List<String> months = monthsMap.keys.toList();

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
      List<int> selectedMonthInfoIds = monthsMap[selectedMonth] ?? [];

      await _fetchDataForSelectedMonth(selectedMonthInfoIds, selectedMonth);
      context.showSnackBar('Selected month: $selectedMonth');
    }
  }
  Future<void> _fetchDataForSelectedMonth(List<int> infoIds, String selectedMonth) async {
    try {
      setState(() {
        isLoading = true;
      });

      if (AppState().user == null) return;

      final DateFormat format = DateFormat.yMMM();
      final DateTime monthDate = format.parse(selectedMonth);
      final firstDayOfMonth = DateTime.utc(monthDate.year, monthDate.month, 1);
      final lastDayOfMonth = DateTime.utc(monthDate.year, monthDate.month + 1, 0);

      // Build an OR filter string for all the infoIds
      final gameInfoFilter = infoIds.map((id) => 'id.eq.$id').join(',');
      final gamesFilter = infoIds.map((id) => 'info_id.eq.$id').join(',');

      // First query to fetch 'id' and 'short_game_name' from 'game_info'
      final gameInfoResponse = await supabase
          .from('game_info')
          .select('id, short_game_name, sequence')
          .or(gameInfoFilter);

      List<dynamic> gameInfoData = gameInfoResponse as List<dynamic>;

      if (gameInfoData.isEmpty) {
        AppState().gameNames = [];
        // AppState().games = []; because if selected month is null but don't want current days games to empty
        AppState().gameResults = {};
        AppState().notifyListeners();
        return;
      }
      // Sort gameInfoData by 'id' (infoId) to maintain sequence
      gameInfoData.sort((a, b) => a['id'].compareTo(b['id']));

      // Sort gameInfoData by 'sequence', handling null values by assigning them the lowest priority
      gameInfoData.sort((a, b) {
        final sequenceA = a['sequence'] ?? double.infinity; // Null goes to the end
        final sequenceB = b['sequence'] ?? double.infinity;
        return sequenceA.compareTo(sequenceB);
      });

      final response = await supabase
          .from('games')
          .select('id, info_id, game_date, game_result, off_day')
          .or(gamesFilter)
          .gte('game_date', firstDayOfMonth.toIso8601String())
          .lte('game_date', lastDayOfMonth.toIso8601String());

      if (response.isEmpty) {
        AppState().gameNames = [];
        AppState().gameResults = {};
        AppState().notifyListeners();
        return;
      }

      List<dynamic> gamesData = response as List<dynamic>;
      if (gamesData.isEmpty) {
        AppState().notifyListeners(); // Notify listeners when no data is found
        return;
      }

      // Sort the games data by 'game_date' before processing it
      gamesData.sort((a, b) {
        DateTime gameDateA = DateTime.parse(a['game_date']);
        DateTime gameDateB = DateTime.parse(b['game_date']);
        return gameDateA.compareTo(gameDateB); // Ascending order
      });

      Map<String, List<Map<String, dynamic>>> results = {};
      List<String> newGameNames = [];

      for (var info in gameInfoData) {
        final infoId = info['id'];
        final shortGameName = info['short_game_name'];

        if (!results.containsKey(shortGameName)) {
          results[shortGameName] = [];
        }

        for (var game in gamesData) {
          if (game['info_id'] == infoId) {
            results[shortGameName]?.add(game as Map<String, dynamic>);
          }
        }

        // Add game names in the sorted sequence of infoId
        newGameNames.add(shortGameName);
      }

      setState(() {
        AppState().gameNames = newGameNames;
        AppState().gameResults = results;
        selectMonth = monthDate;
      });

      setState(() {
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
      });
      context.showSnackBar('Error fetching data for selected month', isError: true);
    }
  }


  // Future<void> _showSelectMonthDialogForDuplicate() async {
  //   // Fetch the map of months and associated info_ids
  //   Map<String, List<int>> monthsMap = await fetchUserMonths();
  //
  //   if (monthsMap.isEmpty) {
  //     context.showSnackBar('No months available to extend', isError: true);
  //     return;
  //   }
  //
  //   // Extract the list of months (keys from the map)
  //   List<String> months = monthsMap.keys.toList();
  //
  //   final selectedMonth = await showDialog<String>(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return AlertDialog(
  //         title: const Text('Select Month'),
  //         content: SingleChildScrollView(
  //           child: Column(
  //             children: months.map((month) {
  //               return ListTile(
  //                 title: Text(month),
  //                 onTap: () => Navigator.of(context).pop(month),
  //               );
  //             }).toList(),
  //           ),
  //         ),
  //         actions: <Widget>[
  //           TextButton(
  //             onPressed: () => Navigator.of(context).pop(),
  //             child: const Text('Cancel'),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  //
  //   // If a month is selected, get the corresponding info_ids and pass them to _handleDataDuplication
  //   if (selectedMonth != null) {
  //     List<int> selectedMonthInfoIds = monthsMap[selectedMonth] ?? [];
  //     // Build an OR filter string for all the infoIds
  //     final orFilter = selectedMonthInfoIds.map((id) => 'info_id.eq.$id').join(',');
  //
  //     await _handleDataDuplication(orFilter,selectedMonth);
  //     context.showSnackBar('Selected month: $selectedMonth');
  //   }
  // }

  Future<void> _showSelectMonthDialogForDuplicate() async {
    if (isLoading) return;

    if (AppState().subscription != 'super' && AppState().subscription != 'premium'){
      context.showSnackBar('Get a subscription to extend chart');
      return;
    }
    // Show progress indicator while the data is being fetched
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog by tapping outside
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(), // Show a circular progress indicator
        );
      },
    );
    // Fetch the map of months and associated info_ids
    Map<String, List<int>> monthsMap = await fetchUserMonths();

    Navigator.of(context).pop();

    if (monthsMap.isEmpty) {
      context.showSnackBar('No months available to extend', isError: true);
      return;
    }

    // Extract the list of months (keys from the map)
    List<String> months = monthsMap.keys.toList();
    final now = AppState().currentTime; // Assuming you have access to the current time here
    final lastDayOfMonth = DateTime.utc(now.year, now.month + 1, 0);
    final currentMonth = DateFormat.yMMM().format(now); // Format the current month to match the selected months

    final selectedMonth = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Month To Extend'),
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

    // If a month is selected, get the corresponding info_ids and pass them to _handleDataDuplication
    if (selectedMonth != null) {
      List<int> selectedMonthInfoIds = monthsMap[selectedMonth] ?? [];
      // Build an OR filter string for all the infoIds
      final orFilter = selectedMonthInfoIds.map((id) => 'info_id.eq.$id').join(',');

      if (selectedMonth == currentMonth) {
        // Case 1: Selected month is the current month
        final confirmed = await _showConfirmationDialog('Do you want to extend current month (${_getMonthName(now)}) games to next month?');
        if (confirmed) {
          await _duplicateMonthData(orFilter, selectedMonth, now.month + 1);
        }
      } else {
        // Parse both selectedMonth and currentMonth for year and month comparison
        final selectedDate = DateFormat.yMMM().parse(selectedMonth);
        final currentDate = DateFormat.yMMM().parse(currentMonth);

        final monthDifference = (currentDate.year * 12 + currentDate.month) - (selectedDate.year * 12 + selectedDate.month);

        if (monthDifference == 1) {
          // First, query to find the maximum available game_date for the given info_id
          final maxDateResponse = await supabase
              .from('games')
              .select('game_date')
              .or(orFilter)
              .order('game_date', ascending: false)
              .limit(1);

          if (maxDateResponse.isEmpty) {
            context.showSnackBar('No games found for the selected month', isError: true);
            return;
          }
          DateTime maxGameDate = DateTime.parse(maxDateResponse[0]['game_date']);
          // Case 2: Selected month is the previous month
          final confirmed = await _showConfirmationDialog(
              maxGameDate.isAfter(lastDayOfMonth)
                  ? 'Do you want to copy $selectedMonth games to this month (${_getMonthName(now)}) and later months?'
                  : 'Do you want to copy $selectedMonth games to this month (${_getMonthName(now)})?'
          );
          if (confirmed) {
            await _duplicateMonthData(orFilter, selectedMonth, now.month);
            if (maxGameDate.isAfter(lastDayOfMonth)) {
              await _duplicateMonthData(orFilter, selectedMonth, now.month + 1);
            }
          }

          // // Case 2: Selected month is the previous month
          // final extendTo = await _showExtendOptionsDialog('Do you want to extend ($selectedMonth) games to:', ['Current Month', 'Next Month']);
          // if (extendTo == 'Current Month') {
          //   await _duplicateMonthData(orFilter, selectedMonth, now.month);
          // } else if (extendTo == 'Next Month') {
          //   await _duplicateMonthData(orFilter, selectedMonth, now.month + 1);
          // }
        } else if (monthDifference < 0) {
          // Case 3: Selected month is next or later
          _showAlertDialog('Next month\'s games ($selectedMonth) can\'t be extended until it becomes the current month.');
        }
      }

    }
  }
  Future<void> _duplicateMonthData(String orFilter, String selectedMonth, int targetMonth) async {
    try {
      setState(() {
        isLoading = true;
      });
      _tempGameData.clear();

      final DateFormat format = DateFormat.yMMM();
      final DateTime selectedDate = format.parse(selectedMonth);
      final firstDayOfSelectedMonth = DateTime.utc(selectedDate.year, selectedDate.month, 1);
      final lastDayOfSelectedMonth = DateTime.utc(selectedDate.year, selectedDate.month + 1, 0);

      final now = AppState().currentTime;
      final targetYear = (targetMonth < now.month) ? now.year + 1 : now.year;
      final daysInTargetMonth = DateTime.utc(targetYear, targetMonth + 1, 0).day;

      final firstDayOfTargetMonth = DateTime.utc(targetYear, targetMonth, 1);

      // Check if data exists for the first day of the target month with orFilter
      final existingData = await supabase
          .from('games')
          .select('id')
          .or(orFilter)
          .eq('game_date', firstDayOfTargetMonth.toIso8601String())
          .limit(1);

      if (existingData.isNotEmpty) {
        context.showSnackBar('Game already exists in the next month');
        setState(() {
          isLoading = false;
        });
        return;
      }

      final selectedMonthGames = await supabase
          .from('games')
          .select('info_id, game_date, off_day')
          .or(orFilter)
          .gte('game_date', firstDayOfSelectedMonth.toIso8601String())
          .lte('game_date', lastDayOfSelectedMonth.toIso8601String());

      if (selectedMonthGames.isEmpty) {
        context.showSnackBar('No games found for the selected month', isError: true);
        setState(() {
          isLoading = false;
        });
        return;
      }

      // Sort the games by 'game_date' in ascending order
      selectedMonthGames.sort((a, b) {
        final DateTime gameDateA = DateTime.parse(a['game_date']);
        final DateTime gameDateB = DateTime.parse(b['game_date']);
        return gameDateA.compareTo(gameDateB); // Ascending order
      });

      for (var game in selectedMonthGames) {
        final gameDate = DateTime.parse(game['game_date']);
        final day = gameDate.day;
        final targetDate = DateTime.utc(targetYear, targetMonth, day <= daysInTargetMonth ? day : daysInTargetMonth);

        await _addGame2(
          game['info_id'],
          targetDate,
          game['off_day'],
        );
      }

      // Handle extra days if target month has more days than selected month
      if (daysInTargetMonth > lastDayOfSelectedMonth.day) {
        final extraDay = lastDayOfSelectedMonth.day;
        final extraDayGames = selectedMonthGames.where((game) => DateTime.parse(game['game_date']).day == extraDay).toList();
        for (int day = extraDay + 1; day <= daysInTargetMonth; day++) {
          final extraDayDate = DateTime.utc(targetYear, targetMonth, day);
          for (var extraDayGame in extraDayGames) {
            await _addGame2(
              extraDayGame['info_id'],
              extraDayDate,
              extraDayGame['off_day'],
            );
          }
        }
      }

      // Filter and sort games from the 25th onward in descending order
      final filteredGamesFrom24 = selectedMonthGames
          .where((game) => DateTime.parse(game['game_date']).day >= 24)
          .toList();

      filteredGamesFrom24.sort((a, b) {
        final DateTime gameDateA = DateTime.parse(a['game_date']);
        final DateTime gameDateB = DateTime.parse(b['game_date']);
        return gameDateB.compareTo(gameDateA); // Descending order
      });

      // Pass filtered and sorted games to copyLastFourGamesExcludingDate
      await copyLastFourGamesExcludingDate(filteredGamesFrom24, DateTime.utc(targetYear, targetMonth, 1));

      // Now copy the last 4 games excluding the date
      // await copyLastFourGamesExcludingDate(orFilter, selectedDate, DateTime.utc(targetYear, targetMonth, 1));

      await AppState().fetchGameNamesAndResults();
      await AppState().fetchGamesForCurrentDateOrTomorrow();

      context.showSnackBar('Chart extended for ${targetMonth == now.month ? 'current month' : 'next month'}!');
      setState(() {
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
      });
      context.showSnackBar('Unexpected error occurred', isError: true);
    }
  }

  Future<void> copyLastFourGamesExcludingDate(List<Map<String, dynamic>> filteredGamesFrom24, DateTime targetMonthDate) async {
    try {
      if (filteredGamesFrom24.isEmpty) {
        context.showSnackBar('No games found for the selected month', isError: true);
        return;
      }

      // Group games by short_game_name
      final Map<int, List<Map<String, dynamic>>> groupedSelectedGames = {};
      for (var game in filteredGamesFrom24) {
        final infoId = game['info_id'];
        if (!groupedSelectedGames.containsKey(infoId)) {
          groupedSelectedGames[infoId] = [];
        }
        groupedSelectedGames[infoId]!.add(game);
      }

      // Filter and sort _tempGameData for games in the target month on or after the 25th
      final filteredTempGameData = _tempGameData.where((game) {
        final gameDate = DateTime.parse(game['game_date']);
        return gameDate.month == targetMonthDate.month &&
            gameDate.year == targetMonthDate.year &&
            gameDate.day >= 24;
      }).toList();

      filteredTempGameData.sort((a, b) {
        final DateTime gameDateA = DateTime.parse(a['game_date']);
        final DateTime gameDateB = DateTime.parse(b['game_date']);
        return gameDateB.compareTo(gameDateA); // Descending order
      });

      // Group filtered games by 'info_id'
      final Map<int, List<Map<String, dynamic>>> groupedTargetGames = {};
      for (var game in filteredTempGameData) {
        final infoId = game['info_id'];
        if (!groupedTargetGames.containsKey(infoId)) {
          groupedTargetGames[infoId] = [];
        }
        groupedTargetGames[infoId]!.add(game);
      }

      // Copy the data for each group
      for (var infoId in groupedSelectedGames.keys) {
        final selectedGames = groupedSelectedGames[infoId]!;
        final targetGames = groupedTargetGames[infoId] ?? [];

        for (int i = 0; i < 5 && i < targetGames.length && i < selectedGames.length; i++) {
          final selectedGame = selectedGames[i];
          final targetGame = targetGames[i];

          // Find the corresponding game in _tempGameData
          final existingGameIndex = _tempGameData.indexWhere((game) =>
          game['game_date'] == targetGame['game_date'] && game['info_id'] == targetGame['info_id']);
          if (existingGameIndex != -1) {
            _tempGameData[existingGameIndex]['info_id'] = selectedGame['info_id'];
            _tempGameData[existingGameIndex]['off_day'] = selectedGame['off_day'];
            // Add other fields to copy here, excluding 'game_date'
          }

        }
      }

      // Sort _tempGameData by info_id and then game_date (ascending order)
      _tempGameData.sort((a, b) {
        final int infoIdA = a['info_id'];
        final int infoIdB = b['info_id'];
        if (infoIdA == infoIdB) {
          final DateTime gameDateA = DateTime.parse(a['game_date']);
          final DateTime gameDateB = DateTime.parse(b['game_date']);
          return gameDateA.compareTo(gameDateB); // Sort by date if info_id is equal
        }
        return infoIdA.compareTo(infoIdB); // Sort by info_id
      });

      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      await _insertAllGames();

    } catch (error) {
      if (kDebugMode) {
        print('Error: $error');
      }
      context.showSnackBar('Unexpected error occurred: $error', isError: true);
    }
  }

  // Future<void> copyLastFourGamesExcludingDate(String orFilter, DateTime selectedMonthDate, DateTime targetMonthDate) async {
  //   try {
  //     // Fetch the games from the selected month
  //     final selectedMonthGames = await supabase
  //         .from('games')
  //         .select('id, info_id, off_day')
  //         .or(orFilter)
  //         .gte('game_date', DateTime.utc(selectedMonthDate.year, selectedMonthDate.month, 25).toIso8601String())
  //         .lte('game_date', DateTime.utc(selectedMonthDate.year, selectedMonthDate.month + 1, 0).toIso8601String())
  //         .order('game_date', ascending: false);
  //
  //     if (selectedMonthGames.isEmpty) {
  //       context.showSnackBar('No games found for the selected month', isError: true);
  //       return;
  //     }
  //
  //     // Group games by short_game_name
  //     final Map<int, List<Map<String, dynamic>>> groupedGames = {};
  //     for (var game in selectedMonthGames) {
  //       final infoId = game['info_id'];
  //       if (!groupedGames.containsKey(infoId)) {
  //         groupedGames[infoId] = [];
  //       }
  //       groupedGames[infoId]!.add(game);
  //     }
  //
  //     // Fetch the games from the target month
  //     final targetMonthGames = await supabase
  //         .from('games')
  //         .select('id, info_id, game_date, off_day')
  //         .or(orFilter)
  //         .gte('game_date', DateTime.utc(targetMonthDate.year, targetMonthDate.month, 25).toIso8601String())
  //         .lte('game_date', DateTime.utc(targetMonthDate.year, targetMonthDate.month + 1, 0).toIso8601String())
  //         .order('game_date', ascending: false);
  //
  //     if (targetMonthGames.isEmpty) {
  //       context.showSnackBar('No games found for the target month', isError: true);
  //       return;
  //     }
  //
  //     // Group target month games by short_game_name
  //     final Map<int, List<Map<String, dynamic>>> groupedTargetGames = {};
  //     for (var game in targetMonthGames) {
  //       final infoId = game['info_id'];
  //       if (!groupedTargetGames.containsKey(infoId)) {
  //         groupedTargetGames[infoId] = [];
  //       }
  //       groupedTargetGames[infoId]!.add(game);
  //     }
  //
  //     // Copy the data for each group
  //     for (var infoId in groupedGames.keys) {
  //       final selectedGames = groupedGames[infoId]!;
  //       final targetGames = groupedTargetGames[infoId] ?? [];
  //
  //       for (int i = 0; i < 4 && i < targetGames.length && i < selectedGames.length; i++) {
  //         final selectedGame = selectedGames[i];
  //         final targetGame = targetGames[i];
  //
  //         // Create a map to hold the updated fields
  //         final updatedFields = <String, dynamic>{
  //           'info_id': selectedGame['info_id'],
  //           'off_day': selectedGame['off_day'],
  //           // Add other fields to copy here, excluding 'game_date'
  //         };
  //
  //         await supabase
  //             .from('games')
  //             .update(updatedFields)
  //             .eq('game_date', targetGame['game_date'])
  //             .eq('info_id', targetGame['info_id']);
  //       }
  //     }
  //
  //     // context.showSnackBar('Last 4 games copied successfully for each short_game_name!');
  //   } catch (error) {
  //     print('Error: $error');
  //     context.showSnackBar('Unexpected error occurred: $error', isError: true);
  //   }
  // }

  Future<bool> _showConfirmationDialog(String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmation'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    ) ?? false; // Keep this to handle null response
  }

  Future<bool> _showGameConfirmationDialog(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Proceed')),
          ],
        );
      },
    ) ?? false;
  }


  Future<String?> _showExtendOptionsDialog(String message, List<String> options) async {
    return await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choose an Option'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message), // Display the message here
                const SizedBox(height: 16), // Add some spacing
                ...options.map((option) {
                  return ListTile(
                    title: Text(option),
                    onTap: () => Navigator.of(context).pop(option),
                  );
                }),
              ],
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
  }




  Future<Map<String, List<int>>> fetchUserMonths() async {
    try {
      // First query to fetch 'id' from 'game_info'
      final gameInfoResponse = await supabase
          .from('game_info')
          .select('id')
          .eq('khaiwal_id', AppState().khaiwalId);

      if (gameInfoResponse.isEmpty) {
        // context.showSnackBar('Error fetching months', isError: true);
        return {};
      }

      // Collect all info_ids to query games table
      List<int> infoIds = gameInfoResponse.map((info) => info['id'] as int).toList();

      // Build an OR filter string for all the infoIds
      final orFilter = infoIds.map((id) => 'info_id.eq.$id').join(',');

      // Fetch game dates and info_ids
      final response = await supabase
          .from('games')
          .select('info_id, game_date')
          .or(orFilter);

      List<dynamic> data = response as List<dynamic>;

      // Sort the games data by 'game_date' before processing it
      data.sort((a, b) {
        DateTime gameDateA = DateTime.parse(a['game_date']);
        DateTime gameDateB = DateTime.parse(b['game_date']);
        return gameDateA.compareTo(gameDateB); // Ascending order
      });

      // Create a map of months and the corresponding list of info_ids
      Map<String, List<int>> monthToInfoIdsMap = {};

      for (var game in data) {
        DateTime date = DateTime.parse(game['game_date']);
        String month = DateFormat.yMMM().format(date);  // Format date to "Oct 2024"
        int infoId = game['info_id'];

        // Add the info_id to the correct month
        if (monthToInfoIdsMap.containsKey(month)) {
          monthToInfoIdsMap[month]!.add(infoId);
        } else {
          monthToInfoIdsMap[month] = [infoId];
        }
      }

      return monthToInfoIdsMap;
    } catch (error) {
      context.showSnackBar('Error fetching months', isError: true);
      return {};
    }
  }

  // Future<void> _duplicateCurrentMonthData() async {
  //   try {
  //     // final user = supabase.auth.currentUser;
  //     if (user == null) return;
  //
  //     final now = DateTime.now();
  //     final firstDayOfCurrentMonth = DateTime(now.year, now.month, 1);
  //     final lastDayOfCurrentMonth = DateTime(now.year, now.month + 1, 0);
  //
  //     final currentMonthGames = await supabase
  //         .from('games')
  //         .select()
  //         .eq('khaiwal_id', currentUserProfileId)
  //         .gte('game_date', firstDayOfCurrentMonth.toIso8601String())
  //         .lte('game_date', lastDayOfCurrentMonth.toIso8601String());
  //
  //     if (currentMonthGames == null || currentMonthGames.isEmpty) {
  //       context.showSnackBar('No games found for the current month', isError: true);
  //       return;
  //     }
  //
  //     final daysInNextMonth = DateTime(now.year, now.month + 2, 0).day;
  //
  //     for (var game in currentMonthGames) {
  //       final gameDate = DateTime.parse(game['game_date']);
  //       final day = gameDate.day;
  //       final nextMonthDate = DateTime(now.year, now.month + 1, day <= daysInNextMonth ? day : daysInNextMonth);
  //
  //       await _addGame(
  //         currentUserProfileId,
  //         game['full_game_name'],
  //         game['short_game_name'],
  //         nextMonthDate,
  //         game['open_time'],
  //         game['last_big_play_time'],
  //         game['close_time'],
  //         game['result_time'],
  //       );
  //     }
  //
  //     context.showSnackBar('Games duplicated for next month!');
  //   } catch (error) {
  //     context.showSnackBar('Unexpected error occurred', isError: true);
  //   }
  // }
  //
  // Future<void> _handleDataDuplication(String orFilter, String selectedMonth) async {
  //   try {
  //     if (AppState().user == null) return;
  //
  //     final now = AppState().currentTime;//globalDateTime ??
  //     final firstDayOfCurrentMonth = DateTime.utc(now.year, now.month, 1);
  //     final lastDayOfCurrentMonth = DateTime.utc(now.year, now.month + 1, 0);
  //
  //     // Query to check if there's data for both the first and last day of the current month
  //     final currentMonthGames = await supabase
  //         .from('games')
  //         .select('id')
  //         .or(orFilter)
  //         .or('game_date.eq.${firstDayOfCurrentMonth.toIso8601String()},game_date.eq.${lastDayOfCurrentMonth.toIso8601String()}');
  //
  //     if (currentMonthGames.isEmpty) {
  //       // If current month has no data, duplicate selected month's data to current month
  //       await _duplicateMonthData(orFilter, selectedMonth, now.month);
  //     } else {
  //       // Check if there is data for next month (now.month + 1)
  //       // final nextMonth = now.month + 1;
  //       // final firstDayOfNextMonth = DateTime.utc(now.year, nextMonth, 1);
  //       // final lastDayOfNextMonth = DateTime.utc(now.year, nextMonth + 1, 0);
  //       // // Query to check if there's data for the next month
  //       // final nextMonthGames = await supabase
  //       //     .from('games')
  //       //     .select('id')
  //       //     .or(orFilter)
  //       //     .or('game_date.eq.${firstDayOfNextMonth.toIso8601String()},game_date.eq.${lastDayOfNextMonth.toIso8601String()}');
  //       //
  //       // if (nextMonthGames.isNotEmpty) {
  //       //   // Show message if data exists for next month
  //       //   context.showSnackBar('Game chart already exists for next month');
  //       //   return;
  //       // } else {
  //       //   // Duplicate selected month data to next month
  //       //   await _duplicateMonthData(orFilter, selectedMonth, nextMonth);
  //       // }
  //       await _duplicateMonthData(orFilter, selectedMonth, now.month+1);
  //
  //     }
  //   } catch (error) {
  //     context.showSnackBar('Unexpected error occurred', isError: true);
  //   }
  // }


  // void _handleMenuItemClick(String value) async {
  //   switch (value) {
  //     case 'Change Month':
  //       _showSelectMonthDialog();
  //       break;
  //
  //     case 'Add Game':
  //       final now = AppState().currentTime;
  //       final isCurrentMonth = selectMonth.year == now.year && selectMonth.month == now.month;
  //       final isFutureMonth = selectMonth.isAfter(DateTime(now.year, now.month, 1));
  //       final isPastMonth = selectMonth.isBefore(DateTime(now.year, now.month, 1));
  //
  //       if (isCurrentMonth) {
  //         _showAddGameDialog();
  //
  //       } else if (isFutureMonth) {
  //         // Show error dialog for trying to add a game in a past month
  //         _showAlertDialog('New games can only be added in the current month & auto extended to next months');
  //       } else if (isPastMonth) {
  //         // Show error dialog for trying to add a game in a past month
  //         _showAlertDialog('New games can only be added in the current month.');
  //       }
  //       break;
  //
  //     case 'Manage Game':
  //       _showSelectGameDialog();
  //       break;
  //
  //     case 'Extend Chart':
  //       _showSelectMonthDialogForDuplicate();
  //       break;
  //
  //     case 'Delete Chart':
  //     // Handle Delete Chart action here
  //       _handleDeleteChart();
  //       break;
  //
  //     case 'Get Premium':
  //     // Handle Get Premium action here
  //       break;
  //
  //     case 'Sign Out':
  //       _showSignOutDialog();
  //       break;
  //   }
  // }

  Future<void> _showAlertDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Notice'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _getMonthName(DateTime date) {
    return ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][date.month - 1];
  }


  // Future<void> _showCreateChartDialog() async {
  //   showDialog<void>(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return AlertDialog(
  //         title: const Text('No Data for Current Month'),
  //         content: const Text('There is no data for the current month. Would you like to create a chart?'),
  //         actions: <Widget>[
  //           TextButton(
  //             onPressed: () => Navigator.of(context).pop(),
  //             child: const Text('Cancel'),
  //           ),
  //           TextButton(
  //             onPressed: () {
  //               Navigator.of(context).pop();
  //               _showAddGameDialog();
  //             },
  //             child: const Text('Create'),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }

  Future<void> _showAddGameDialog() async {
    if (isLoading) return;
    TextEditingController fullGameNameController = TextEditingController();
    TextEditingController shortGameNameController = TextEditingController();
    TextEditingController openTimeController = TextEditingController();
    TextEditingController lastBigPlayTimeController = TextEditingController();
    TextEditingController closeTimeController = TextEditingController();
    TextEditingController resultTimeController = TextEditingController();

    List<DateTime> offDays = [];
    // DateTime selectedDay = AppState().currentTime;

    bool openDayBefore = false; // Track switch value for 'Open a day before'
    bool isActive = true; // Track switch value for 'Activate'


    final DateFormat timeFormat = DateFormat('HH:mm');

    Future<void> selectTime(BuildContext context, TextEditingController controller) async {
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (picked != null) {
        final time = DateTime(0, 0, 0, picked.hour, picked.minute);
        controller.text = timeFormat.format(time);
      }
    }

    void clearTime(TextEditingController controller) {
      controller.clear();
    }

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
                      DateTime.utc(selectMonth.year, selectMonth.month + 1, 0).day,
                          (index) {
                        DateTime day = DateTime.utc(selectMonth.year, selectMonth.month, index + 1);
                        return CheckboxListTile(
                          title: Text(DateFormat('EEEE, dd MMMM').format(day)), // Display day and date
                          value: offDays.contains(day),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                offDays.add(day);
                              } else {
                                offDays.remove(day);
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
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          );
        },
      );
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


    final shouldAddGame = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Add Game'),
              content: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
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
                          onPressed: () => selectTime(context, lastBigPlayTimeController),
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
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    // Validate Full Game Name and Short Game Name
                    if (fullGameNameController.text.isEmpty || shortGameNameController.text.isEmpty) {
                      context.showSnackBar('Full Game Name and Short Game Name are mandatory', isError: true);
                      return;
                    }
                    // Parse openTime and closeTime
                    if (openTimeController.text.isEmpty || closeTimeController.text.isEmpty) {
                      context.showSnackBar('Open Time and Close Time are mandatory', isError: true);
                      return;
                    }

                    final DateTime openTime = timeFormat.parse(openTimeController.text);
                    final DateTime closeTime = timeFormat.parse(closeTimeController.text);
                    // Check if open time and close time are the same
                    if (openTime.isAtSameMomentAs(closeTime)) {
                      context.showSnackBar('Open Time and Close Time cannot be the same', isError: true);
                      return;
                    }

                    // Check if Last Big Play Time is filled and within range
                    if (lastBigPlayTimeController.text.isNotEmpty) {
                      final DateTime lastBigPlayTime = timeFormat.parse(lastBigPlayTimeController.text);
                      if (lastBigPlayTime.isAfter(closeTime)) {
                        context.showSnackBar('Last Big Play Time must be before Close Time', isError: true);
                        return;
                      }
                    }

                    // Validate Result Time (if filled)
                    if (resultTimeController.text.isNotEmpty) {
                      final DateTime resultTime = timeFormat.parse(resultTimeController.text);
                      if (!resultTime.isAfter(closeTime)) {
                        context.showSnackBar('Result Time must be after Close Time', isError: true);
                        return;
                      }
                    }

                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldAddGame == true) {
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

      await _addGamesForMonth(
        fullGameNameController.text.trim(),
        shortGameNameController.text.trim(),
        openTimeController.text,
        lastBigPlayMin,
        closeTimeMin,
        resultTimeMin,
        offDays,
        openDayBefore,
        isActive,
      );
    }
  }

  // Future<void> _addGamesForCurrentMonth(
  //     String fullGameName,
  //     String shortGameName,
  //     String openTime,
  //     int lastBigPlayMin,
  //     int closeTimeMin,
  //     int resultTimeMin,
  //     List<DateTime> offDays,
  //     bool openDayBefore,
  //     bool isActive,
  //     ) async {
  //   try {
  //     // final user = supabase.auth.currentUser;
  //     if (AppState().user != null) {
  //       // Get days of the current month
  //       final now = AppState().currentTime;//globalDateTime!;
  //       final daysInMonth = DateTime.utc(now.year, now.month + 1, 0).day;
  //
  //       // Iterate over each day and add a game
  //       for (int day = 1; day <= daysInMonth; day++) {
  //         final gameDate = DateTime.utc(now.year, now.month, day);
  //
  //         final bool isOffDay = offDays.any((offDay) =>
  //         offDay.year == gameDate.year &&
  //             offDay.month == gameDate.month &&
  //             offDay.day == gameDate.day);
  //
  //         await _addGame(
  //           AppState().khaiwalId,
  //           fullGameName,
  //           shortGameName,
  //           gameDate,
  //           openTime,
  //           lastBigPlayMin,
  //           closeTimeMin,
  //           resultTimeMin,
  //           isOffDay,
  //           openDayBefore,
  //           isActive,
  //         );
  //       }
  //
  //       context.showSnackBar('Games added for current month!');
  //       await AppState().fetchGameNamesAndResults();
  //       await AppState().fetchGamesForCurrentDateOrTomorrow();
  //
  //     }
  //   } catch (error) {
  //     context.showSnackBar('Unexpected error occurred', isError: true);
  //   }
  // }

  Future<void> _addGamesForMonth(
      String fullGameName,
      String shortGameName,
      String openTime,
      int lastBigPlayMin,
      int closeTimeMin,
      int resultTimeMin,
      List<DateTime> offDays,
      bool openDayBefore,
      bool isActive,
      ) async {
    try {

      if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please get a subscription.')),
        );
        return; // Terminate initialization if conditions are not met
      }

      setState(() {
        isLoading = true;
      });
      // Get the first and last day of the current month
      final now = AppState().currentTime;
      final firstDayOfMonth = DateTime.utc(now.year, now.month, 1);
      final lastDayOfMonth = DateTime.utc(now.year, now.month + 1, 0);
      final khaiwalId = AppState().khaiwalId;

      final infoResponse = await supabase
          .from('game_info')
          .select('id')
          .eq('khaiwal_id', khaiwalId);

      if (AppState().subscription == 'super' && infoResponse.length >= AppState().superGames) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please upgrade to higher plan to add more games.')),
        );
        setState(() {
          isLoading = false;
        });
        return;
      } else if (AppState().subscription == 'premium' && infoResponse.length >= AppState().premiumGames) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You have reached the limit of ${AppState().premiumGames}')),
        );
        setState(() {
          isLoading = false;
        });
        return;
      } else if (AppState().subscription.isNotEmpty && AppState().subscription != 'super' && AppState().subscription != 'premium') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unrecognised subscription')),
        );
        setState(() {
          isLoading = false;
        });
        return;
      }

      // Check for existing game with same profile_id, game_date, and either short_game_name or full_game_name
      final existingGame = await supabase
          .from('game_info')
          .select('id')
          .eq('khaiwal_id', khaiwalId)
          .or('short_game_name.ilike.%$shortGameName%,full_game_name.ilike.%$fullGameName%');

      if (existingGame.isNotEmpty) {
        final maxDateResponse = await supabase
            .from('games')
            .select('game_date')
            .eq('info_id', existingGame[0]['id'])
            .order('game_date', ascending: false)
            .limit(1);
          DateTime maxGameDate = DateTime.parse(maxDateResponse[0]['game_date']);

        if (maxGameDate.isAfter(firstDayOfMonth)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Game name is already exist')),
          );
          setState(() {
            isLoading = false;
          });
          return;
        } else if (maxGameDate.isBefore(firstDayOfMonth)) {
          final confirmed = await _showConfirmationDialog('Game with same name already exist in previous month. Do you want to extend that game in the current month?');
          if (confirmed) {
            await _duplicateMonthData('info_id.eq.${existingGame[0]['id']}', DateFormat.yMMM().format(maxGameDate), now.month);
          }
          setState(() {
            isLoading = false;
          });
          return;
        }
      }

      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      // Insert a new game into the game_info table
      final response = await supabase.from('game_info').insert({
        'khaiwal_id': AppState().khaiwalId,
        'full_game_name': fullGameName,
        'short_game_name': shortGameName,
        'open_time': openTime,
        'big_play_min': lastBigPlayMin,
        'close_time_min': closeTimeMin,
        'result_time_min': resultTimeMin,
        'day_before': openDayBefore,
        'is_active': isActive,
      }).select('id');

      final infoId = response[0]['id']; // Get the id of the newly created row in game_info table

      // Prepare a list of rows for batch insertion into `games` table
      final List<Map<String, dynamic>> gameRows = [];

      // Loop through each day of the month
      for (var date = firstDayOfMonth; date.isBefore(lastDayOfMonth.add(const Duration(days: 1))); date = date.add(const Duration(days: 1))) {
        final isOffDay = offDays.contains(date);

        gameRows.add({
          'info_id': infoId,
          'game_date': date.toIso8601String(),
          'off_day': isOffDay,
        });
        // Insert into the games table
        // await supabase.from('games').insert({
        //   'info_id': infoId,
        //   'game_date': date.toIso8601String(),
        //   'off_day': isOffDay,
        // });
      }
      // Batch insert into `games` table
      if (gameRows.isNotEmpty) {
        await supabase.from('games').insert(gameRows);
      }

      // First query to fetch 'id' from 'game_info'
      final gameInfoResponse = await supabase
          .from('game_info')
          .select('id')
          .eq('khaiwal_id', AppState().khaiwalId);

      if (gameInfoResponse.isNotEmpty) {
        // Collect all info_ids to query games table
        List<int> infoIds = gameInfoResponse.map((info) => info['id'] as int).toList();
        // Build an OR filter string for all the infoIds
        final orFilter = infoIds.map((id) => 'info_id.eq.$id').join(',');
        // First, query to find the maximum available game_date for the given info_id
        final maxDateResponse = await supabase
            .from('games')
            .select('game_date')
            .or(orFilter)
            .order('game_date', ascending: false)
            .limit(1);

        if (maxDateResponse.isNotEmpty) {
          DateTime maxGameDate = DateTime.parse(maxDateResponse[0]['game_date']);

          if (maxGameDate.isAfter(lastDayOfMonth)) {
            await _duplicateMonthData('info_id.eq.$infoId', DateFormat.yMMM().format(now), now.month + 1);
          }
        }
      }

      context.showSnackBar('Game added in month: ${DateFormat.yMMM().format(selectMonth)}');
      await AppState().fetchGameNamesAndResults();
      await AppState().fetchGamesForCurrentDateOrTomorrow();

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (kDebugMode) {
        print('Error adding games for current month: $e');
      }
    }
  }



  Future<void> _addGame(
      int infoId,
      DateTime gameDate,
      bool isOffDay,
      ) async {
    try {
      // Check for existing game with same profile_id, game_date, and either short_game_name or full_game_name
      final existingGame = await supabase
          .from('games')
          .select('id')
          .eq('info_id', infoId)
          .eq('game_date', gameDate.toIso8601String());
          // .or('short_game_name.ilike.%$shortGameName%,full_game_name.ilike.%$fullGameName%');

      if (existingGame.isNotEmpty) {
        // context.showSnackBar('Game with the same name already exists for this date', isError: true);
        return;
      }

      final response = await supabase.from('games').insert({
        'info_id': infoId,
        'game_date': gameDate.toIso8601String(),
        'off_day': isOffDay,
      });

      if (response != null) {
        context.showSnackBar(response.error!.message, isError: true);
      }
    } catch (error) {
      context.showSnackBar('Unexpected error occurred $error', isError: true);
    }
  }


  Future<void> _addGame2(int infoId, DateTime gameDate, bool isOffDay) async {
    final existingGame = _tempGameData.any(
          (game) =>
      game['info_id'] == infoId &&
          game['game_date'] == gameDate.toIso8601String(),
    );

    if (!existingGame) {
      _tempGameData.add({
        'info_id': infoId,
        'game_date': gameDate.toIso8601String(),
        'off_day': isOffDay,
      });
    }
  }

  Future<void> _insertAllGames() async {
    try {
      if (_tempGameData.isNotEmpty) {
        final response = await supabase.from('games').insert(_tempGameData);
        if (response != null) {
          context.showSnackBar(response, isError: true);
        }
        // else {
        //   context.showSnackBar('Chart extended successfully!');
        // }
      } else {
        context.showSnackBar('No data to extend.', isError: true);
      }
    } catch (error) {
      context.showSnackBar('Unexpected error occurred: $error', isError: true);
    } finally {
      _tempGameData.clear(); // Clear the buffer after insertion
    }
  }


  void _showSelectGameDialog() {
    if (isLoading) return;

    // Check if there are less than 2 games
    if (AppState().gameNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add games to manage'),
          duration: Duration(seconds: 2),
        ),
      );
      return; // Exit the method if there are not enough games
    }

    final now = AppState().getLiveTime(); // Get the current time
    final firstDayOfMonth = DateTime.utc(now.year, now.month, 1); // Calculate first day of the current month

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select a game'),
          content: Consumer<AppState>(
            builder: (context, appState, child) {
              return SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: appState.gameNames.length,
                  itemBuilder: (context, index) {
                    String shortGameName = appState.gameNames[index];

                    // Retrieve the first game_date for this shortGameName from appState.gameResults
                    String? gameDate;
                    int infoId = 0;
                    if (appState.gameResults.containsKey(shortGameName)) {
                      List<Map<String, dynamic>> games = appState.gameResults[shortGameName] ?? [];
                      if (games.isNotEmpty) {
                        gameDate = games.first['game_date'];
                        infoId = games.first['info_id'];
                      }
                    }

                    return ListTile(
                      title: Text(shortGameName),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ManageGamePage(
                              shortGameName: shortGameName,
                              gameDate: gameDate ?? firstDayOfMonth.toIso8601String(), // Pass gameDate or 'N/A' if not found
                              infoId: infoId, // Pass gameDate or 'N/A' if not found
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _handleDeleteChart() async {
    if (isLoading) return;

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to delete chart.')),
      );
      return; // Terminate initialization if conditions are not met
    }

    // Show progress indicator while the data is being fetched
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog by tapping outside
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(), // Show a circular progress indicator
        );
      },
    );
    // Fetch available months and corresponding info_ids
    Map<String, List<int>> monthsMap = await fetchUserMonths();

    Navigator.of(context).pop();

    if (monthsMap.isEmpty) {
      context.showSnackBar('No months available to delete', isError: true);
      return;
    }

    // Show list of months in a dialog
    final selectedMonth = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Month to Delete'),
          content: SingleChildScrollView(
            child: Column(
              children: monthsMap.keys.map((month) {
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

    if (selectedMonth == null) return;

    // Get the list of info_ids for the selected month
    List<int> selectedMonthInfoIds = monthsMap[selectedMonth] ?? [];

    final DateFormat format = DateFormat.yMMM();
    final DateTime monthDate = format.parse(selectedMonth);
    final firstDayOfMonth = DateTime.utc(monthDate.year, monthDate.month, 1);
    final lastDayOfMonth = DateTime.utc(monthDate.year, monthDate.month + 1, 0);

    bool showNextMonthWarning = false;

    // Check if the selected month is the current month
    final DateTime currentDate = DateTime.now();
    if (monthDate.year == currentDate.year && monthDate.month == currentDate.month) {
      // Check if games exist after the last day of the current month
      final additionalGames = await supabase
          .from('games')
          .select('id')
          .gt('game_date', lastDayOfMonth.toIso8601String())
          .limit(1);

      showNextMonthWarning = additionalGames.isNotEmpty;
    }

    // Show confirmation dialog
    bool confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        String userInput = '';

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirm Delete'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Are you sure you want to delete all games in $selectedMonth? This action cannot be undone.'),
                  if (showNextMonthWarning)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Warning: Games exist in the next month and will also be deleted if you proceed.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) {
                      setState(() {
                        userInput = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Type CONFIRM to proceed',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: userInput == 'CONFIRM'
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('Yes, Delete'),
                ),
              ],
            );
          },
        );
      },
    ) ?? false;


    if (!confirmDelete) return;

    setState(() {
      isLoading = true;
    });
    // Check for device mismatch
    final isMismatch = await AppState().checkDeviceMismatch(context);
    if (isMismatch) return; // Halt if there's a mismatch


    // Build an OR filter string for all the infoIds
    // final gamesFilter = selectedMonthInfoIds.map((id) => 'info_id.eq.$id').join(',');
    //
    // // Delete games for the selected month (and beyond if current month)
    // var deleteQuery = supabase
    //     .from('games')
    //     .delete()
    //     .or(gamesFilter)
    //     .gte('game_date', firstDayOfMonth.toIso8601String());
    //
    // if (!showNextMonthWarning) {
    //   deleteQuery = deleteQuery.lte('game_date', lastDayOfMonth.toIso8601String());
    // }
    //
    // final deleteResponse = await deleteQuery;
    //
    //
    // if (deleteResponse != null) {
    //   context.showSnackBar('Error deleting games', isError: true);
    //   setState(() {
    //     isLoading = false;
    //   });
    //   return;
    // }
    await _deleteGamesUsingRPC(
      selectedMonthInfoIds,
      firstDayOfMonth,
      showNextMonthWarning ? null : lastDayOfMonth,
    );


    // Check if any selectedMonthInfoId still exists in 'games' table
    // for (int infoId in selectedMonthInfoIds) {
    //   final gameExists = await supabase
    //       .from('games')
    //       .select('id')
    //       .eq('info_id', infoId)
    //       .limit(1);
    //
    //   if (gameExists.isEmpty) {
    //     // Delete infoId from 'game_info' table if no games found
    //     await supabase
    //         .from('game_info')
    //         .delete()
    //         .eq('id', infoId);
    //   }
    // }

    _refreshFullGame();
    // Show confirmation of deletion
    // context.showSnackBar('Games in $selectedMonth deleted successfully');
  }

  Future<void> _deleteGamesUsingRPC(
      List<int> infoIds, DateTime startDate, DateTime? endDate) async {
    try {
      final result = await supabase.rpc('delete_games_and_info', params: {
        'info_ids': infoIds,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
      });

      if (result != null) {
        throw Exception('RPC Error: $result');
      }

      context.showSnackBar('Games deleted successfully');
    } catch (e) {
      context.showSnackBar('Failed to delete games: $e', isError: true);
    }
  }



  Future<void> _updateTimezoneIfNull(String profileId, String timezone) async {
    try {
      // Query the 'khaiwals' table to check if the timezone is null for the given khaiwal_id
      final response = await supabase
          .from('khaiwals')
          .select('timezone')
          .eq('khaiwal_id', profileId)
          .single();

      if (response['timezone'] == null) {
        // Timezone is null, update it with the provided timezone
        final updateResponse = await supabase
            .from('khaiwals')
            .update({'timezone': timezone})
            .eq('khaiwal_id', profileId);

        if (updateResponse == null) {
          context.showSnackBar('Timezone updated successfully!');
        } else {
          context.showSnackBar('Failed to update timezone', isError: true);
        }
      } else {
        context.showSnackBar('Timezone is already set.');
      }
    } catch (error) {
      context.showSnackBar('Unexpected error occurred', isError: true);
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
      Navigator.of(context).pop(); // Dismiss the dialog

      await supabase.auth.signOut();
      await Supabase.instance.client.dispose();
      // Sign out from Google
      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.disconnect();
      }
      await AppState().resetState();

      // await Purchases.logOut(); // when using this it creates new users in revenuecat

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        elevation: 0.0, // Remove default shadow
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.blueAccent.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'sequence') {
                _reSequenceGameNames();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'sequence',
                child: Text('Re-arrange Games'),
              ),
            ],
            icon: const Icon(Icons.more_vert), // Three-dot menu icon
          ),
        ],
      ),
      drawer: Consumer<AppState>(
        builder: (context, appState, child) {
          return Drawer(
            child: ListView(
              children: [
                UserAccountsDrawerHeader(
                  accountName: Text(
                    appState.khaiwalName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  accountEmail: Text(appState.khaiwalEmail),
                  currentAccountPicture: GestureDetector(
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: (appState.avatarUrl.isNotEmpty)
                          ? NetworkImage(appState.avatarUrl)
                          : null,
                      backgroundColor: (appState.avatarUrl.isEmpty)
                          ? (appState.khaiwalName.isNotEmpty)
                          ? _isNumeric(appState.khaiwalName)
                          ? Colors.blueGrey // Background for numeric-only names
                          : getColorForLetter(getFirstValidLetter(appState.khaiwalName)?.toUpperCase() ?? '')
                          : Colors.grey // For null or empty names
                          : Colors.transparent,
                      child: (appState.avatarUrl.isEmpty)
                          ? (getFirstValidLetter(appState.khaiwalName) != null
                          ? Text(
                        getFirstValidLetter(appState.khaiwalName)!.toUpperCase(),
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

                  ),

                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue, Colors.blueAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.manage_accounts, color: Colors.blueGrey),
                  title: const Text('Profile'),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (isLoading) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const ProfilePage()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add, color: Colors.blueGrey),
                  title: const Text('Add Game'),
                  onTap: () {
                    Navigator.of(context).pop();
                    final now = AppState().currentTime;
                    final isCurrentMonth = selectMonth.year == now.year && selectMonth.month == now.month;
                    final isFutureMonth = selectMonth.isAfter(DateTime(now.year, now.month, 1));
                    final isPastMonth = selectMonth.isBefore(DateTime(now.year, now.month, 1));

                    if (isCurrentMonth) {
                      _showAddGameDialog();
                    } else if (isFutureMonth) {
                      _showAlertDialog('New games can only be added in the current month & auto extended to next months');
                    } else if (isPastMonth) {
                      _showAlertDialog('New games can only be added in the current month.');
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videogame_asset , color: Colors.blueGrey),
                  title: const Text('Manage Games'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showSelectGameDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month, color: Colors.blueGrey),
                  title: const Text('View Month'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showSelectMonthDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_all, color: Colors.blueGrey),
                  title: const Text('Extend Chart'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showSelectMonthDialogForDuplicate();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.blueGrey),
                  title: const Text('Delete Chart'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _handleDeleteChart();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.card_membership, color: Colors.blueGrey),
                  title: const Text('Manage\nSubscription'),
                  onTap: () {
                    _openSubscriptionPage();
                    // Handle Get Premium action
                  },
                ),
                if (AppState().subscription == 'super')
                ListTile(
                  leading: const Icon(Icons.star, color: Colors.blueAccent),
                  title: const Text('Get Premium'),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (isLoading) return;
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SubscriptionPage()));
                    // Handle Get Premium action
                  },
                ),
                if (AppState().subscription != 'super' && AppState().subscription != 'premium')
                  ListTile(
                    leading: const Icon(Icons.star, color: Colors.blueAccent),
                    title: const Text('Get Subscription'),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (isLoading) return;
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SubscriptionPage()));
                      // Handle Get Premium action
                    },
                  ),
                // Sign Out button positioned at the bottom
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.blueGrey),
                  title: const Text('Sign Out'),
                  onTap: () {
                    Navigator.of(context).pop(); // Close the drawer
                    _showSignOutDialog(); // Show sign out confirmation dialog
                  },
                ),
              ],
            ),
          );
        },
      ),
        body: Consumer<AppState>(
          builder: (context, appState, child) {
            return isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _refreshGameResults,
              child: appState.gameNames.isEmpty
                  ? ListView(
                children: const [
                  Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 200), // Adjust as needed
                      child: Text(
                        'No games found for the current month',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ) : DataTable2(
                border: TableBorder.all(color: Colors.grey.shade300),
                headingRowColor: WidgetStateProperty.all(Colors.blue.shade100),
                columnSpacing: 0,
                horizontalMargin: 4,
                minWidth: _calculateMinWidth(appState.gameNames.length),
                fixedLeftColumns: 1, // Fix the first column (Date)

                columns: [
                  const DataColumn2(
                    label: Center(
                      child: Text(
                        'Date',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center, // Ensures the alignment inside the Text
                      ),
                    ),
                    fixedWidth: 100,
                  ),
                  ...appState.gameNames.map(
                        (name) => DataColumn2(
                      label: Center(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
                rows: _generateDataRows(appState),
              ),
            );
          },
        )
    );
  }

  void _reSequenceGameNames() {
    AppState appState = AppState();

    // Check if there are less than 2 games
    if (appState.gameNames.isEmpty || appState.gameNames.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a minimum of 2 games to sequence them.'),
          duration: Duration(seconds: 2),
        ),
      );
      return; // Exit the method if there are not enough games
    }

    List<String> tempGameNames = List.from(appState.gameNames);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Re-arrange Games'),
          content: SizedBox(
            width: double.maxFinite,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                // Calculate the dynamic height based on the number of items
                const maxDialogHeight = 400.0; // Maximum dialog height
                const itemHeight = 56.0; // Approximate height of each ListTile
                final calculatedHeight =
                (itemHeight * tempGameNames.length).clamp(100.0, maxDialogHeight);

                return SizedBox(
                  height: calculatedHeight,
                  child: ReorderableListView(
                    onReorder: (oldIndex, newIndex) {
                      setDialogState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = tempGameNames.removeAt(oldIndex);
                        tempGameNames.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (int index = 0; index < tempGameNames.length; index++)
                        ListTile(
                          key: ValueKey(index),
                          title: Text(tempGameNames[index]),
                          trailing: const Icon(Icons.drag_handle),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: isLoading
              ? []
              : [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                setState(() {
                  appState.gameNames = List.from(tempGameNames);
                  isLoading = true;
                });
                await _updateGameSequenceInDatabase(appState);
                setState(() {
                  isLoading = false;
                });
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateGameSequenceInDatabase(AppState appState) async {
    final isMismatch = await AppState().checkDeviceMismatch(context);
    if (isMismatch) return; // Halt if there's a mismatch

    for (int index = 0; index < appState.gameNames.length; index++) {
      final gameName = appState.gameNames[index];
      final gameInfo = appState.gameResults[gameName]?.first;

      if (gameInfo != null) {
        final infoId = gameInfo['info_id'];
        try {
          await supabase
              .from('game_info')
              .update({'sequence': index + 1}) // New sequence starts at 1
              .eq('id', infoId);
        } catch (error) {
          if (kDebugMode) {
            print('Error updating game sequence: $error');
          }
        }
      }
    }
  }




  double _calculateMinWidth(int length) {
    if (length <= 2) {
      return 400;
    } else if (length == 3) {
      return 450;
    } else if (length == 4) {
      return 500;
    } else if (length == 5) {
      return 550;
    } else {
      return 550 + ((length - 5) * 80); // Add 80 for each additional column after 5
    }
  }


  List<DataRow> _generateDataRows(AppState appState) {
    Set<String> allDates = appState.gameResults.values
        .expand((results) => results.map((result) => result['game_date'] as String))
        .toSet();

    return allDates.map((date) {
      String formattedDate = appState.formatGameDate(date);
      List<DataCell> cells = [
        DataCell(Center(child: Text(formattedDate))),
        ...appState.gameNames.map((name) {
          final result = appState.gameResults[name]?.firstWhere(
                (result) => result['game_date'] == date,
            orElse: () => {'game_date': date, 'game_result': ''},
          );
          return DataCell(
            GestureDetector(
              onTap: () => _onGameResultTap(
                result?['id'],
                result?['info_id'],
                name,
                date,
                result?['game_result'] ?? '',
                result?['off_day'],
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: result?['game_result'] != null && result!['game_result'] != ''
                        ? Colors.green.shade50
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.5),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    result?['game_result'] ?? '  ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green
                    ),
                    // textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }),
      ];
      return DataRow(cells: cells);
    }).toList();
  }


  void _openSubscriptionPage() async {
    const url = 'https://play.google.com/store/account/subscriptions';

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      // Show an error if the URL cannot be opened
      debugPrint("Could not launch $url");
    }
  }

  Future<void> _refreshGameResults() async {
    setState(() {
      isLoading = true; // Set loading to true before fetching data
    });

    await context.read<AppState>().fetchGameResultsForCurrentDayAndYesterday();
    await context.read<AppState>().checkGamePlayExistence();
    selectMonth = context.read<AppState>().currentTime;

    setState(() {
      isLoading = false; // Set loading to false after fetching data
    });
  }

  Future<void> _refreshFullGame() async {
    setState(() {
      isLoading = true; // Set loading to true before fetching data
    });

    await context.read<AppState>().fetchGameNamesAndResults();
    await context.read<AppState>().fetchGamesForCurrentDateOrTomorrow();
    await context.read<AppState>().checkGamePlayExistence();

    setState(() {
      isLoading = false; // Set loading to false after fetching data
    });
  }


  void _onGameResultTap(int gameId, int infoId, String gameName, String gameDate, String gameResult, bool? offDay) async {
    if (gameResult.isEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(
              'Game Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge,
                      children: [
                        const TextSpan(
                          text: 'Short Name: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: gameName),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge,
                      children: [
                        const TextSpan(
                          text: 'Date: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: AppState().formatGameDate(gameDate)),
                      ],
                    ),
                  ),
                  if (offDay == true)
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge,
                        children: const [
                          TextSpan(
                            text: 'Day Off: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: 'Yes'),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'No result has been declared for this game yet.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  // Handle 'Declare Result' action
                  Navigator.pop(context); // Close the dialog
                  _showDeclareDialog(context, gameId, infoId, gameDate, offDay);
                },
                child: const Text('Declare Result'),
              ),
              TextButton(
                onPressed: () async {
                  // Handle 'Open Game' action
                  Navigator.pop(context); // Close the dialog
                  // Navigate to PlayPage
                  await _navigateToPlayPage(gameId, infoId, gameDate);

                },
                child: const Text('Open Game'),
              ),
            ],
          );
        },
      );
    } else {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(
              'Game Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge,
                      children: [
                        const TextSpan(
                          text: 'Short Name: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: gameName),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge,
                      children: [
                        const TextSpan(
                          text: 'Date: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: AppState().formatGameDate(gameDate)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge,
                      children: [
                        const TextSpan(
                          text: 'Result: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: gameResult),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Result has been declared for this game.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close the dialog
                  showDialog(
                    context: context,
                    barrierDismissible: true,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('Confirm Reset'),
                        content: const Text(
                          'Are you sure you want to reset the game result? This will also reset all user winnings for this game.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop(); // Dismiss the dialog
                            },
                            child: const Text('No'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.of(context).pop(); // Dismiss the dialog
                              // Delay to ensure dialog is dismissed
                              await _resetGame(gameId, infoId, gameDate); // Run the reset method
                            },
                            child: const Text('Yes'),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text('Reset Result'),
              ),
              TextButton(
                onPressed: () async {
                  // Handle 'Open in View Mode' action
                  Navigator.pop(context); // Close the dialog

                  // Navigate to PlayPage
                  await _navigateToPlayPage(gameId, infoId, gameDate);
                },
                child: const Text('View Game'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _navigateToPlayPage(int gameId, int infoId, String gameDate) async {
    // Fetch the game info
    final response = await supabase
        .from('game_info')
        .select('full_game_name, open_time, big_play_min, close_time_min, day_before')
        .eq('id', infoId)
        .maybeSingle();

    if (response == null || response.isEmpty) {
      return;
    }
    final openTimeParts = response['open_time'].split(':');
    DateTime openGameDate = DateTime.parse(gameDate);
    DateTime openTime = DateTime.utc(
      openGameDate.year,
      openGameDate.month,
      openGameDate.day,
      int.parse(openTimeParts[0]),
      int.parse(openTimeParts[1]),
      int.parse(openTimeParts[2]),
    );

    // Parse 'close_time_min' from the game and add it to openTime to create closeTime
    DateTime closeTime = openTime.add(Duration(minutes: response['close_time_min']));
    // Parse 'last_big_play_min' from the game
    DateTime lastBigPlayTime = openTime.add(Duration(minutes: response['big_play_min']));

    // Navigate to PlayPage
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayPage(
          gameId: gameId,
          infoId: infoId,
          fullGameName: response['full_game_name'],
          gameDate: gameDate,
          closeTime: closeTime,
          lastBigPlayTime: lastBigPlayTime,
          lastBigPlayMinute: response['big_play_min'],
          isDayBefore: response['day_before'],
        ),
      ),
    );
  }


  void _showDeclareDialog(BuildContext context, int gameId, int infoId, String gameDate, bool? dayOff) {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to declare game result')),
      );
      return; // Terminate initialization if conditions are not met
    }

    if (dayOff == true) {
      // Show a dialog if the dayOff is true
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Day Off Declared'),
            content: Text(
              'The game on $gameDate has already been declared as a Day Off.',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close the dialog
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return; // Exit the method since the game can't be declared again
    }

    TextEditingController resultController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Game Result'),
          content: TextField(
            controller: resultController,
            keyboardType: TextInputType.number,
            maxLength: 2, // Ensure only 2 digits
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: 'Enter 2-digit result'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (resultController.text.length == 2) {
                  Navigator.pop(context);
                  await _declareGame(gameId, infoId, gameDate, resultController.text);
                }
              },
              child: const Text('Declare Result'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _declareGame(int gameId, int infoId, String gameDate, String gameResult) async {
    // Show confirmation dialog
    final confirmReset = await _showGameConfirmationDialog(
      'Confirm Game Declare',
      'You are about to declare the game result.\n\n'
          'Do you want to proceed?',
    );
    if (!confirmReset) return;
    // Show progress indicator while the data is being fetched
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog by tapping outside
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(), // Show a circular progress indicator
        );
      },
    );
    try{
      // Check for device mismatch
      // final isMismatch = await AppState().checkDeviceMismatch(context);
      // if (isMismatch) return; // Halt if there's a mismatch

      await AppState().refreshTime();

      final now = AppState().currentTime;
      DateTime currentTime = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute, now.second);

      // Fetch the game info
      final response = await supabase
          .from('game_info')
          .select('open_time, close_time_min, day_before')
          .eq('id', infoId)
          .maybeSingle();

      if (response == null || response.isEmpty) {
        // Close the loading indicator
        Navigator.of(context).pop();
        _showAlertDialog('Unable to fetch game information.');
        return;
      }

      final openTimeParts = response['open_time'].split(':');
      DateTime gameDateTime  = DateTime.parse(gameDate);

      DateTime openTime = DateTime.utc(
        gameDateTime.year,
        gameDateTime.month,
        gameDateTime.day,
        int.parse(openTimeParts[0]),
        int.parse(openTimeParts[1]),
        int.parse(openTimeParts[2]),
      );
      // Parse 'close_time_min' from the game and add it to openTime to create closeTime
      DateTime closeTime = openTime.add(Duration(minutes: response['close_time_min']));

      if (response['day_before'] == true) {
        currentTime = currentTime.add(const Duration(days: 1));
      }

      if (currentTime.isAfter(openTime) && currentTime.isBefore(closeTime)) {
        Navigator.of(context).pop();
        _showAlertDialog('The game is in progress and can be declared after close time');
        return;
      }

      if (gameDateTime.isAfter(currentTime)) {
        Navigator.of(context).pop();
        _showAlertDialog('Game result can only be declared for current and previous game dates');
        return;
      }

      final resultResponse = await supabase
          .from('games')
          .select('game_result')
          .eq('id', gameId);

      if (resultResponse[0]['game_result'] != null) {
        // Close the loading indicator
        Navigator.of(context).pop();

        _refreshFullGame();
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Game result has been already declared.')),
        );
        return;
      }

      // Step 1: Fetch users' kp_id and slot_amount
      final gameDataResponse = await supabase
          .from('game_play')
          .select('id, kp_id, slot_amount')
          .eq('game_id', gameId)
          .or('is_win.is.null');

      if (gameDataResponse.isEmpty) {
        await supabase.from('games').update({
          'game_result': gameResult,
          'total_invested': 0,
        }).eq('id', gameId);

        // Close the loading indicator
        Navigator.of(context).pop();

        _refreshFullGame();
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Game declared successfully.')),
        );
        return;
      }

      final usersData = gameDataResponse as List;

      int totalInvested = 0;

      // Temporary storage for batched operations
      List<Map<String, dynamic>> walletBalanceGamePlayData = [];
      List<Map<String, dynamic>> gamePlayOnlyUpdates = [];

      // Step 2: Iterate through each user and calculate win/loss
      for (final user in usersData) {
        final int gamePlayId = user['id'];
        final int kpId = user['kp_id'];
        final String slotAmount = user['slot_amount'];

        // Fetch user rate, commission, and patti
        final userDetailsResponse = await supabase
            .from('khaiwals_players')
            .select('rate, commission, patti')
            .eq('id', kpId);

        if (userDetailsResponse.isEmpty) {
          if (kDebugMode) {
            print('Error fetching user details: $userDetailsResponse');
          }
          continue;
        }

        final int userRate = userDetailsResponse[0]['rate'];
        final int userCommission = userDetailsResponse[0]['commission'];
        final int userPatti = userDetailsResponse[0]['patti'];

        // Step 3: Calculate total amount invested
        int totalAmountInvested = _calculateTotalAmountInvested(slotAmount);
        totalInvested += totalAmountInvested;

        // Step 4: Determine win/loss amount
        double winLossAmount = 0;
        bool hasWinningSlot = false;
        int passAmount = 0;
        int rateWon = 0;
        double commissionWon = 0.0;

        // Split the slot_amount into individual slots
        final slotPairs = slotAmount.split(' / ');
        for (var pair in slotPairs) {
          final keyValue = pair.split('=');
          if (keyValue.length == 2) {
            final slotNumber = keyValue[0].trim();
            passAmount = int.parse(keyValue[1].trim());

            // Check if slot matches the game result
            if (slotNumber == gameResult && userPatti == 0) {
              rateWon = passAmount * userRate;
              commissionWon = (userCommission / 100.0) * totalAmountInvested;
              winLossAmount += rateWon + commissionWon;
              hasWinningSlot = true;
            }
          }
        }

        // Calculate loss amount if no winning slot
        if (!hasWinningSlot) {
          winLossAmount = (userCommission / 100.0) * totalAmountInvested;
          commissionWon = winLossAmount;
        }

        // Calculate the final win/loss balance by deducting total investment
        double finalWinLoss = winLossAmount - totalAmountInvested;

        // Step 5: Update balance and insert into wallet, update game_play
        // if user win
        if (winLossAmount > 0 || userCommission > 0) {
          // prepare all three data into one
          walletBalanceGamePlayData.add({
            'kp_id': kpId,
            'game_id': gameId,
            'game_play_id': gamePlayId,
            'transaction_type': 'Credit',
            'amount': winLossAmount,
            'is_win': hasWinningSlot,
            'pass_amount': passAmount,
            'rate_win': rateWon,
            'commission_win': commissionWon,
            'net_win': finalWinLoss,
            'timestamp': AppState().currentTime.toIso8601String(),
          });

        } else {
          // Add to gamePlayOnlyUpdates
          gamePlayOnlyUpdates.add({
            'kp_id': kpId,
            'game_id': gameId,
            'game_play_id': gamePlayId,
            'is_win': hasWinningSlot,
            'net_win': finalWinLoss,
          });
        }
      }

      // Close the loading indicator
      // Navigator.of(context).pop();
      //
      // // Show confirmation dialog
      // final confirmReset = await _showGameConfirmationDialog(
      //   'Confirm Game Declare',
      //   'You are about to declare the game result.\n\n'
      //       'Do you want to proceed?',
      // );
      // if (!confirmReset) return;
      //
      // showDialog(
      //   context: context,
      //   barrierDismissible: false, // Prevent closing the dialog by tapping outside
      //   builder: (BuildContext context) {
      //     return const Center(
      //       child: CircularProgressIndicator(), // Show a circular progress indicator
      //     );
      //   },
      // );

      // Check for device mismatch
      final isMismatch2 = await AppState().checkDeviceMismatch(context);
      if (isMismatch2) return; // Halt if there's a mismatch

      // Step 3: Execute batch RPC
      await supabase.rpc('declare_game', params: {
        'game_id_param': gameId,
        'game_result_param': gameResult,
        'total_invested_param': totalInvested,
        'wallet_balance_game_play_data': walletBalanceGamePlayData,
        'game_play_only_updates': gamePlayOnlyUpdates,
      });

      // Close the loading indicator
      Navigator.of(context).pop();

      AppState().fetchMenuUsers();
      _refreshFullGame();
      // Show success snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game declared successfully.')),
      );

    } catch (error) {
      // Close the loading indicator
      Navigator.of(context).pop();

      _refreshFullGame();
      // Show failure snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error declaring game: $error')),
      );
    }
  }

  // Helper function to calculate total investment from slotAmount
  int _calculateTotalAmountInvested(String slotAmount) {
    int total = 0;
    final slotPairs = slotAmount.split(' / ');

    for (var pair in slotPairs) {
      final keyValue = pair.split('=');
      if (keyValue.length == 2) {
        total += int.parse(keyValue[1].trim());
      }
    }

    return total;
  }

  Future<void> _resetGame(int gameId, int infoId, String gameDate) async {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to reset game result')),
      );
      return; // Terminate initialization if conditions are not met
    }
    // Show progress indicator while the data is being fetched
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog by tapping outside
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(), // Show a circular progress indicator
        );
      },
    );
    try{
      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      final now = AppState().currentTime;
      DateTime currentTime = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute, now.second);

      // Fetch game information
      final response = await supabase
          .from('game_info')
          .select('open_time, day_before')
          .eq('id', infoId)
          .maybeSingle();

      if (response == null || response.isEmpty) {
        Navigator.of(context).pop();
        _showAlertDialog('Unable to fetch game information.');
        return;
      }

      DateTime gameDateTime = DateTime.parse(gameDate);

      // Adjust current time for "day_before" scenario
      if (response['day_before'] == true) {
        currentTime = currentTime.add(const Duration(days: 1));
      }

      // Check if gameDateTime is older than 2 days
      final differenceInDays = currentTime.difference(gameDateTime).inDays;
      if (differenceInDays > 2) {
        final gamePlayResponse = await supabase
            .from('game_play')
            .select('id')
            .eq('game_id', gameId)
            .limit(1);

        if (gamePlayResponse.isNotEmpty) {
          Navigator.of(context).pop();
          _showAlertDialog('Game date contains game play and older than 2 days, it cannot be reset.');
          return;
        }
      }


      // Step 1: Fetch users' kp_id and slot_amount
      final gameDataResponse = await supabase
          .from('game_play')
          .select('id, result_txn_id, kp_id, rate_win, commission_win')
          .eq('game_id', gameId)
          .not('is_win', 'is', 'null');

      if (gameDataResponse.isEmpty) {
        await supabase.from('games').update({
          'game_result': null,
          'total_invested': null,
        }).eq('id', gameId);

        // Close the loading indicator
        Navigator.of(context).pop();

        _refreshFullGame();
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Game resets successfully.')),
        );
        return;
      }

      final List<Map<String, dynamic>> resetData = (gameDataResponse as List).map((user) {
        return {
          'kp_id': user['kp_id'],
          'result_txn_id': user['result_txn_id'],
          'rate_win': user['rate_win'] ?? 0,
          'commission_win': user['commission_win'] ?? 0,
          'game_play_id': user['id'],
        };
      }).toList();

      if (mounted) Navigator.of(context).pop(); // Close the loading indicator

      // Show confirmation dialog
      final confirmReset = await _showGameConfirmationDialog(
        'Confirm Game Reset',
        'You are about to reset the game result.\n\n'
            'Affected players: ${resetData.length}\n\n'
            'Do you want to proceed?',
      );

      if (!confirmReset || !mounted) return; // Halt if user cancels or widget is unmounted

      // Show the progress indicator again before the RPC call
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(child: CircularProgressIndicator());
        },
      );

      // Check for device mismatch again
      final isMismatch2 = await AppState().checkDeviceMismatch(context);
      if (isMismatch2 || !mounted) return;

      // Step 2: Call the RPC to handle the reset logic server-side
      await supabase.rpc('reset_game', params: {
        'game_id_param': gameId,
        'reset_data': resetData,
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close the loading indicator
        AppState().fetchMenuUsers();
        _refreshFullGame();
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Game resets successfully.')),
        );
      }

    } catch (error) {
      // Close the loading indicator
      Navigator.of(context).pop();

      _refreshFullGame();
      // Show failure snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resetting game: $error')),
      );
    }
  }

  bool _isNumeric(String input) {
    final numericRegex = RegExp(r'^[0-9]+$');
    return numericRegex.hasMatch(input);
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




// String getTimeZone() {
  //   DateTime now = DateTime.now();
  //   Duration offset = now.timeZoneOffset;
  //
  //   // Calculate the absolute value of hours and minutes
  //   int hours = offset.inHours.abs();
  //   int minutes = offset.inMinutes.remainder(60).abs();
  //
  //   // Determine the offset sign
  //   String offsetSign = offset.isNegative ? '-' : '+';
  //
  //   return 'UTC $offsetSign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  // }



  // String getUserTimezone() {
  //   final now = DateTime.now();
  //   final timezoneOffset = now.timeZoneOffset;
  //   final timezoneName = now.timeZoneName;
  //
  //   // Format the timezone offset as a string, e.g., +02:00 or -05:00
  //   final String formattedOffset = (timezoneOffset.isNegative ? '-' : '+') +
  //       timezoneOffset.abs().inHours.toString().padLeft(2, '0') + ':' +
  //       (timezoneOffset.inMinutes % 60).toString().padLeft(2, '0');
  //
  //   return '$timezoneName (UTC$formattedOffset)';
  // }



}
