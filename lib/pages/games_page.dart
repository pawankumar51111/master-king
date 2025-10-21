import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import 'play_page.dart';  // Import PlayPage
import '../main.dart';

class GamesPage extends StatefulWidget {
  const GamesPage({super.key});

  @override
  _GamesPageState createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  late DateTime currentTime;
  late DateTime tomorrowTime;
  late Timer _timer;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize currentTime with the accurate time from AppState
    currentTime = context.read<AppState>().currentTime;
    tomorrowTime = context.read<AppState>().currentTime.add(const Duration(days: 1));

    // Set up a timer to update the currentTime every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        currentTime = context.read<AppState>().currentTime.add(const Duration(seconds: 1));
        tomorrowTime = context.read<AppState>().currentTime.add(const Duration(days: 1, seconds: 1));
      });
    });
  }

  Future<void> _refreshGames() async {
    // Notify the UI that loading has started
    setState(() {
      isLoading = true;
    });

    await context.read<AppState>().fetchGameResultsForCurrentDayAndYesterday();
    await context.read<AppState>().checkGamePlayExistence();

    // Notify the UI that loading has finished
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Games'),
        // backgroundColor: Colors.orangeAccent,
        backgroundColor: Colors.transparent,
        elevation: 0.0, // Remove default shadow
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orangeAccent.shade200, Colors.orange.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          // Show a CircularProgressIndicator while data is being fetched
          if (isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // Filter active games
          final activeGames = appState.games.where((game) => game['is_active'] == true).toList();

          if (activeGames.isEmpty) {
            return const Center(child: Text('No games found for today', style: TextStyle(color: Colors.grey),));
          }

          return RefreshIndicator(
            onRefresh: _refreshGames, // Trigger refresh when pulled down
            child: ListView.separated(
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: Colors.grey,
              ),
              itemCount: activeGames.length,
              itemBuilder: (context, index) {
                final game = activeGames[index];

                // Skip the game if 'off_day' is true
                if (game['is_active'] == false) {
                  return const SizedBox.shrink();
                }

                DateTime openTime;
                DateTime closeTime;
                DateTime lastBigPlayTime;

                // Parse the open_time, close_time & edit_minutes
                try {
                  final openTimeParts = game['open_time'].split(':');
                  DateTime gameDate = DateTime.parse(game['game_date']);
                  openTime = DateTime.utc(
                    gameDate.year,
                    gameDate.month,
                    gameDate.day,
                    int.parse(openTimeParts[0]),
                    int.parse(openTimeParts[1]),
                    int.parse(openTimeParts[2]),
                  );

                  // Parse 'close_time_min' from the game and add it to openTime to create closeTime
                  closeTime = openTime.add(Duration(minutes: game['close_time_min']));

                  // Parse 'last_big_play_min' from the game
                  lastBigPlayTime = openTime.add(Duration(minutes: game['big_play_min']));

                } catch (e) {
                  return ListTile(
                    title: Text(game['full_game_name']),
                    subtitle: Text('Invalid time format $e'),
                  );
                }

                final isTimeOver = currentTime.isAfter(closeTime);
                final isBeforeOpenTime = currentTime.isBefore(openTime);

                final isTimeOver2 = tomorrowTime.isAfter(closeTime);
                final isBeforeOpenTime2 = tomorrowTime.isBefore(openTime);

                final String status;
                final Color bgColor;
                final Icon icon;

                 if (game['game_result'] != null && game['game_result'] != '') {
                   status = 'Declared';
                   bgColor = Colors.blue.shade50;
                   icon = const Icon(Icons.check_circle, color: Colors.blue, size: 16);
                 } else if (game['off_day'] == true) {
                   status = 'Day Off';
                   bgColor = Colors.orange.shade50;
                   icon = const Icon(Icons.event_busy, color: Colors.orange, size: 16);
                 } else if (game['pause'] == true && !isTimeOver) {
                   status = 'Paused';
                   bgColor = Colors.orange.shade50;
                   icon = const Icon(Icons.pause_circle_filled, color: Colors.grey, size: 16);
                 } else if ((isBeforeOpenTime && !game['day_before']) || (isBeforeOpenTime2 && game['day_before'])) {
                   status = 'Not Open Yet';
                   bgColor = Colors.orange.shade50;
                   icon = const Icon(Icons.access_time, color: Colors.orange, size: 16);
                 } else if ((!isBeforeOpenTime && !isTimeOver && !game['day_before']) ||
                     (!isBeforeOpenTime2 && !isTimeOver2 && game['day_before'])) {
                   status = 'Live';
                   bgColor = Colors.green.shade50;
                   icon = const Icon(Icons.play_circle_fill, color: Colors.green, size: 16);
                 } else if ((isTimeOver && !game['day_before']) || (isTimeOver2 && game['day_before'])) {
                   status = 'Time Over';
                   bgColor = Colors.red.shade50;
                   icon = const Icon(Icons.stop_circle, color: Colors.red, size: 16);
                 } else {
                   status = '';
                   bgColor = Colors.orange.shade50;
                   icon = const Icon(Icons.help_outline, color: Colors.grey, size: 16); // Default icon
                 }

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: bgColor,

                  child: ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, // Space between the children
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded( // Use Expanded to take available space
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Row for the icon and full_game_name
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Icon based on the game status
                                  // if (game['game_result'] != null && game['game_result'] != '')
                                  //   const Icon(Icons.check_circle, color: Colors.blue, size: 16)
                                  // else if (game['off_day'] == true)
                                  //   const Icon(Icons.event_busy, color: Colors.orange, size: 16)
                                  // else if (game['pause'] == true && !isTimeOver)
                                  //     const Icon(Icons.pause_circle_filled, color: Colors.grey, size: 16)
                                  //   else if ((isBeforeOpenTime && !game['day_before']) || (isBeforeOpenTime2 && game['day_before']))
                                  //       const Icon(Icons.access_time, color: Colors.orange, size: 16)
                                  //     else if ((!isBeforeOpenTime && !isTimeOver && !game['day_before']) ||
                                  //           (!isBeforeOpenTime2 && !isTimeOver2 && game['day_before']))
                                  //         const Icon(Icons.play_circle_fill, color: Colors.green, size: 16)
                                  //       else if ((isTimeOver && !game['day_before']) || (isTimeOver2 && game['day_before']))
                                  //           const Icon(Icons.stop_circle, color: Colors.red, size: 16),
                                  icon,
                                  const SizedBox(width: 8), // Add spacing between the icon and text
                                  // Full game name
                                  Expanded(
                                    child: Text(
                                      game['full_game_name'],
                                      style: const TextStyle(color: Colors.black, fontSize: 18),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],

                              ),
                            ],
                          ),
                        ),

                        Column(
                          children: [
                            Text(
                              AppState().formatGameDate(game['game_date']),
                              style: const TextStyle(color: Colors.grey, fontSize: 14), // Light grey color for the date
                            ),
                            // Status text
                            if (game['game_result'] != null && game['game_result'] != '')
                              Text('Result:${game['game_result']}', style: const TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic))

                            else Text(status, style: const TextStyle(color: Colors.grey, fontSize: 12),),

                            // else if (game['off_day'] == true)
                            //   const Text(
                            //     'Day Off',
                            //     style: TextStyle(color: Colors.grey, fontSize: 12), // Smaller, grey text
                            //   )
                            // else if (game['pause'] == true && !isTimeOver)
                            //     const Text(
                            //       'Paused',
                            //       style: TextStyle(color: Colors.grey, fontSize: 12), // Light grey for Paused
                            //     )
                            //   else if ((isBeforeOpenTime && !game['day_before']) || (isBeforeOpenTime2 && game['day_before']))
                            //       const Text(
                            //         'Not Open Yet',
                            //         style: TextStyle(color: Colors.grey, fontSize: 12), // Smaller, grey text
                            //       )
                            //     else if ((!isBeforeOpenTime && !isTimeOver && !game['day_before']) ||
                            //           (!isBeforeOpenTime2 && !isTimeOver2 && game['day_before']))
                            //         const Text(
                            //           'Live',
                            //           style: TextStyle(color: Colors.grey, fontSize: 12), // Smaller, grey text
                            //         )
                            //       else if ((isTimeOver && !game['day_before']) || (isTimeOver2 && game['day_before']))
                            //           const Text(
                            //             'Time Over',
                            //             style: TextStyle(color: Colors.grey, fontSize: 12), // Smaller, grey text
                            //           ),
                          ],
                        )
                        // Right-aligned game date
                      ],
                    ),
                    subtitle: Row(
                      children: [

                        if (game['game_result'] != null && game['game_result'] != '')
                          // Text('Result:${game['game_result']}', style: const TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic))
                          const Text('')

                        else if (game['off_day'] == true)
                          const Text('')

                        else if (game['pause'] == true && !isTimeOver)
                          const Text('Game is Paused')

                        else if ((isBeforeOpenTime && !game['day_before']) || (isBeforeOpenTime2 && game['day_before']))
                          Text('Game Opens at ${formatTimeTo12Hour(game['open_time'])}')

                          else if ((isTimeOver && !game['day_before']) || (isTimeOver2 && game['day_before']))
                              ElevatedButton(
                                onPressed: () {
                                  _showDeclareDialog(context, game['id']);
                                },
                                child: const Text('Declare'),
                              ),

                        if (game['game_result'] != null && game['game_result'] != '') ...[
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () {
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
                                          await _resetGame(game['id']); // Run the reset method
                                        },
                                        child: const Text('Yes'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            child: const Text('Reset'),
                          ),
                        ],


                        if (!game['off_day'] && (!game['day_before'] && !isBeforeOpenTime) || (game['day_before'] && !isBeforeOpenTime2)) ...[
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PlayPage(
                                    gameId: game['id'],
                                    infoId: game['info_id'],
                                    fullGameName: game['full_game_name'],
                                    gameDate: game['game_date'],
                                    closeTime: closeTime,
                                    lastBigPlayTime: lastBigPlayTime,
                                    lastBigPlayMinute: game['big_play_min'],
                                    isDayBefore: game['day_before'],
                                  ),
                                ),
                              );
                            },
                            child: const Text('Open'),
                          ),
                        ],


                        if (!game['off_day'] && (!game['day_before'] && appState.gamePlayExists[game['id']] == true && !isBeforeOpenTime)
                            || (game['day_before'] && appState.gamePlayExists[game['id']] == true && !isBeforeOpenTime2)) ...[
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () async {
                              await _fetchAndShowSlotAmount(context, game['id'], game['full_game_name']);
                            },
                            child: const Text('View'),
                          ),
                        ],
                      ],
                    ),
                    onTap: () {
                      _showGameDetails(context, game, status, openTime, closeTime);
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showGameDetails(BuildContext context, Map<String, dynamic> game, String status, DateTime openTime, DateTime closeTime) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Game Name
                Text(
                  game['full_game_name'] ?? 'Unknown Game',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // Game Date
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      AppState().formatGameDate(game['game_date']),
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Status
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('Status: $status',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Open Time
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Open Time: ${formatTimeTo12Hour(game['open_time'])}',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Close Time
                Row(
                  children: [
                    const Icon(Icons.lock_clock, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Close Time: ${formatTimeTo12Hour(closeTime.toIso8601String().substring(11))}',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CLOSE'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  void _showDeclareDialog(BuildContext context, int gameId) {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to declare game result')),
      );
      return; // Terminate initialization if conditions are not met
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
                  await _declareGame(gameId, resultController.text);
                }
              },
              child: const Text('Declare Result'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _declareGame(int gameId, String gameResult) async {
    // Show confirmation dialog
    final confirmDeclare = await _showConfirmationDialog(
      'Confirm Game Declare',
      'You are about to declare the game result.\n\n'
          'Do you want to proceed?',
    );
    if (!confirmDeclare) return;

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

      // check if the result is already declared
      final resultResponse = await supabase
          .from('games')
          .select('game_result')
          .eq('id', gameId);

      if (resultResponse[0]['game_result'] != null) {
        // Close the loading indicator
        Navigator.of(context).pop();

        _refreshGames();
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

        _refreshGames();
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
        // Check if user meets wallet insertion criteria
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
      // final confirmReset = await _showConfirmationDialog(
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
      _refreshGames();
      // Show success snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game declared successfully.')),
      );

    } catch (error) {
      // Close the loading indicator
      Navigator.of(context).pop();

      _refreshGames();
      // Show failure snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error declaring game: $error')),
      );
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message) async {
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


  // Future<void> _declareGame(int gameId, String gameResult) async {
  //   // Show progress indicator while the data is being fetched
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false, // Prevent closing the dialog by tapping outside
  //     builder: (BuildContext context) {
  //       return const Center(
  //         child: CircularProgressIndicator(), // Show a circular progress indicator
  //       );
  //     },
  //   );
  //   try{
  //     // Check for device mismatch
  //     final isMismatch = await AppState().checkDeviceMismatch(context);
  //     if (isMismatch) return; // Halt if there's a mismatch
  //
  //     // Step 1: Fetch users' kp_id and slot_amount
  //     final gameDataResponse = await supabase
  //         .from('game_play')
  //         .select('kp_id, slot_amount')
  //         .eq('game_id', gameId)
  //         .or('is_win.is.null');
  //
  //     if (gameDataResponse.isEmpty) {
  //       await supabase.from('games').update({
  //         'game_result': gameResult,
  //         'total_invested': 0,
  //       }).eq('id', gameId);
  //
  //       // Close the loading indicator
  //       Navigator.of(context).pop();
  //
  //       _refreshGames();
  //       // Show success snackbar
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('Game declared successfully.')),
  //       );
  //       return;
  //     }
  //
  //     final usersData = gameDataResponse as List;
  //
  //     int totalInvested = 0;
  //
  //     // Step 2: Iterate through each user and calculate win/loss
  //     for (final user in usersData) {
  //       final int kpId = user['kp_id'];
  //       final String slotAmount = user['slot_amount'];
  //
  //       // Fetch user rate, commission, and patti
  //       final userDetailsResponse = await supabase
  //           .from('khaiwals_players')
  //           .select('rate, commission, patti')
  //           .eq('id', kpId);
  //
  //       if (userDetailsResponse.isEmpty) {
  //         print('Error fetching user details: $userDetailsResponse');
  //         continue;
  //       }
  //
  //       final int userRate = userDetailsResponse[0]['rate'];
  //       final int userCommission = userDetailsResponse[0]['commission'];
  //       final int userPatti = userDetailsResponse[0]['patti'];
  //
  //       // Step 3: Calculate total amount invested
  //       int totalAmountInvested = _calculateTotalAmountInvested(slotAmount);
  //       totalInvested += totalAmountInvested;
  //
  //       // Step 4: Determine win/loss amount
  //       double winLossAmount = 0;
  //       bool hasWinningSlot = false;
  //       int amountInvested = 0;
  //       int rateWon = 0;
  //       double commissionWon = 0.0;
  //
  //       // Split the slot_amount into individual slots
  //       final slotPairs = slotAmount.split(' / ');
  //       for (var pair in slotPairs) {
  //         final keyValue = pair.split('=');
  //         if (keyValue.length == 2) {
  //           final slotNumber = keyValue[0].trim();
  //           amountInvested = int.parse(keyValue[1].trim());
  //
  //           // Check if slot matches the game result
  //           if (slotNumber == gameResult && userPatti == 0) {
  //             rateWon = amountInvested * userRate;
  //             commissionWon = (userCommission / 100.0) * totalAmountInvested;
  //             winLossAmount += rateWon + commissionWon;
  //             hasWinningSlot = true;
  //           }
  //         }
  //       }
  //
  //       // Calculate loss amount if no winning slot
  //       if (!hasWinningSlot) {
  //         winLossAmount = (userCommission / 100.0) * totalAmountInvested;
  //         commissionWon = winLossAmount;
  //       }
  //
  //       // Calculate the final win/loss balance by deducting total investment
  //       double finalWinLoss = winLossAmount - totalAmountInvested;
  //
  //       // Step 5: Update balance and insert into wallet, update game_play
  //       // if user win
  //       if (winLossAmount > 0 || userCommission > 0) {
  //         // Case: winLossAmount > 0
  //         await supabase.rpc('add_to_balance', params: {
  //           'kp_id': kpId,
  //           'amount': winLossAmount,
  //         });
  //
  //         final walletResponse = await supabase.from('wallet').insert({
  //           'kp_id': kpId,
  //           'game_id': gameId,
  //           'transaction_type': 'Credit',
  //           'amount': winLossAmount,
  //           'timestamp': AppState().currentTime.toIso8601String(),
  //         }).select('id');
  //
  //         await supabase.from('game_play').update({
  //           'result_txn_id': walletResponse[0]['id'],
  //           'is_win': hasWinningSlot,
  //           if (hasWinningSlot) 'pass_amount': amountInvested,
  //           if (hasWinningSlot) 'rate_win': rateWon,
  //           if (userCommission > 0) 'commission_win': commissionWon,
  //           'net_win': finalWinLoss,
  //         }).eq('game_id', gameId).eq('kp_id', kpId);
  //
  //       } else {
  //         // Case: No winning slot and userCommission is 0
  //         await supabase.from('game_play').update({
  //           'is_win': hasWinningSlot,
  //           'net_win': finalWinLoss,
  //         }).eq('game_id', gameId).eq('kp_id', kpId);
  //       }
  //     }
  //     // Step 6: Update the 'game_result' column in the 'games' table after the loop
  //     await supabase.from('games').update({
  //       'game_result': gameResult,
  //       'total_invested': totalInvested,
  //     }).eq('id', gameId);
  //
  //     // Close the loading indicator
  //     Navigator.of(context).pop();
  //
  //     AppState().fetchUsers();
  //     _refreshGames();
  //     // Show success snackbar
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text('Game declared successfully.')),
  //     );
  //
  //   } catch (error) {
  //     // Close the loading indicator
  //     Navigator.of(context).pop();
  //
  //     _refreshGames();
  //     // Show failure snackbar
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Error declaring game: $error')),
  //     );
  //   }
  // }

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

  Future<void> _resetGame(int gameId) async {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to reset game result')),
      );
      return; // Terminate initialization if conditions are not met
    }

    // Show progress indicator while the data is being fetched
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return;

      // Step 1: Fetch users' data related to the game
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

        if (mounted) {
          Navigator.of(context).pop(); // Close the loading indicator
          _refreshGames();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Game reset successfully.')),
          );
        }
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
      final confirmReset = await _showConfirmationDialog(
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
        _refreshGames();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Game reset successfully.')),
        );
      }

    } catch (error) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading indicator
        _refreshGames();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting game: $error')),
        );
      }
    }
  }


  // Future<void> _resetGame0(int gameId) async {
  //   // Show progress indicator while the data is being fetched
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false, // Prevent closing the dialog by tapping outside
  //     builder: (BuildContext context) {
  //       return const Center(
  //         child: CircularProgressIndicator(), // Show a circular progress indicator
  //       );
  //     },
  //   );
  //   try{
  //     // Check for device mismatch
  //     final isMismatch = await AppState().checkDeviceMismatch(context);
  //     if (isMismatch) return; // Halt if there's a mismatch
  //
  //     // Step 1: Fetch users' kp_id and slot_amount
  //     final gameDataResponse = await supabase
  //         .from('game_play')
  //         .select('id, result_txn_id, kp_id, rate_win, commission_win')
  //         .eq('game_id', gameId)
  //         .not('is_win', 'is', 'null');
  //
  //     if (gameDataResponse.isEmpty) {
  //       await supabase.from('games').update({
  //         'game_result': null,
  //         'total_invested': null,
  //       }).eq('id', gameId);
  //
  //       // Close the loading indicator
  //       Navigator.of(context).pop();
  //
  //       _refreshGames();
  //       // Show success snackbar
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('Game resets successfully.')),
  //       );
  //       return;
  //     }
  //
  //     final usersData = gameDataResponse as List;
  //
  //     // Step 2: Iterate through each user and calculate win/loss
  //     for (final user in usersData) {
  //       final int kpId = user['kp_id'];
  //       final int resultTxnId = user['result_txn_id'] ?? 0;
  //       final int rateWin = user['rate_win'] ?? 0;
  //       final double commission = user['commission_win'] ?? 0;
  //       final double totalWinAmount  = rateWin + commission;
  //
  //       // Revert balance by deducting net_win from the user's balance
  //       await supabase.rpc('add_to_balance', params: {
  //         'kp_id': kpId,
  //         'amount': -totalWinAmount , // Deducting the win/loss amount
  //       });
  //
  //       if (resultTxnId != 0) {
  //         // Delete the corresponding wallet transaction
  //         await supabase.from('wallet').delete().eq('id', resultTxnId);
  //       }
  //
  //       // Reset game_play entry for the user
  //       await supabase.from('game_play').update({
  //         'is_win': null,
  //         'pass_amount': null,
  //         'rate_win': null,
  //         'commission_win': null,
  //         'net_win': null,
  //       }).eq('id', user['id']);
  //     }
  //
  //     // Step 3: Reset the game_result in the games table
  //     await supabase.from('games').update({
  //       'game_result': null,
  //       'total_invested': null,
  //     }).eq('id', gameId);
  //
  //     // Close the loading indicator
  //     Navigator.of(context).pop();
  //
  //     AppState().fetchUsers();
  //     _refreshGames();
  //     // Show success snackbar
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text('Game resets successfully.')),
  //     );
  //
  //   } catch (error) {
  //     // Close the loading indicator
  //     Navigator.of(context).pop();
  //
  //     _refreshGames();
  //     // Show failure snackbar
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Error resetting game: $error')),
  //     );
  //   }
  // }


  Future<void> _fetchAndShowSlotAmount(BuildContext context, int gameId, String gameName) async {
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

    try {
      // Fetch all rows of slot_amount for the given game_id
      final response = await supabase
          .from('game_play')
          .select('slot_amount')
          .eq('game_id', gameId); // Remove kp_id condition to fetch all relevant rows

      if (response.isNotEmpty) {
        Map<String, int> combinedSlots = {};
        int totalInvested = 0;  // Initialize the totalInvested counter

        // Iterate through each row and parse the slot_amount
        for (var row in response) {
          String slotAmount = row['slot_amount'];
          totalInvested = _parseAndCombineSlotAmount(slotAmount, combinedSlots, totalInvested);  // Parse and combine slot amounts, update total
        }

        // Format the combined slot amounts into a readable format
        String formattedSlotAmount = _formatCombinedSlotAmount(combinedSlots);
        // Close the progress dialog before showing the result
        Navigator.pop(context);

        // Show the dialog with the combined slot amount and the total
        _showSlotAmountDialog(context, formattedSlotAmount, gameName, totalInvested);
      } else {
        // Close the progress dialog before showing the result
        Navigator.pop(context);
        // Handle the case where no slot_amount was found
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No play data found for this game.'),
            backgroundColor: Colors.red,
          ),
        );
        _refreshGames();
      }
    } catch (e) {
      // Close the progress dialog before showing the result
      Navigator.pop(context);
      // Handle any errors that occurred during the fetch
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching play data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

// Function to parse and combine slot_amount for multiple rows
  int _parseAndCombineSlotAmount(String slotAmountStr, Map<String, int> combinedSlots, int totalInvested) {
    List<String> pairs = slotAmountStr.split(' / ');

    for (String pair in pairs) {
      List<String> parts = pair.split('=');
      if (parts.length == 2) {
        String key = parts[0];
        int value = int.parse(parts[1]);
        combinedSlots[key] = (combinedSlots[key] ?? 0) + value;
        totalInvested += value;  // Accumulate the total invested
      }
    }
    return totalInvested;  // Return the updated total
  }

// Function to format the combined slot amounts into a readable format
  String _formatCombinedSlotAmount(Map<String, int> combinedSlots) {
    final formattedPairs = combinedSlots.entries.map((entry) {
      return '${entry.key}, ( ${entry.value} )'; // Format as 'key, ( value )'
    }).join('\n'); // Join all formatted pairs with a newline

    return formattedPairs;
  }

// Function to show slot_amount in a dialog, including the totalInvested at the bottom
  void _showSlotAmountDialog(BuildContext context, String slotAmount, String gameName, int totalInvested) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(gameName),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slotAmount), // Show the formatted slot_amount
                const SizedBox(height: 16), // Add some space before showing the total
                Text('Total: $totalInvested', style: const TextStyle(fontWeight: FontWeight.bold)),  // Show the total invested amount
              ],
            ),
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
  }



  String formatTimeTo12Hour(String time) {
    try {
      // Parse the 'HH:mm:ss' time string into a DateTime object
      DateTime parsedTime = DateFormat('HH:mm:ss').parse(time);

      // Format the parsed time into 'hh:mm a' format (12-hour time with AM/PM)
      return DateFormat('hh:mm a').format(parsedTime);
    } catch (e) {
      return time;
    }

  }


  @override
  void dispose() {
    // Cancel the timer when the widget is disposed to avoid memory leaks
    _timer.cancel();
    super.dispose();
  }

}
