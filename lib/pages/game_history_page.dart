import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:masterking/main.dart';
import 'package:masterking/models/app_state.dart';

class GameHistoryPage extends StatefulWidget {
  final int kpId;
  final String fullName;

  const GameHistoryPage({
    super.key,
    required this.kpId,
    required this.fullName,
  });

  @override
  _GameHistoryPageState createState() => _GameHistoryPageState();
}

class _GameHistoryPageState extends State<GameHistoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _gameHistory = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchGameHistory();
  }

  Future<void> _fetchGameHistory() async {
    setState(() {
      _loading = true;
    });

    try {
      // Step 1: Fetch data from 'game_play' where 'kp_id' equals widget.kpId
      final gamePlayResponse = await supabase
          .from('game_play')
          .select('id, game_id, is_win')
          .eq('kp_id', widget.kpId);

      if (gamePlayResponse.isEmpty) {
        setState(() {
          _gameHistory = [];
          _loading = false;
        });
        return;
      }

      // final khaiwalResponse = await supabase
      //     .from('khaiwals_players')
      //     .select('khaiwal_id')
      //     .eq('id', widget.kpId)
      //     .maybeSingle();

      // Temporary storage for fetched game history
      List<dynamic> gameHistory = [];

      // Step 2: Fetch details for each game
      for (var game in gamePlayResponse) {
        final gameId = game['game_id'];

        final gamesResponse = await supabase
            .from('games')
            .select('info_id, game_date')
            .eq('id', gameId)
            .maybeSingle();

        if (gamesResponse == null) {
          game['full_game_name'] = 'Game deleted by host';
          game['info_id'] = 0;
          game['game_date'] = '';
        } else {
          final gameInfoResponse = await supabase
              .from('game_info')
              .select('full_game_name')
              .eq('id', gamesResponse['info_id'])
              .maybeSingle();

          game['full_game_name'] = gameInfoResponse?['full_game_name'] ?? 'Game deleted by host';
          game['info_id'] = gamesResponse['info_id'];
          game['game_date'] = gamesResponse['game_date'];
        }

        gameHistory.add({
          'id': game['id'],
          'game_id': game['game_id'],
          'info_id': game['info_id'],
          'khaiwal_id': AppState().khaiwalId,
          'full_game_name': game['full_game_name'],
          'game_date': game['game_date'],
          'is_win': game['is_win'],
        });
      }
      // Sort game history by game_date in descending order (most recent first)
      gameHistory.sort((a, b) {
        final dateA = DateTime.tryParse(a['game_date'] ?? '') ?? DateTime(0);
        final dateB = DateTime.tryParse(b['game_date'] ?? '') ?? DateTime(0);
        return dateB.compareTo(dateA); // Sorts from latest to oldest
      });

      setState(() {
        _gameHistory = gameHistory;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching game history: $e');
      }
    }
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final inProgressGames = _gameHistory.where((game) => game['is_win'] == null).toList();
    final completedGames = _gameHistory.where((game) => game['is_win'] != null).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Games: (${widget.fullName})'),
        elevation: 0.0, // Remove default shadow
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade100, Colors.tealAccent.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "In Progress"),
            Tab(text: "Completed"),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _gameHistory.isEmpty
          ? Center(
        child: Text(
          'No Game History Found',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade600,
          ),
        ),
      )
          : TabBarView(
        controller: _tabController,
        children: [

          inProgressGames.isEmpty ? Center(
            child: Text(
              'No Game is in Progress',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildGameList(inProgressGames),

          completedGames.isEmpty ? Center(
            child: Text(
              'No Completed Games Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildGameList(completedGames),

        ],
      ),
    );
  }

  Widget _buildGameList(List<dynamic> games) {
    return ListView.separated(
      // padding: const EdgeInsets.all(16.0),
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.grey,
      ),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final game = games[index];
        // Format the date if it's not null, otherwise use "Unknown"
        final gameDate = game['game_date'] != null && game['game_date'].trim().isNotEmpty
            ? AppState().formatGameDate(game['game_date'])
            : 'Deleted';

        return GestureDetector(
          onTap: () {
            _showGameDetails(
              context,
              game['id'],
              game['game_id'],
              game['info_id'],
              game['khaiwal_id'],
              game['game_date'],
              game['full_game_name'],
              game['is_win'],
            );
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: game['is_win'] == null ? Colors.orange.shade50 : game['is_win'] == true ? Colors.green.shade50 : Colors.red.shade50,
            child: ListTile(
              title: Text(
                game['full_game_name'],
                style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Date: $gameDate'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    game['is_win'] == null ? Icons.timelapse : (game['is_win'] == true ? Icons.check_circle : Icons.cancel),
                    color: game['is_win'] == null ? Colors.orange : game['is_win'] == true ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    game['is_win'] == null ? 'In Progress' : (game['is_win'] == true ? 'Win' : 'Loss'),
                    style: TextStyle(fontSize: 14.0, color: game['is_win'] == null ? Colors.orange : game['is_win'] == true ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGameDetails(BuildContext context, int id, int gameId, int infoId, String khaiwalId, String gameDate, String fullGameName, bool? isWin) async {
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
    // Fetch data from 'game_play' table
    final gamePlayResponse = await supabase
        .from('game_play')
        .select('play_txn_id, result_txn_id, slot_amount, is_win, pass_amount, rate_win, commission_win, net_win')
        .eq('id', id)
        .maybeSingle();

    if (gamePlayResponse == null) {
      Navigator.pop(context);
      // Close and refresh if no game data found
      await _fetchGameHistory();
      return;
    }

    // Check if 'is_win' in response matches the current game's 'is_win' status
    if (gamePlayResponse['is_win'] != isWin) {
      Navigator.pop(context);
      // Close and refresh if 'is_win' status has changed
      await _fetchGameHistory();
      return;
    }

    final refundDayResponse = await supabase
        .from('khaiwals')
        .select('refund_days')
        .eq('id', khaiwalId)
        .maybeSingle();


    // Temporary storage for fetched data
    final String slotAmountStr = gamePlayResponse['slot_amount'] ?? '';
    final int userInvested = _calculateUserInvested(slotAmountStr);
    final int refundDays = refundDayResponse?['refund_days'];
    String? fullGameNameFetched;
    String? gameResult;
    final now = AppState().currentTime;
    bool isOlderThanRefundDays = false;

    String? playTime;
    if (gamePlayResponse['play_txn_id'] != null && gamePlayResponse['play_txn_id'].toString().isNotEmpty) {
      final playWalletResponse = await supabase
          .from('wallet')
          .select('timestamp')
          .eq('id', gamePlayResponse['play_txn_id'])
          .maybeSingle();

      if (playWalletResponse != null) {
        playTime = _formatTimestamp(playWalletResponse['timestamp']);
      }
    }

    // Check if the game has not been deleted
    if (fullGameName != 'Game deleted by host') {
      // Fetch 'full_game_name' from 'game_info' table where 'id' matches 'game_id'
      final gameInfoResponse = await supabase
          .from('game_info')
          .select('full_game_name')
          .eq('id', infoId)
          .maybeSingle();

      if (gameInfoResponse != null) {
        // Check if the fetched 'full_game_name' matches the current game name
        if (fullGameName != gameInfoResponse['full_game_name']) {
          Navigator.pop(context);
          await _fetchGameHistory();
          return;
        }
        // Store fetched 'full_game_name' for later use
        fullGameNameFetched = gameInfoResponse['full_game_name'];
      }

      // fetch 'game_result' from 'games' table
      final gameResultResponse = await supabase
          .from('games')
          .select('game_result')
          .eq('id', gameId);

      if (gameResultResponse.isNotEmpty) {
        gameResult = gameResultResponse[0]['game_result'];
      } else {
        Navigator.pop(context);
        await _fetchGameHistory();
        return;
      }

      // Parse gameDate and check if it is older than 2 days
      final gameDateParsed = DateTime.parse(gameDate);
      isOlderThanRefundDays = now.difference(gameDateParsed).inDays > refundDays;

    }

    Navigator.pop(context);
    // Display the details in the bottom sheet
    showModalBottomSheet(
      backgroundColor: isWin == null ? Colors.orange.shade50 : isWin == true ? Colors.green.shade50 : Colors.red.shade50,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Game title
                Text(
                  fullGameNameFetched ?? fullGameName,
                  style: TextStyle(
                    fontSize: 22.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[700],
                  ),
                ),
                const SizedBox(height: 5.0),
                // Display other details
                if (gameDate.isNotEmpty) Text('Game Date: ${AppState().formatGameDate(gameDate)}', style: const TextStyle(fontSize: 16.0)),
                const SizedBox(height: 5.0),
                Text(
                  'Played: $slotAmountStr',
                  style: TextStyle(
                    fontSize: 13.0,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 5.0),
                Text('Total Invested: $userInvested', style: const TextStyle(fontSize: 16.0)),
                const SizedBox(height: 10.0),
                // Game status (only shows if not in refund/delete condition)
                if (isWin != null || (!((fullGameName == 'Game deleted by host' && isWin == null) || (isWin == null && isOlderThanRefundDays))))
                  Row(
                    children: [
                      Icon(
                        isWin == true
                            ? Icons.check_circle
                            : isWin == false
                            ? Icons.cancel
                            : Icons.hourglass_top, // Icon for "In Progress" state
                        color: isWin == true
                            ? Colors.green
                            : isWin == false
                            ? Colors.red
                            : Colors.orange, // Color for "In Progress" state
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        isWin == true ? 'Win' : isWin == false ? 'Loss' : 'In Progress',
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                          color: isWin == true
                              ? Colors.green
                              : isWin == false
                              ? Colors.red
                              : Colors.orange, // Text color for "In Progress" state
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10.0),
                // Additional fetched details if they exist
                if (gameResult != null) Text('Game Result: $gameResult', style: const TextStyle(fontSize: 16.0)),
                const SizedBox(height: 5.0),
                if (gamePlayResponse['pass_amount'] != null) Text('Pass Amount: ${gamePlayResponse['pass_amount']}'),
                if (gamePlayResponse['rate_win'] != null) Text('Rate Win: ${gamePlayResponse['rate_win']}'),
                if (gamePlayResponse['commission_win'] != null && gamePlayResponse['commission_win'] != 0) Text('Commission: ${gamePlayResponse['commission_win']}'),
                if (gamePlayResponse['net_win'] != null) Text('Net Win/Loss: ${gamePlayResponse['net_win']}'),
                const SizedBox(height: 5.0),
                if (playTime != null) Text('Play Time: $playTime'),

                // Show "Request Refund" button based on conditions
                if (fullGameName == 'Game deleted by host' && isWin == null) ...[
                  const SizedBox(height: 10.0),
                  Text(
                    'This game has been deleted by host without declaring the result.',
                    style: TextStyle(
                      fontSize: 14.0,
                      color: Colors.red[600],
                    ),
                  ),
                  const SizedBox(height: 10.0),

                  // Row to align buttons horizontally
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Delete Record Button
                      ElevatedButton(
                        onPressed: () {
                          // _showDeleteConfirmationDialog(context, id);
                          Navigator.pop(context);
                        },
                        // style: ElevatedButton.styleFrom(
                          // backgroundColor: Colors.red,
                        // ),
                        child: const Text('Ok'),
                      ),

                      // Request Refund Button
                      ElevatedButton(
                        onPressed: () {
                          // Handle refund request action here
                          _processRefund(id, widget.kpId, gameId, userInvested, widget.fullName, fullGameNameFetched, gameDate, slotAmountStr);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: const Text('Give Refund'),
                      ),
                    ],
                  ),
                ] else if (isWin == null && isOlderThanRefundDays) ...[
                  const SizedBox(height: 10.0),
                  Text(
                    refundDays == 0
                        ? 'The game has passed its play date ($gameDate) and game is still in progress.'
                        : 'This game is still in progress and has exceeded $refundDays ${refundDays > 1 ? 'days' : 'day'} since the play date.',
                    style: TextStyle(
                      fontSize: 14.0,
                      color: Colors.red[600],
                    ),
                  ),

                  const SizedBox(height: 10.0),

                  // Row to align buttons horizontally
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Delete Record Button
                      ElevatedButton(
                        onPressed: () {
                          // _showDeleteConfirmationDialog(context, id);
                          Navigator.pop(context);
                        },
                        // style: ElevatedButton.styleFrom(
                        //   backgroundColor: Colors.red,
                        // ),
                        child: const Text('Ok'),
                      ),

                      // Request Refund Button
                      ElevatedButton(
                        onPressed: () {
                          // Handle refund request action here
                          _processRefund(id, widget.kpId, gameId, userInvested, widget.fullName, fullGameNameFetched, gameDate, slotAmountStr);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: const Text('Give Refund'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _processRefund(int gamePlayId, int kpId, int gameId, int userInvested, String fullName, String? fullGameName, String? gameDate, String slotAmount) async {
    // Declare prefilled text and set up the note controller
    final prefilledText = '${fullGameName ?? 'Deleted'} - ${gameDate ?? ''}\nPlayed: $slotAmount\nRefunded by host: ';
    TextEditingController noteController = TextEditingController();

    // Show the refund confirmation dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Refund'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Do you want to refund user ($fullName)?'),
                const SizedBox(height: 10),
                // Display prefilled text as a separate, read-only Text widget
                Text(
                  prefilledText,
                  style: const TextStyle(color: Colors.black54), // Optional style for read-only text
                ),
                const SizedBox(height: 10),
                // TextField for the user to add additional notes
                TextField(
                  controller: noteController,
                  maxLines: null, // Allows the TextField to expand to multiple lines
                  decoration: const InputDecoration(
                    labelText: 'Additional Note',
                    alignLabelWithHint: true,
                  ),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(100),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // Combine prefilled text with user input and pass to refund function
                final fullNote = '$prefilledText${noteController.text.trim()}';

                Navigator.of(context).pop(); // Close the dialog
                Navigator.of(context).pop(); // Close the dialog
                _refundUser(gamePlayId, kpId, gameId, userInvested, fullName, fullNote); // Pass combined note
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }



  Future<void> _refundUser(int gamePlayId, int kpId, int gameId, int userInvested, String fullName, String note) async {
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
      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      // Step 2: Call the `process_refund` RPC function
      final result = await supabase.rpc('process_refund', params: {
        '_kp_id': kpId,
        '_game_id': gameId,
        '_timestamp': AppState().currentTime.toIso8601String(), // Use current timestamp
        '_refund_note': note.isNotEmpty ? note : 'Refunded by host',
      });

      // Step 3: Handle the result of the function
      if (result == 'Refund processed successfully.') {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund processed successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (result == 'Error: No data found to refund.') {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No data found to refund.')),
        );
      } else if (result == 'Error: Refund not allowed. Game result has been declared.') {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refund is not allowed. Game result has been declared.')),
        );
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error processing refund.')),
        );
      }

      // Step 4: Refresh data after handling
      await _fetchGameHistory();
    } catch (e) {
      Navigator.pop(context);
      await _fetchGameHistory();
      // Handle unexpected errors
      if (kDebugMode) {
        print('Error processing refund: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred.')),
      );
    }
  }


  void _showDeleteConfirmationDialog(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete Record'),
          content: const Text(
            'Are you sure you want to delete this incomplete game record? This action is irreversible, and you will lose the ability to get a refund for this game.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // Proceed with the deletion
                Navigator.of(context).pop(); // Close the dialog
                Navigator.of(context).pop(); // Close the dialog
                _deleteGameRecord(id); // Call the method to delete the record
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }


// Method to delete the game record
  void _deleteGameRecord(int id) async {
    await supabase.from('game_play').delete().eq('id', id);
    await _fetchGameHistory(); // Refresh the game history after deletion
  }


// Helper function to calculate total invested amount
  int _calculateUserInvested(String slotAmountStr) {
    int userInvested = 0;
    List<String> pairs = slotAmountStr.split(' / ');
    for (String pair in pairs) {
      List<String> parts = pair.split('=');
      if (parts.length == 2) {
        int amount = int.parse(parts[1]);
        userInvested += amount;
      }
    }
    return userInvested;
  }

  String _formatTimestamp(String timestamp) {
    // Parse the timestamp string to DateTime object
    DateTime parsedTimestamp = DateTime.parse(timestamp);
    // Format the DateTime to the desired format
    return DateFormat('yyyy-MM-dd \'at\' hh:mm a').format(parsedTimestamp);
  }


  @override
  void dispose() {
    _tabController.dispose(); // Dispose of TabController to free resources
    super.dispose();
  }

}
