import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:masterking/models/app_state.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';


class PlayPage extends StatefulWidget {
  final int gameId;
  final int infoId;
  final String fullGameName;
  final String gameDate;
  final DateTime closeTime;
  final DateTime lastBigPlayTime;
  final int lastBigPlayMinute;
  final bool isDayBefore;

  const PlayPage({
    super.key,
    required this.gameId,
    required this.infoId,
    required this.fullGameName,
    required this.gameDate,
    required this.closeTime,
    required this.lastBigPlayTime,
    required this.lastBigPlayMinute,
    required this.isDayBefore
  });


  @override
  _PlayPageState createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {

  final TextEditingController cutAmountController = TextEditingController();
  final TextEditingController limitCheckController = TextEditingController();

  List<Map<String, dynamic>> slotData = [];
  // String? _selectedFullName = 'All Users'; // To store the currently selected full_name
  int? _selectedKpId;

  Map<int, TextEditingController> editTextControllers = {};
  Map<String, int> originalValues = {}; // Map to store original slot values


  int _selectedRate = AppState().defaultRate; // Default rate
  int totalAmount = 0;
  final ValueNotifier<int> _finalAmount = ValueNotifier<int>(0);
  final ValueNotifier<int> _matchCount = ValueNotifier<int>(0);
  final ValueNotifier<String> riskProfitText = ValueNotifier<String>('');
  final ValueNotifier<String> _belowCount = ValueNotifier<String>('');
  final ValueNotifier<String> _aboveCount = ValueNotifier<String>('');

  late int existingId;

  Timer? _closeTimeChecker;
  Timer? _lastBigPlayTimeChecker;

  late DateTime gameCloseTime;
  late DateTime lastBigPlayTime;

  final ValueNotifier<Duration> remainingCloseTime = ValueNotifier<Duration>(const Duration());
  final ValueNotifier<String> countdownCloseTimeText = ValueNotifier<String>('');
  final ValueNotifier<Duration> remainingLastBigPlayTime = ValueNotifier<Duration>(const Duration());
  final ValueNotifier<String> countdownLastBigPlayTimeText = ValueNotifier<String>('');

  late int? limitValue;
  late int? cutValue;

  bool loading = false;

  @override
  void initState() {
    super.initState();
    // _setStatusBarColor(Colors.purple); // Set your desired status bar color
    _initializeTextControllers(); // Initialize the controllers

    _parseCloseTime();
    _parseLastBigPlayTime();

    if (AppState().currentTime.isBefore(gameCloseTime)) {
      _startCloseTimeCheck();
      _startLastBigPlayTimeCheck();
    }

    _refreshData();
    // Add a listener to cutAmountController to adjust each slot amount in real-time
    cutAmountController.addListener(_adjustSlotAmounts);
    limitCheckController.addListener(_checkLimit);
    _fetchLimitCutValue();
  }

  Future<void> _refreshTime() async {
    await AppState().refreshTime();
  }

  Future<void> _refreshData() async {
    setState(() {
      loading = true;
    });
    await _refreshTime();
    // Call the fetchSlotData() method to refresh the slot data
    await fetchSlotData();
    setState(() {
      loading = false;
    });
  }

  void _initializeTextControllers() {
    for (int i = 0; i <= 99; i++) {
      editTextControllers[i] = TextEditingController();
      // 2. Add listener to each controller to update total when text changes
      editTextControllers[i]!.addListener(_calculateTotalAmount);
    }
  }
  void _calculateTotalAmount() {
    int total = 0;
    for (int i = 0; i <= 99; i++) {
      final text = editTextControllers[i]?.text ?? '';
      if (text.isNotEmpty) {
        total += int.tryParse(text) ?? 0;
      }
    }
    // 3. Update the total amount
    _finalAmount.value = total;
  }

  void _parseCloseTime() {
    // Assuming the closeTime is in "HH:mm:ss" format
    try {
      // Subtract 5 seconds
      gameCloseTime = widget.closeTime;
      gameCloseTime = gameCloseTime.subtract(const Duration(seconds: 5));
      if (widget.isDayBefore) {
        gameCloseTime = gameCloseTime.subtract(const Duration(minutes: 1440));
      }

    } catch (e) {
      if (kDebugMode) {
        print('Error parsing close time: $e');
      }
    }
  }
  // Parse last big play time
  void _parseLastBigPlayTime() {
    try {

      // Check widget.lastBigPlayTime and subtract accordingly
      if (widget.lastBigPlayMinute != -1 && widget.lastBigPlayMinute != 0 && !widget.lastBigPlayTime.isAfter(widget.closeTime)) {
        lastBigPlayTime = widget.lastBigPlayTime;
        // Subtract the editMinutes from lastEditTime
        lastBigPlayTime = lastBigPlayTime.subtract(const Duration(seconds: 5));
      } else {
        lastBigPlayTime = widget.closeTime;
        // If editMinutes is -1 or 0, subtract 5 seconds
        lastBigPlayTime = lastBigPlayTime.subtract(const Duration(seconds: 5));
      }
      if (widget.isDayBefore){
        lastBigPlayTime = lastBigPlayTime.subtract(const Duration(minutes: 1440));
      }
      // print('Parsed last big play time: $lastBigPlayTime');
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing last big play time: $e');
      }
    }
  }
  // Countdown for close time
  void _startCloseTimeCheck() {
    _closeTimeChecker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = AppState().currentTime; // Use the current time from AppState
      if (now.isAfter(gameCloseTime)) {
        timer.cancel(); // Stop the timer when the close time is over
        // _showTimeOverDialog(); to need to display for MasterKing app
        _refreshData();
      } else {
        Duration timeRemaining = gameCloseTime.difference(now);
        remainingCloseTime.value = timeRemaining;
        countdownCloseTimeText.value = _formatDuration(timeRemaining);
      }
    });
  }
  // Countdown for last big play time
  void _startLastBigPlayTimeCheck() {
    if (widget.lastBigPlayMinute == -1){
      return;
    }
    _lastBigPlayTimeChecker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = AppState().currentTime; // Use the current time from AppState
      if (now.isAfter(lastBigPlayTime)) {
        timer.cancel(); // Stop the timer when the last big play time is over
        // exceededBigPlayLimit = true;
        _refreshData();
      } else {
        Duration timeRemaining = lastBigPlayTime.difference(now);
        remainingLastBigPlayTime.value = timeRemaining;
        countdownLastBigPlayTimeText.value = _formatDuration(timeRemaining);

        // setState(() {
        //   remainingLastBigPlayTime = lastBigPlayTime.difference(now);
        //   countdownLastBigPlayTimeText = _formatDuration(remainingLastBigPlayTime);
        // });
      }
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> fetchSlotData() async {
    // Step 6: Set dropdown to 'All Users' after refund
    setState(() {
      _selectedKpId = null; // Set dropdown to 'All Users'
      slotData.clear();
      originalValues.clear();
      totalAmount = 0;
    });

    _clearAllTextFields();

    final response = await supabase
        .rpc('fetch_slot_amount_and_full_name', params: {'game_id_input': widget.gameId}); // Use widget.gameId for the actual game ID

    if (response.isNotEmpty) {

      setState(() {
        slotData = List<Map<String, dynamic>>.from(response);
        String combinedSlotAmount = _combineAllUsersSlotAmount();
        _parseAndSetSlotAmount(combinedSlotAmount);
        totalAmount = _calculateUserInvested(combinedSlotAmount);

        // Automatically populate slot amounts for "All Users" once the data is fetched
        // if (_selectedFullName == 'All Users') {
        //   String combinedSlotAmount = _combineAllUsersSlotAmount();
        //   _parseAndSetSlotAmount(combinedSlotAmount);
        // } else if (_selectedKpId != null) {
        //   // Find the corresponding slot amount using the selected kp_id
        //   var selectedUser = slotData.firstWhere(
        //           (user) => user['kp_id'] == _selectedKpId, orElse: () => <String, dynamic>{}); // Return an empty map if no match found
        //
        //   if (selectedUser.isNotEmpty && selectedUser['slot_amount'] != null) {
        //     // Parse and set slot amount for the selected user
        //     _parseAndSetSlotAmount(selectedUser['slot_amount']);
        //   }
        // }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No played games found yet")),
      );
    }
    _addMissingNumbersToOriginalValues();
    _checkLimit();
    _adjustSlotAmounts();
    await AppState().checkGamePlayExistence();
    AppState().notifyListeners();
  }

  void _parseAndSetSlotAmount(String slotAmountStr) {
    List<String> pairs = slotAmountStr.split(' / ');
    for (String pair in pairs) {
      List<String> parts = pair.split('=');
      if (parts.length == 2) {
        String slotNumber = parts[0];
        int amount = int.parse(parts[1]);

        originalValues[slotNumber] = amount; // Store original value
        editTextControllers[int.parse(slotNumber)]?.text = amount.toString();
      }
    }
  }
  String _combineAllUsersSlotAmount() {
    Map<String, int> combinedAmounts = {}; // To store the combined slot amounts

    for (var user in slotData) {
      String slotAmountStr = user['slot_amount'];
      List<String> pairs = slotAmountStr.split(' / ');

      for (String pair in pairs) {
        List<String> parts = pair.split('=');
        if (parts.length == 2) {
          String slotNumber = parts[0]; // Slot number
          int amount = int.parse(parts[1]); // Slot amount

          // If the slot number already exists, sum the amounts
          if (combinedAmounts.containsKey(slotNumber)) {
            combinedAmounts[slotNumber] = combinedAmounts[slotNumber]! + amount;
          } else {
            combinedAmounts[slotNumber] = amount;
          }
        }
      }
    }
    // Convert combinedAmounts map to the same string format as slotAmountStr (e.g., "1=100 / 2=200")
    return combinedAmounts.entries.map((entry) => '${entry.key}=${entry.value}').join(' / ');
  }

  void _addMissingNumbersToOriginalValues() {
    // Loop through numbers from 0 to 99
    for (int i = 0; i < 100; i++) {
      // Format number as a two-digit string
      String formattedNumber = i.toString().padLeft(2, '0');

      // Check if the formatted number is not in originalValues
      if (!originalValues.containsKey(formattedNumber)) {
        // Add the missing number to originalValues with a value of 0
        originalValues[formattedNumber] = 0;
      }
    }

    // Sort the originalValues map by keys to ensure sequence from '00' to '99'
    var sortedEntries = originalValues.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    originalValues
      ..clear()
      ..addEntries(sortedEntries);

  }

  Future<void> _checkLimit() async {
    // Parse the entered limit from the limitCheckController
    int? limitValue = int.tryParse(limitCheckController.text);

    // If the limitValue is null (e.g., invalid input), reset counts and return early
    if (limitValue == null) {
      _belowCount.value = '';
      _aboveCount.value = '';
      return;
    }

    int belowCounted = 0;
    int aboveCounted = 0;

    // Loop through each entry in originalValues to compare values
    originalValues.forEach((key, value) {
      if (value > limitValue) {
        aboveCounted++;
      } else {
        belowCounted++;
      }
    });

    // Update the ValueNotifiers with the counts, setting them to '' if the count is zero
    _belowCount.value = belowCounted > 0 ? '$belowCounted <' : '';
    _aboveCount.value = aboveCounted > 0 ? '> $aboveCounted' : '';
  }

  Future<void> _fetchLimitCutValue() async {
    try {
      final response = await supabase
          .from('games')
          .select('limit_check, cut_amount')
          .eq('id', widget.gameId)
          .maybeSingle(); // Fetch a single row

      if (response != null) {
        setState(() {
          limitValue = response['limit_check'];
          limitCheckController.text = limitValue?.toString() ?? ''; // Set the controller value

          cutValue = response['cut_amount'];
          cutAmountController.text = cutValue?.toString() ?? '';
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Exception while fetching limit_check: $e');
      }
    }
  }


  // Method to adjust slot amounts based on the 'Cut amount' value
  void _adjustSlotAmounts() {
    String cutAmt = cutAmountController.text;
    int cutAmount = int.tryParse(cutAmt) ?? 0;

    // Reset all values to original first
    for (var entry in originalValues.entries) {
      int index = int.parse(entry.key);
      int originalAmount = entry.value;
      int adjustedAmount = originalAmount - cutAmount;

      // If adjusted amount is <= 0, display empty; otherwise, display the adjusted amount
      editTextControllers[index]?.text = adjustedAmount > 0 ? adjustedAmount.toString() : '';
    }

    // if (cutAmt.isNotEmpty && cutAmount == 0) {
    //   // Calculate missing numbers count if cutAmount is 0
    //   List<String> missingNumbers = _findMissingNumbers();
    //   _matchCount.value = missingNumbers.length;
    // } else {
    //   // Count how many values in originalValues match the cutAmount
    //   _matchCount.value = originalValues.values.where((value) => value == cutAmount).length;
    // }

    _matchCount.value = originalValues.values.where((value) => value == int.tryParse(cutAmt)).length;

    _updateRiskProfit();
  }

  void _updateRiskProfit() {
    int cuttingAmount = int.tryParse(cutAmountController.text) ?? 0;
    int rate = _selectedRate;
    int cuttedAmount = totalAmount - _finalAmount.value;

    int originalValue = originalValues.values.isNotEmpty
        ? originalValues.values.reduce((a, b) => a > b ? a : b)
        : 0;

    int riskProfit;
    if (rate == 0) {
      riskProfit = 0;
    } else if (cuttingAmount > originalValue) {
      riskProfit = (originalValue * rate) - cuttedAmount;
    } else {
      riskProfit = (cuttingAmount * rate) - cuttedAmount;
    }

    // Update the notifier value to avoid setState
    if (rate == 0) {
      riskProfitText.value = '';
    } else {
      riskProfitText.value = riskProfit < 0
          ? "Profit: ${riskProfit.abs()}"
          : "Risk: $riskProfit";
    }
  }


  // void _setStatusBarColor(Color color) {
  //   SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
  //     statusBarColor: color, // Set the status bar color
  //   ));
  // }


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Detect taps outside of focused widgets
      onTap: () {
        FocusScope.of(context).unfocus(); // Remove focus from any text field
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.teal.shade100,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // Aligns text to the start
            children: [
              Text(
                widget.fullGameName,
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                AppState().formatGameDate(widget.gameDate),
                style: const TextStyle(fontSize: 14, color: Colors.blueGrey), // Subtitle style
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Use ValueListenableBuilder to listen to countdownCloseTimeText changes
                    ValueListenableBuilder<String>(
                      valueListenable: countdownCloseTimeText,
                      builder: (context, text, child) {
                        return Text(
                          text.isNotEmpty ? "Close: $text" : "Time Over",
                          style: const TextStyle(fontSize: 14),
                        );
                      },
                    ),
                    // Conditionally show the Last Big Play timer if lastBigPlayMinute != -1
                    if (widget.lastBigPlayMinute != -1)
                      ValueListenableBuilder<String>(
                        valueListenable: countdownLastBigPlayTimeText,
                        builder: (context, text, child) {
                          return Text(
                            text.isNotEmpty ? "Big Play: $text" : "Big Play Time Over",
                            style: const TextStyle(fontSize: 14),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshData, // Call your refresh method here
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollability even when content is smaller
              child: Column(
                children: [
                  const SizedBox(height: 8.0),
                  Column(
                    children: _buildNumberInputs(),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildAdditionalComponents(), // Add additional components here
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  List<Widget> _buildNumberInputs() {
    List<Widget> rows = [];
    for (int i = 0; i < 10; i++) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5), // Reduce vertical padding
          child: Row(
            children: _buildRow(i),
          ),
        ),
      );
    }
    return rows;
  }

  List<Widget> _buildRow(int start) {
    List<Widget> row = [];
    for (int i = 0; i < 10; i++) {
      int number = start + i * 10;
      row.add(
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(1.0), // Reduce padding
            child: TextField(
              controller: editTextControllers[number],
              readOnly: true, // Make the TextField non-editable
              decoration: InputDecoration(
                labelText: number.toString().padLeft(2, '0'),
                labelStyle: const TextStyle(fontSize: 16, color: Colors.blue,), // Reduce label text size
                contentPadding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 0.0), // Reduce content padding
                border: const OutlineInputBorder(),
                isDense: true, // Make the input field more compact
                floatingLabelBehavior: FloatingLabelBehavior.always, // Ensure label is always visible
                floatingLabelAlignment: FloatingLabelAlignment.center,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly, // Allow only digits
                LengthLimitingTextInputFormatter(9), // Limit input to 9 digits
              ],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
              ) // Text color changes based on theme), // Reduce font size
            ),
          ),
        ),
      );
    }
    return row;
  }


  Widget _buildAdditionalComponents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Amt: $totalAmount'),

            // Row containing _belowCount, limitCheckController, and _aboveCount
            Row(
              children: [
                // Below Count
                GestureDetector(
                  onTap: () {
                    _showBelowNumbersDialog();
                  },
                  child: ValueListenableBuilder<String>(
                    valueListenable: _belowCount,
                    builder: (context, value, child) {
                      return Text(value);
                    },
                  ),
                ),

                // Spacing between _belowCount and limitCheckController
                const SizedBox(width: 5.0),

                // Limit Check Text Field
                SizedBox(
                  width: 31, // Set width to fit up to 4-digit numbers comfortably
                  child: TextField(
                    controller: limitCheckController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(10), // Limit to 10 digits
                      FilteringTextInputFormatter.digitsOnly, // Allow only digits
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true, // Reduce padding
                      contentPadding: EdgeInsets.zero, // Further reduce padding
                      hintText: 'Limit', // Add the hint text here
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    onChanged: (value) {
                      // print("Entered value: $value");
                      AppState().scheduleLimitUpdate(widget.gameId, int.tryParse(limitCheckController.text));
                    },
                  ),
                ),

                // Spacing between limitCheckController and _aboveCount
                const SizedBox(width: 5.0),

                // Above Count
                GestureDetector(
                  onTap: () {
                    _showAboveNumbersDialog();
                  },
                  child: ValueListenableBuilder<String>(
                    valueListenable: _aboveCount,
                    builder: (context, value, child) {
                      return Text(value);
                    },
                  ),
                ),
              ],
            ),

            // Final Amount Text with ValueListenableBuilder
            ValueListenableBuilder<int>(
              valueListenable: _finalAmount,
              builder: (context, finalAmount, child) {
                return Text('Final Amt: $finalAmount');
              },
            ),
          ],
        ),
        const SizedBox(height: 10.0),
        // Add the dropdown spinner here
        Row(
          children: [
            // Expanded to make the dropdown take available space
            Expanded(
              child: DropdownButton<int?>(
                value: _selectedKpId, // Track selected user by kp_id (can be null for 'All Users')
                onChanged: (int? newValue) {
                  setState(() {
                    _selectedKpId = newValue;
                  });
                },
                items: [
                  // Add "All Users" option as the first item
                  const DropdownMenuItem<int?>(
                    value: null, // Use null for "All Users"
                    child: Text('All Users'), // Show total invested for All Users
                  ),
                  // Map slotData to DropdownMenuItems, showing full_name but using kp_id internally
                  ...slotData.map<DropdownMenuItem<int?>>((data) {
                    // Calculate total invested for each user
                    int userInvested = _calculateUserInvested(data['slot_amount']);
                    return DropdownMenuItem<int?>(
                      value: data['kp_id'], // Use kp_id as the value
                      child: Text('${data['full_name']} (Amt: $userInvested)'), // Display full_name
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(width: 8), // Add some space between the dropdown and the refund button
            // View button
            ElevatedButton(
              onPressed: _selectedKpId != null
                  ? () {
                // Fetch selected user data based on kp_id
                var selectedUser = slotData.firstWhere((user) => user['kp_id'] == _selectedKpId);
                _showSlotAmountDialog(context, selectedUser['slot_amount'], selectedUser['full_name']!);
              }
                  : null, // Disable the button if no user is selected
              child: const Text('View'),
            ),
          ],
        ),
        const SizedBox(height: 15.0),

        // Add the cut amount row here
        Row(
          children: [
            // Info icon with a GestureDetector
            GestureDetector(
              onTap: () {
                _showInfoDialog(
                  "Rate Information",
                  "By setting the rate, you can estimate the level of risk you're taking after cutting. "
                      "This value provides a close-to-accurate measure of potential risk, but keep in mind that it’s not exact.",
                );
              },
              child: const Icon(Icons.info_outline, size: 18, color: Colors.grey), // Info icon
            ),

            const SizedBox(width: 5),

            // Rate label and picker
            const Text("Rate 1 x = "),
            GestureDetector(
              onTap: () async {
                // Open the picker dialog and get the selected value
                final pickedRate = await _showRatePickerDialog("Rate", _selectedRate);
                if (pickedRate != null) {
                  setState(() {
                    _selectedRate = pickedRate; // Update _selectedRate with the selected value
                  });
                  _updateRiskProfit();
                }
              },
              child: Text(
                "$_selectedRate", // Show current selected rate
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),

            const SizedBox(width: 5),

            // Edit icon for rate
            GestureDetector(
              onTap: () async {
                final pickedRate = await _showRatePickerDialog("Rate", _selectedRate);
                if (pickedRate != null) {
                  setState(() {
                    _selectedRate = pickedRate;
                  });
                  _updateRiskProfit();
                }
              },
              child: const Icon(Icons.edit, size: 18), // Edit icon after the rate text
            ),

            const Spacer(), // Pushes the remaining widgets to the right side

            // Matches text
            GestureDetector(
              onTap: () {
                _showMatchedValuesDialog();
              },
              child: ValueListenableBuilder<int>(
                valueListenable: _matchCount,
                builder: (context, count, child) {
                  return Text(count > 1 ? "$count Matches =" : "$count Match =");
                },
              ),
            ),

            const SizedBox(width: 10.0),

            // Fixed-width 'Cut amount' text field
            SizedBox(
              width: 100, // Adjust width as needed
              height: 50, // Adjust width as needed
              child: TextField(
                controller: cutAmountController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(13), // Limit to 13 digits
                  FilteringTextInputFormatter.digitsOnly, // Allow only digits
                ],
                decoration: const InputDecoration(
                  labelText: 'Cut amount',
                  floatingLabelBehavior: FloatingLabelBehavior.always, // Makes label float by default
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  // Calculate totalCutAmount and finalAmount
                  int? finalAmount = _finalAmount.value; // Accessing the ValueNotifier's current value
                  int? totalCutAmount = totalAmount - finalAmount;

                  // Trigger match count update
                  _adjustSlotAmounts(); // Ensure this updates match count when the cut amount changes

                  AppState().scheduleCutUpdate(widget.gameId, int.tryParse(cutAmountController.text), totalCutAmount, finalAmount);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10.0),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,

          children: [
            Row(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: riskProfitText,
                  builder: (context, value, child) {
                    return Text(value);
                  },
                ),
              ],
            ),


            const SizedBox(height: 10.0),

            // Display the Total Cut Amount
            ValueListenableBuilder<int>(
              valueListenable: _finalAmount,
              builder: (context, finalAmount, child) {
                int totalCutAmount = totalAmount - finalAmount; // Calculate total cut amount
                return Text("Total Cut Amount: $totalCutAmount");
              },
            ),
          ],
        ),

        const SizedBox(height: 20.0),

        // Row for Copy and Share Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton.icon(
              onPressed: () => _onCopyFinalCodePressed(context),
              icon: const Icon(Icons.copy),
              label: const Text('Copy Final Code'),
            ),

            ElevatedButton.icon(
              onPressed: () => _onShareFinalCodePressed(context),
              icon: const Icon(Icons.share, size: 18), // Share icon
              label: const Text('Share Final Code'),
            ),
          ],
        ),
        const SizedBox(height: 10.0),

        // Share Final QR Button on the Next Line, Right Aligned
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () => _onShareFinalQrPressed(context),
            icon: const Icon(Icons.qr_code, size: 18), // QR code icon
            label: const Text('Share Final QR'),
          ),
        ),
      ],
    );
  }

  void _showBelowNumbersDialog() {
    // Filter numbers with values less than or equal to the limit
    int? limitValue = int.tryParse(limitCheckController.text);
    if (limitValue == null) return;

    List<MapEntry<String, int>> belowValues = originalValues.entries
        .where((entry) => entry.value <= limitValue)
        .toList();

    int count = belowValues.length;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$count Numbers Below or Equal to Limit: $limitValue'),
          content: SingleChildScrollView(
            child: Text(_formatEntries(belowValues)),
          ),
          actions: [
            // Row to arrange buttons horizontally
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // space out buttons
              children: [
                Flexible(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showCopyFormatDialog(belowValues, skipZero: false, isCopyNoOnly: true); // Copy No. only
                    },
                    child: const Text("Copy No. only", style: TextStyle(fontSize: 12)), // Adjust font size for better fit
                  ),
                ),
                const SizedBox(width: 8), // Space between buttons
                Flexible(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showCopyFormatDialog(belowValues, skipZero: true, isCopyNoOnly: false); // Copy & Skip (0)
                    },
                    child: const Text("Copy & Skip (0)", style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8), // Space between buttons
                Flexible(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showCopyFormatDialog(belowValues, isCopyNoOnly: false); // Opens format options dialog directly
                    },
                    child: const Text("Copy", style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showAboveNumbersDialog() {
    // Filter numbers with values greater than the limit
    int? limitValue = int.tryParse(limitCheckController.text);
    if (limitValue == null) return;

    List<MapEntry<String, int>> aboveValues = originalValues.entries
        .where((entry) => entry.value > limitValue)
        .toList();

    int count = aboveValues.length;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$count Numbers Above Limit: $limitValue'),
          content: SingleChildScrollView(
            child: Text(_formatEntries(aboveValues)),
          ),
          actions: [
            // Row to arrange buttons horizontally
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // space out buttons
              children: [
                Flexible(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showCopyFormatDialog(aboveValues, skipZero: false, isCopyNoOnly: true); // Copy No. only
                    },
                    child: const Text("Copy No. only", style: TextStyle(fontSize: 12)), // Adjust font size for better fit
                  ),
                ),
                const SizedBox(width: 8), // Space between buttons
                Flexible(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // Subtract limitValue from each value in aboveValues
                      List<MapEntry<String, int>> trimmedValues = aboveValues.map((entry) {
                        int trimmedValue = entry.value - limitValue;
                        return MapEntry(entry.key, trimmedValue);
                      }).toList();
                      // Show copy format dialog with trimmed values
                      _showCopyFormatDialog(trimmedValues, skipZero: false, isCopyNoOnly: false);
                    },
                    child: const Text("Copy Trimmed", style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8), // Space between buttons
                Flexible(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showCopyFormatDialog(aboveValues, isCopyNoOnly: false); // Opens format options dialog directly
                    },
                    child: const Text("Copy", style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }


  void _showCopyFormatDialog(List<MapEntry<String, int>> belowValues, {bool skipZero = false, bool isCopyNoOnly = false}) {
    List<MapEntry<String, int>> filteredValues = skipZero
        ? belowValues.where((entry) => entry.value != 0).toList()
        : belowValues;

    // Show the format dialog
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose Copy Format'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Vertically ┇'),
                onTap: () {
                  String textToCopy = isCopyNoOnly
                      ? _formatVerticalKeys(filteredValues)  // Copy only numbers
                      : _formatVertical(filteredValues);     // Copy key-value pairs
                  copyToClipboard(textToCopy);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Numbers copied to clipboard Vertically ┇'),
                  ));
                },
              ),
              ListTile(
                title: const Text('Shuffled Vertically ┇'),
                onTap: () {
                  String shuffledText = isCopyNoOnly
                      ? shuffleNumbersVertically(_formatVerticalKeys(filteredValues))
                      : shuffleNumbersVertically(_formatVertical(filteredValues));
                  copyToClipboard(shuffledText);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Numbers copied to clipboard Shuffled Vertically ┇'),
                  ));
                },
              ),
              ListTile(
                title: const Text('Horizontally ⁃⁃⁃'),
                onTap: () {
                  String textToCopy = isCopyNoOnly
                      ? _formatHorizontalKeys(filteredValues)
                      : _formatHorizontal(filteredValues);
                  copyToClipboard(textToCopy);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Numbers copied to clipboard Horizontally ⁃⁃⁃'),
                  ));
                },
              ),
              ListTile(
                title: const Text('Shuffled Horizontally ⁃⁃⁃'),
                onTap: () {
                  String shuffledText = isCopyNoOnly
                      ? shuffleOnlyNumbersHorizontally(_formatHorizontalKeys(filteredValues))
                      : shuffleNumbersHorizontally(_formatHorizontal(filteredValues));
                  copyToClipboard(shuffledText);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Numbers copied to clipboard Shuffled Horizontally ⁃⁃⁃'),
                  ));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatVertical(List<MapEntry<String, int>> entries) {
    return entries.map((e) => '${e.key}, ( ${e.value} )').join('\n');
  }

  String _formatHorizontal(List<MapEntry<String, int>> entries) {
    return entries.map((e) => '${e.key}=${e.value}').join(' / ');
  }

  // void _showAboveNumbersDialog() {
  //   // Filter numbers with values greater than the limit
  //   int? limitValue = int.tryParse(limitCheckController.text);
  //   if (limitValue == null) return;
  //
  //   List<MapEntry<String, int>> aboveValues = originalValues.entries
  //       .where((entry) => entry.value > limitValue)
  //       .toList();
  //
  //   int count = aboveValues.length;
  //
  //   showDialog(
  //     context: context,
  //     builder: (context) {
  //       return AlertDialog(
  //         title: Text('$count Numbers Above Limit: $limitValue'),
  //         content: SingleChildScrollView(
  //           child: Text(_formatEntries(aboveValues)),
  //         ),
  //         actions: [
  //           TextButton(
  //             onPressed: () => Navigator.of(context).pop(),
  //             child: const Text("Close"),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }

  String _formatEntries(List<MapEntry<String, int>> entries) {
    // Format each entry as 'key, ( value )' and join with a newline
    return entries.map((entry) => '${entry.key}, ( ${entry.value} )').join('\n');
  }

  // Helper method to format only the keys (numbers)
  String _formatVerticalKeys(List<MapEntry<String, int>> entries) {
    return entries.map((e) => e.key).join('\n');
  }

  String _formatHorizontalKeys(List<MapEntry<String, int>> entries) {
    return entries.map((e) => e.key).join(' ');
  }




  void _processRefund(int selectedKpId, String slotAmount) async {
    var user = slotData.firstWhere((user) => user['kp_id'] == selectedKpId);

    // Prefilled text with game details
    final prefilledText = '${widget.fullGameName} - ${widget.gameDate}\nPlayed: $slotAmount\nRefunded by host: ';
    TextEditingController noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Refund'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Do you want to refund user (${user['full_name']})?'),
                const SizedBox(height: 10),
                // Display prefilled text as a separate, read-only Text widget
                Text(
                  prefilledText,
                  style: const TextStyle(color: Colors.black54), // Optional: style to indicate read-only text
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
                // Combine the prefilled text with user input
                final fullNote = '$prefilledText${noteController.text.trim()}';

                // Process the refund with the full note
                Navigator.of(context).pop();
                _refundUser(user['kp_id'], fullNote); // Pass the combined note
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _refundUser(int kpId, String note) async {
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
      // Step 1: Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      // Step 2: Call the `process_refund` RPC function
      final result = await supabase.rpc('process_refund', params: {
        '_kp_id': kpId,
        '_game_id': widget.gameId,
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
      await _refreshData();
    } catch (e) {
      Navigator.pop(context);
      await _refreshData();
      // Handle unexpected errors
      if (kDebugMode) {
        print('Error processing refund: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred.')),
      );
    }
  }


  // Future<void> _refundUser(int kpId, String note) async {
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
  //   try {
  //     // Check for device mismatch
  //     final isMismatch = await AppState().checkDeviceMismatch(context);
  //     if (isMismatch) return; // Halt if there's a mismatch
  //
  //     // Step 1: Check if data exists in 'game_play' table for the given kpId and widget.gameId
  //     final response = await supabase
  //         .from('game_play')
  //         .select('id, slot_amount, is_win') // Select both 'id' and 'slot_amount'
  //         .eq('kp_id', kpId)
  //         .eq('game_id', widget.gameId);
  //     // .single(); // Get the single record if it exists
  //
  //     if (response.isEmpty) {
  //       Navigator.pop(context);
  //       // Handle the case where no data exists
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('No data found to refund.')),
  //       );
  //       await _refreshData();
  //       return;
  //     } else if (response[0]['is_win'] != null) {
  //       Navigator.pop(context);
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('Refund is not allowed. Game result has been declared.')),
  //       );
  //       return;
  //     }
  //
  //     // Extract 'id' and 'slot_amount' from the response
  //     int gamePlayId = response[0]['id'];
  //     String slotAmountStr = response[0]['slot_amount'];
  //
  //     // Step 2: Parse 'slot_amount' and calculate user invested amount
  //     int userInvested = _calculateUserInvested(slotAmountStr);
  //
  //     // Step 3: Update the 'khaiwals_players' table to add the user invested amount to their wallet
  //     final walletUpdateResponse = await supabase
  //         .rpc('add_to_balance', params: {'kp_id': kpId, 'amount': userInvested}); // Example of adding to wallet
  //
  //     if (walletUpdateResponse != null) {
  //       // Handle wallet update failure
  //       print('Failed to update wallet for kp_id: $kpId');
  //       Navigator.pop(context);
  //       return;
  //     }
  //
  //     // Step 4: Insert a refund transaction into the 'wallet' table
  //     final transactionResponse = await supabase
  //         .from('wallet')
  //         .insert({
  //       'kp_id': kpId,
  //       'game_id': widget.gameId,
  //       'transaction_type': 'Refund',
  //       'amount': userInvested,
  //       'timestamp': AppState().currentTime.toIso8601String(), // Assuming AppState().currentTime gives the current timestamp
  //       'note': note.isNotEmpty ? note : 'Refunded by host',
  //     });
  //
  //     if (transactionResponse != null) {
  //       // Handle transaction log failure
  //       print('Failed to insert refund transaction for kp_id: $kpId');
  //       Navigator.pop(context);
  //       return;
  //     }
  //
  //     // Step 5: Delete the record from the 'game_play' table after refund is processed
  //     final deleteResponse = await supabase
  //         .from('game_play')
  //         .delete()
  //         .eq('id', gamePlayId); // Delete using the retrieved 'id'
  //
  //     if (deleteResponse != null) {
  //       Navigator.pop(context);
  //       // Handle delete failure
  //       print('Failed to delete record from game_play for id: $gamePlayId');
  //       return;
  //     }
  //     Navigator.pop(context);
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text("Refund processed successfully: $userInvested."),
  //         backgroundColor: Colors.green,
  //       ),
  //     );
  //     await _refreshData();
  //   } catch (e) {
  //     Navigator.pop(context);
  //     await _refreshData();
  //     // Handle any unexpected errors
  //     print('Error processing refund: $e');
  //   }
  // }

  // Method to show the number picker dialog for rate selection
  Future<int?> _showRatePickerDialog(String field, int currentValue) async {
    int pickerValue = currentValue; // Use the current value as the starting value

    return showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit $field'),
          content: StatefulBuilder(
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
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                  ),
                  Text('Rate 1 x = $pickerValue'),
                ],
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


  // Function to show slot_amount in a dialog
  void _showSlotAmountDialog(BuildContext context, String slotAmount, String userName) {
    final formattedSlotAmount = _formatSlotAmount(slotAmount);  // Format the slot_amount string

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(userName),
          content: SingleChildScrollView(
            child: Text(formattedSlotAmount),  // Show the formatted slot_amount
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close the dialog first
                _processRefund(_selectedKpId!, slotAmount); // Trigger the refund process for the selected user
              },
              child: const Text('Refund'),
            ),

            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: formattedSlotAmount)); // Copy slotAmount to clipboard
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
                Navigator.pop(context); // Close the dialog
              },
              child: const Text('Copy'),
            ),

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

  String _formatSlotAmount(String slotAmount) {
    // Split the slot_amount string by ' / ' to get each 'key=value' pair
    final pairs = slotAmount.split(' / ');

    // Iterate through the pairs and format them
    final formattedPairs = pairs.map((pair) {
      final keyValue = pair.split('='); // Split each pair by '='
      if (keyValue.length == 2) {
        final key = keyValue[0];
        final value = keyValue[1];
        return '$key, ( $value )';  // Format it as 'key, ( value )'
      }
      return pair;  // Return the original pair if splitting failed
    }).join('\n');  // Join all formatted pairs with a newline

    return formattedPairs;  // Return the formatted string
  }

// Method to calculate the user's total invested amount from slotAmountStr
  int _calculateUserInvested(String slotAmountStr) {
    int userInvested = 0; // Start with 0 invested amount

    List<String> pairs = slotAmountStr.split(' / ');
    for (String pair in pairs) {
      List<String> parts = pair.split('=');
      if (parts.length == 2) {
        int amount = int.parse(parts[1]); // Parse the slot amount
        userInvested += amount; // Add to the total invested for the user
      }
    }
    return userInvested; // Return total invested for this user
  }

  // Method to check if game_result is declared within the next 7 days from the gameDate
  Future<bool> _checkGameResultForNext7Days(int infoId, DateTime gameDate) async {
    DateTime startDate = gameDate;
    DateTime endDate = gameDate.add(const Duration(days: 7));

    // First, query to find the maximum available game_date for the given info_id
    final maxDateResponse = await supabase
        .from('games')
        .select('game_date')
        .eq('info_id', infoId)
        .order('game_date', ascending: false)
        .limit(1);

    if (maxDateResponse.isNotEmpty) {
      DateTime maxGameDate = DateTime.parse(maxDateResponse[0]['game_date']);

      // If the calculated endDate exceeds the max available game_date, adjust the endDate
      if (endDate.isAfter(maxGameDate)) {
        endDate = maxGameDate;
      }
    }

    // Now, query the games table to check for game_result between startDate and the adjusted endDate
    final response = await supabase
        .from('games')
        .select('game_result')
        .gte('game_date', startDate.toIso8601String())
        .lte('game_date', endDate.toIso8601String())
        .eq('info_id', infoId);

    if (response.isNotEmpty) {
      for (var game in response) {
        if (game['game_result'] != null && game['game_result'].isNotEmpty) {
          return true; // Game result is declared for at least one game within the next 7 days
        }
      }
    }

    return false; // No game result declared within the next 7 days or adjusted endDate
  }


  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  // Method to show a dialog with the matched values
  void _showMatchedValuesDialog() {
    int? cutAmount = int.tryParse(cutAmountController.text);

    // if (cutAmount == 0 && cutAmount != null) {
    //   _showMissingNumbersDialog();
    //   return;
    // } else if (cutAmount == null){
    //   return;
    // }

    if (cutAmount == null){
      return;
    }

    // Find matching values based on the cutAmount
    List<String> matchedValues = originalValues.entries
        .where((entry) => entry.value == cutAmount)
        .map((entry) => entry.key) // Get the keys (which are now strings)
        .toList();

    int count = matchedValues.length;

    if (matchedValues.isNotEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('$count Matched Numbers With Amt: $cutAmount'),
            content: SingleChildScrollView(
              child: ListBody(
                children: matchedValues.map((value) => Text(value)).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: const Text("Close"),
              ),
              TextButton(
                onPressed: () {
                  // Call the copy method with matched values
                  _showCopyFormatDialog(
                    matchedValues.map((value) => MapEntry(value, cutAmount)).toList(),
                    isCopyNoOnly: true, // Copy only numbers
                  );
                },
                child: const Text("Copy"),
              ),
              TextButton(
                onPressed: () {
                  // Share the matched values
                  String textToShare = matchedValues.join('\n'); // Convert list to a vertical string
                  shareTextCode(textToShare);
                  // Share.share(textToShare, subject: 'Matched Numbers'); // Share the content
                },
                child: const Text("Share"),
              ),
            ],
          );
        },
      );
    } else {
      // Show a message if there are no matched values
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No matches found")),
      );
    }
  }

  void _onCopyFinalCodePressed(BuildContext context) {
    if (isDataFilled()) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Choose Copy Format'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Vertically ┇'),
                  onTap: () {
                    // if (!premium && !accessGranted) {
                    //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    //     content: Text('Use (Horizontally ⁃⁃⁃) or upgrade to Premium to use this'),
                    //   ));
                    //   return;
                    // }
                    String textToCopy = generateVerticalTextCode();
                    copyToClipboard(textToCopy);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Numbers copied to clipboard Vertically ┇'),
                    ));
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Shuffled Vertically ┇'),
                  onTap: () {
                    // if (!premium && !accessGranted) {
                    //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    //     content: Text('Use (Horizontally ⁃⁃⁃) or upgrade to Premium to use this'),
                    //   ));
                    //   return;
                    // }
                    String shuffledTextCode = shuffleNumbersVertically(generateVerticalTextCode());
                    copyToClipboard(shuffledTextCode);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Numbers copied to clipboard Shuffled Vertically ┇'),
                    ));
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Horizontally ⁃⁃⁃'),
                  onTap: () {
                    String textToCopy = generateHorizontalTextCode();
                    copyToClipboard(textToCopy);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Numbers copied to clipboard Horizontally ⁃⁃⁃'),
                    ));
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Shuffled Horizontally ⁃⁃⁃'),
                  onTap: () {
                    // if (!premium && !accessGranted) {
                    //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    //     content: Text('Use (Horizontally ⁃⁃⁃) or upgrade to Premium to use this'),
                    //   ));
                    //   return;
                    // }
                    String shuffledTextCode = shuffleNumbersHorizontally(generateHorizontalTextCode());
                    copyToClipboard(shuffledTextCode);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Numbers copied to clipboard Shuffled Horizontally ⁃⁃⁃'),
                    ));
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No data to share'),
      ));
    }
  }

  void _onShareFinalCodePressed(BuildContext context) {
    if (isDataFilled()) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Choose Share Format'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Vertically ┇'),
                  onTap: () {
                    // Check for premium status if needed (not implemented here)
                    String textToShare = generateVerticalTextCode();
                    shareTextCode(textToShare);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Shuffled Vertically ┇'),
                  onTap: () {
                    // Check for premium status if needed (not implemented here)
                    String shuffledTextCode = shuffleNumbersVertically(generateVerticalTextCode());
                    shareTextCode(shuffledTextCode);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Horizontally ⁃⁃⁃'),
                  onTap: () {
                    String textToShare = generateHorizontalTextCode();
                    shareTextCode(textToShare);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Shuffled Horizontally ⁃⁃⁃'),
                  onTap: () {
                    // Check for premium status if needed (not implemented here)
                    String shuffledTextCode = shuffleNumbersHorizontally(generateHorizontalTextCode());
                    shareTextCode(shuffledTextCode);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No data to share'),
      ));
    }
  }

  // Implement this method to share the QR code
  Future<void> _onShareFinalQrPressed(BuildContext context) async {
    try {
      // Generate the final code as a string (modify based on your logic)
      String finalCode = generateHorizontalTextCode();
      int totalAmount = _calculateUserInvested(finalCode);

      // Generate QR code and save it as an image file
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/Final QR.png';

      final qrValidationResult = QrValidator.validate(
        data: finalCode,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );

      if (qrValidationResult.status == QrValidationStatus.valid) {
        final qrCode = qrValidationResult.qrCode;
        final painter = QrPainter.withQr(
          qr: qrCode!,
          gapless: false,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        );

        // Create a white background for the QR code
        const imageSize = 200.0;
        const textHeight = 40.0;

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, imageSize, imageSize + textHeight));

        final paint = Paint()..color = Colors.white;
        canvas.drawRect(const Rect.fromLTWH(0, 0, imageSize, imageSize + textHeight), paint);

        // Draw QR code on canvas
        final qrImage = await painter.toImage(imageSize.toDouble());
        canvas.drawImage(qrImage, Offset.zero, Paint());

        // Draw the "Total" text below the QR code
        final textPainter = TextPainter(
          text: TextSpan(
            text: 'Total: $totalAmount',
            style: const TextStyle(color: Colors.black, fontSize: 16),
          ),
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();
        final textOffset = Offset(
          (imageSize - textPainter.width) / 2,
          imageSize + (textHeight - textPainter.height) / 2,
        );
        textPainter.paint(canvas, textOffset);

        // Convert canvas to image
        final finalImage = await recorder.endRecording().toImage(imageSize.toInt(), (imageSize + textHeight).toInt());
        final byteData = await finalImage.toByteData(format: ImageByteFormat.png);
        final buffer = byteData!.buffer;

        await File(filePath).writeAsBytes(buffer.asUint8List());

        // Share the generated QR code image
        await Share.shareXFiles([XFile(filePath)], text: '');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to generate QR code.'),
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sharing QR code: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error sharing QR code.'),
      ));
    }
  }


  // Generate formatted vertical code
  String generateVerticalTextCode() {
    StringBuffer formattedTextCode = StringBuffer();
    for (int i = 0; i < 100; i++) {
      String value = editTextControllers[i]?.text.trim() ?? '';
      if (value.isNotEmpty) {
        formattedTextCode.write('${i.toString().padLeft(2, '0')}, ( $value )\n');
      }
    }
    return formattedTextCode.toString().trim();
  }

  // Shuffle numbers vertically
  String shuffleNumbersVertically(String numbers) {
    List<String> numberList = numbers.split('\n');
    numberList.shuffle(Random());
    return numberList.join('\n');
  }

  // Generate horizontal code
  String generateHorizontalTextCode() {
    StringBuffer textCode = StringBuffer();

    for (int i = 0; i < 100; i++) {
      String value = editTextControllers[i]?.text ?? '';
      if (value.isNotEmpty) {
        textCode.write('${i.toString().padLeft(2, '0')}=$value / ');
      }
    }

    // Remove the trailing " / " by checking if textCode is not empty first
    if (textCode.isNotEmpty) {
      textCode = StringBuffer(textCode.toString().substring(0, textCode.length - 3));
    }

    return textCode.toString();
  }


  // Shuffle numbers horizontally
  String shuffleNumbersHorizontally(String numbers) {
    List<String> numberList = numbers.split(' / ');
    numberList.shuffle(Random());
    return numberList.join(' / ');
  }

  String shuffleOnlyNumbersHorizontally(String numbers) {
    List<String> numberList = numbers.split(' ');
    numberList.shuffle(Random());
    return numberList.join(' ');
  }

  // Copy text to clipboard
  void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  // Share the formatted text via Flutter's sharing mechanism (using share_plus)
  void shareTextCode(String formattedTextCode) {
    Share.share(formattedTextCode, subject: 'Shared Data');
  }


  // void _showMissingNumbersDialog() {
  //   List<String> missingNumbers = _findMissingNumbers();
  //
  //   if (missingNumbers.isNotEmpty) {
  //     showDialog(
  //       context: context,
  //       builder: (BuildContext context) {
  //         return AlertDialog(
  //           title: Text("${missingNumbers.length}: Empty Numbers"),
  //           content: SingleChildScrollView(
  //             child: ListBody(
  //               children: missingNumbers.map((number) => Text(number)).toList(),
  //             ),
  //           ),
  //           actions: [
  //             TextButton(
  //               onPressed: () {
  //                 Navigator.of(context).pop(); // Close the dialog
  //               },
  //               child: const Text("OK"),
  //             ),
  //           ],
  //         );
  //       },
  //     );
  //   } else {
  //     // Show a message if there are no missing numbers
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text("No missing numbers between 00 to 99")),
  //     );
  //   }
  // }
  // List<String> _findMissingNumbers() {
  //   // Create a list to hold missing numbers
  //   List<String> missingNumbers = [];
  //
  //   // Loop through numbers from 0 to 99
  //   for (int i = 0; i < 100; i++) {
  //     // Format number as a two-digit string
  //     String formattedNumber = i.toString().padLeft(2, '0');
  //
  //     // Check if the formatted number is not in originalValues
  //     if (!originalValues.containsKey(formattedNumber)) {
  //       missingNumbers.add(formattedNumber);
  //     }
  //   }
  //
  //   return missingNumbers; // Return the list of missing numbers
  // }


  bool isDataFilled() {
    for (int i = 0; i <= 99; i++) {
      String value = editTextControllers[i]?.text ?? '';

      // Try to parse the value to an integer
      int? numericValue = int.tryParse(value);

      // Check if the value is valid and greater than or equal to 1
      if (numericValue != null && numericValue >= 1) {
        return true;
      }
    }
    return false;
  }
  // Helper method to clear all TextEditingControllers
  void _clearAllTextFields() {
    for (var controller in editTextControllers.values) {
      controller.clear(); // Clear each controller
    }
  }


  @override
  void dispose() {

    for (int i = 0; i <= 99; i++) {
      editTextControllers[i]?.removeListener(_calculateTotalAmount);
      editTextControllers[i]?.dispose();
    }

    limitCheckController.dispose();

    cutAmountController.removeListener(_adjustSlotAmounts);
    cutAmountController.dispose();

    _finalAmount.dispose();
    _matchCount.dispose();
    riskProfitText.dispose();
    _belowCount.dispose();
    _aboveCount.dispose();

    _closeTimeChecker?.cancel();
    remainingCloseTime.dispose();
    countdownCloseTimeText.dispose();

    _lastBigPlayTimeChecker?.cancel();
    remainingLastBigPlayTime.dispose();
    countdownLastBigPlayTimeText.dispose();


    // SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    //   statusBarColor: Colors.transparent,
    // ));
    super.dispose();
  }
}
