import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:masterking/models/app_state.dart';

import '../main.dart';

class KplogsPage extends StatefulWidget {
  final int kpId;
  // final String currentView;
  final int nullActionCount;
  final String fullName;
  final num balance;

  const KplogsPage({super.key, required this.kpId, required this.nullActionCount, required this.fullName, required this.balance});

  @override
  State<KplogsPage> createState() => _KplogsPageState();
}

class _KplogsPageState extends State<KplogsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> logs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchKpLogs();
  }

  Future<void> _fetchKpLogs() async {
    setState(() {
      loading = true; // Set loading to true when fetching starts
    });

    try {
      // Fetch the latest 100 logs in descending order
      final recentLogsResponse = await supabase
          .from('kp_logs')
          .select('id, recharge_amt, withdraw_amt, player_note, action, action_timestamp, action_note, timestamp, user_dispute, khaiwal_dispute')
          .eq('kp_id', widget.kpId)
          .not('action', 'is', null)
          .not('user_dispute', 'is', true)
          .not('khaiwal_dispute', 'is', true)
          .order('timestamp', ascending: false) // Fetch in descending order
          .limit(100);

      // Fetch logs where action is null, irrespective of date or limit
      final nullActionLogsResponse = await supabase
          .from('kp_logs')
          .select('id, recharge_amt, withdraw_amt, player_note, action, action_timestamp, action_note, timestamp, user_dispute, khaiwal_dispute')
          .eq('kp_id', widget.kpId)
          .or('action.is.null,user_dispute.is.true,khaiwal_dispute.is.true');

      // Combine the two lists and remove duplicates
      final combinedLogs = <dynamic>{
        ...recentLogsResponse,
        ...nullActionLogsResponse,
      }.toList();

      // Sort combined logs by timestamp in descending order
      combinedLogs.sort((a, b) {
        DateTime timestampA = DateTime.parse(a['timestamp']);
        DateTime timestampB = DateTime.parse(b['timestamp']);
        return timestampB.compareTo(timestampA);
      });

      setState(() {
        logs = combinedLogs;
        loading = false; // Set loading to false after data is fetched
      });

      // Compare and update action count
      _compareAndUpdateActionCount();
    } catch (e) {
      setState(() {
        loading = false; // Ensure loading is false in case of error
      });
      if (kDebugMode) {
        print('Error fetching KP logs: $e');
      }
    }
  }


  void _compareAndUpdateActionCount() {
    // Count logs where 'action' is null
    int nullCount = logs.where((log) => log['action'] == null).length;

    // If the counts do not match
    if (nullCount != widget.nullActionCount) {
      AppState().userSettings['null_action_count'] = nullCount;

      // Update the appropriate user list based on 'allowed'
      final user = AppState().users.firstWhere(
            (user) => user['kp_id'] == widget.kpId,
        orElse: () => {},
      );
      if (user.isNotEmpty) {
        user['null_action_count'] = nullCount;
      }

      AppState().notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) {
    final allLogs = logs;
    final pendingLogs = logs.where((log) => log['action'] == null).toList();
    final successLogs = logs.where((log) => log['action'] == true).toList();
    final failedLogs = logs.where((log) => log['action'] == false).toList();
    final disputeLogs = logs
        .where((log) =>
    log['user_dispute'] == true ||
        log['khaiwal_dispute'] == true
      // || log['user_dispute'] == false ||
      // log['khaiwal_dispute'] == false
        ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Logs: (${widget.fullName})'),
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
          isScrollable: true, // Make the tabs scrollable
          tabs: [
            const Tab(text: 'All'),
            Tab(text: pendingLogs.isNotEmpty ? 'Pending ${pendingLogs.length}' : 'Pending'),
            const Tab(text: 'Success'),
            const Tab(text: 'Failed'),
            Tab(text: disputeLogs.isNotEmpty ? 'Dispute ${disputeLogs.length}' : 'Dispute'),
          ],
        ),
      ),
      body: loading // Check loading state
          ? const Center(child: CircularProgressIndicator()) // Show loading spinner
          : logs.isEmpty
          ? Center(
        child: Text(
          'No Logs Found',
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

          logs.isEmpty ? Center(
            child: Text(
              'No Logs Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildLogList(allLogs),

          pendingLogs.isEmpty ? Center(
            child: Text(
              'No Pending Logs Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildLogList(pendingLogs),

          successLogs.isEmpty ? Center(
            child: Text(
              'No Success Logs Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildLogList(successLogs),

          failedLogs.isEmpty ? Center(
            child: Text(
              'No Failed Logs Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildLogList(failedLogs),

          disputeLogs.isEmpty ? Center(
            child: Text(
              'No Disputes Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildLogList(disputeLogs),
        ],
      ),
    );
  }

  Widget _buildLogList(List<dynamic> logs) {
    return ListView.separated(
      itemCount: logs.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.grey,
      ),
      itemBuilder: (context, index) {
        final log = logs[index];

        // Logic directly embedded here
        bool isPending = false;
        String status;
        Color statusColor;
        Color backgroundColor = Colors.grey.shade50; // Default background color

        if (log['action'] == true && log['recharge_amt'] != null) {
          status = 'Recharge Successful';
          statusColor = Colors.green;
          backgroundColor = Colors.green.shade50; // Recharge background
        } else if (log['action'] == false && log['recharge_amt'] != null) {
          status = 'Recharge Failed';
          statusColor = Colors.redAccent;
          backgroundColor = Colors.red.shade50; // Failed background
        } else if (log['action'] == null && log['recharge_amt'] != null) {
          status = 'Recharge Pending...';
          statusColor = Colors.green;
          backgroundColor = Colors.orange.shade50; // Pending background
          isPending = true;
        } else if (log['action'] == true && log['withdraw_amt'] != null) {
          status = 'Withdrawal Successful';
          statusColor = Colors.blue;
          backgroundColor = Colors.blue.shade50; // Withdrawal success background
        } else if (log['action'] == false && log['withdraw_amt'] != null) {
          status = 'Withdrawal Failed';
          statusColor = Colors.red;
          backgroundColor = Colors.red.shade50; // Withdrawal failed background
        } else if (log['action'] == null && log['withdraw_amt'] != null) {
          status = 'Withdrawal Pending...';
          statusColor = Colors.blue;
          backgroundColor = Colors.orange.shade50; // Pending background for withdrawal
          isPending = true;
        } else {
          status = 'Pending';
          statusColor = Colors.orange;
          backgroundColor = Colors.orange.shade50; // Default Pending background
          isPending = true;
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: backgroundColor, // Apply category-specific background shade
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
                vertical: 8, horizontal: 16),
            title: Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              'Log ID: ${log['id']} \n${AppState().formatTimestamp(log['timestamp'])}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${log['recharge_amt'] ?? log['withdraw_amt'] ?? 0}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            onTap: () {
              _showLogDetails(log, status, statusColor, backgroundColor, isPending);
            },
          ),
        );
      },
    );
  }



  Future<void> _showLogDetails(Map<String, dynamic> log, String status, Color statusColor, Color backgroundColor, bool isPending) async {
    bool insufficientBalance = false;
    num availableBalance = 0;

    // Fetch the balance only if it's a pending withdrawal
    if (isPending && log['withdraw_amt'] != null) {
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

      final response = await supabase
          .from('khaiwals_players')
          .select('balance')
          .eq('id', widget.kpId)
          .maybeSingle(); // Fetch a single record

      if (response != null) {
        availableBalance = response['balance'] ?? 0;
        if (log['withdraw_amt'] > availableBalance) {
          insufficientBalance = true;
        }
        if (widget.balance != availableBalance) {
          if (kDebugMode) {
            print('updating wallet for user');
          }
          AppState().userSettings['balance'] = availableBalance;
          AppState().updateSelectedUserWallet(widget.kpId, availableBalance);
        }
      }
      Navigator.of(context).pop(); // Close the progress indicator
    }

    showModalBottomSheet(
      backgroundColor: backgroundColor,
      context: context,

      builder: (BuildContext context) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blueGrey,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Details',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const Divider(thickness: 1.0),
                const SizedBox(height: 10),

                // Status of the log (e.g., Pending Recharge, Recharge Successful)
                Text('Status: $status', style: TextStyle(fontSize: 16, color: statusColor)),
                const SizedBox(height: 10),

                // Amount
                Text('Amount: ${log['recharge_amt'] ?? log['withdraw_amt'] ?? 0}'),

                // Transaction ID
                Text('Log ID: ${log['id']}'),

                // Timestamp (formatted)
                Text('Date: ${AppState().formatTimestamp(log['timestamp'])}'),
                const SizedBox(height: 10),

                // Optional player note
                if (log['player_note'] != null)
                  Text(
                    'User Note: ${log['player_note']}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                const SizedBox(height: 10),

                // Optional action note
                if (log['action_note'] != null)
                  Text(
                    'Host Note: ${log['action_note']}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                const SizedBox(height: 10),

                // Optional action timestamp (formatted)
                if (log['action_timestamp'] != null)
                  Text(
                    'Response Time: ${AppState().formatTimestamp(log['action_timestamp'])}',
                    // style: const TextStyle(color: Colors.grey),
                  ),


                if ((log['user_dispute'] == false && log['khaiwal_dispute'] == false) || (log['user_dispute'] == false && log['khaiwal_dispute'] == null)
                    || (log['user_dispute'] == null && log['khaiwal_dispute'] == false) || (log['user_dispute'] == null && log['khaiwal_dispute'] == null))
                  Column(
                    children: [
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: ElevatedButton(
                          onPressed: () {
                            _handleRaiseDispute(log); // Method to handle raising the dispute
                          },
                          child: const Text('Raise Dispute'),
                        ),
                      ),
                    ],
                  ),



                if ((log['user_dispute'] == false && log['khaiwal_dispute'] == false) || (log['user_dispute'] == false && log['khaiwal_dispute'] == null)
                || (log['user_dispute'] == null && log['khaiwal_dispute'] == false))
                  Column(
                    children: [
                      const SizedBox(height: 10),
                      Text(
                        'Dispute Resolved, raised by: ${_wasDisputeRaisedBy(log)}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),


                if (log['user_dispute'] == true || log['khaiwal_dispute'] == true)
                  Column(
                    children: [
                      const SizedBox(height: 10),

                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: Text(
                          'Dispute raised by: ${_getDisputeRaisedBy(log)}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Edit Note button
                          if (log['user_dispute'] == true || log['khaiwal_dispute'] == true || log['user_dispute'] == false || log['khaiwal_dispute'] == false)
                            ElevatedButton(
                              onPressed: () {
                                _handleEditNote(log); // Call a method to handle editing the note
                              },
                              child: const Text('Edit Note'),
                            ),

                          // Solve button
                          if (log['khaiwal_dispute'] == true)
                            ElevatedButton(
                              onPressed: () {
                                _handleSolveDispute(log); // Call a method to handle solving the dispute
                              },
                              child: const Text('Resolve'),
                            ),
                        ],
                      ),
                    ],
                  ),

                const SizedBox(height: 10),

                // Show Cancel and Ok buttons only for pending requests
                if (isPending)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (insufficientBalance)
                        Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: Text(
                            'Available balance: $availableBalance \nInsufficient Balance to Process Withdrawal.',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              _showCancelConfirmationDialog(log);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                            ),
                            child: const Text('Cancel Request'),
                          ),
                          ElevatedButton(
                            onPressed: insufficientBalance
                                ? null // Disable button if balance is insufficient
                                : () {
                              _showAcceptConfirmationDialog(log);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: insufficientBalance
                                  ? Colors.grey // Disabled color
                                  : Colors.greenAccent,
                            ),
                            child: const Text('Accept Request'),
                          ),
                        ],
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

  String _getDisputeRaisedBy(Map<String, dynamic> log) {
    bool userDispute = log['user_dispute'] == true;
    bool khaiwalDispute = log['khaiwal_dispute'] == true;

    if (userDispute && khaiwalDispute) {
      return 'User and Host';
    } else if (userDispute) {
      return 'User';
    } else if (khaiwalDispute) {
      return 'Host';
    }
    return ''; // Default case (should not occur if condition above is correct)
  }

  String _wasDisputeRaisedBy(Map<String, dynamic> log) {
    bool userDispute = log['user_dispute'] != null;
    bool khaiwalDispute = log['khaiwal_dispute'] != null;

    if (userDispute && khaiwalDispute) {
      return 'User and Host';
    } else if (userDispute) {
      return 'User';
    } else if (khaiwalDispute) {
      return 'Host';
    }
    return ''; // Default case (should not occur if condition above is correct)
  }

  void _handleRaiseDispute(Map<String, dynamic> log) {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to raise dispute.')),
      );
      return; // Terminate initialization if conditions are not met
    }

    TextEditingController noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Raise Dispute'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'After raising a dispute, no further recharge, withdrawal & game play can be processed until the dispute is resolved. Please add a note for clarity (optional).',
                style: TextStyle(fontSize: 14, color: Colors.redAccent),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: noteController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Optional Note',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            // Cancel Button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Cancel'),
            ),

            // Raise Dispute Button
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close the dialog before updating
                Navigator.of(context).pop(); // Close the dialog before updating

                setState(() {
                  loading = true;
                });
                // Call the method to update the database
                await _raiseDispute(log, noteController.text.trim());
                setState(() {
                  loading = false;
                });
              },
              child: const Text('Raise Dispute'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _raiseDispute(Map<String, dynamic> log, String note) async {
    try {
      // Check total number of unresolved disputes for `khaiwal_dispute`
      final disputeCountResponse = await supabase
          .from('kp_logs')
          .select('id')
          .eq('kp_id', widget.kpId)
          .eq('khaiwal_dispute', true)
          .limit(5);


      if (disputeCountResponse.length >= 4) {
        // Show a dialog to inform the user about the limit
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Dispute Limit Reached'),
              content: const Text(
                'There are already more than 3 unresolved disputes. Please resolve them before raising a new dispute.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return; // Halt further execution
      }
      // Prepare the data for the update
      final data = {
        'khaiwal_dispute': true,
        'action_note': note.isEmpty ? null : note,
      };

      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      // Update the `khaiwal_dispute` and `action_note` in Supabase
      final response = await supabase
          .from('kp_logs')
          .update(data)
          .eq('id', log['id']);

      if (response != null) {
        throw Exception(response.error!.message);
      }

      // Update the local data and refresh the UI
      setState(() {
        for (var entry in logs) { // Assuming 'logs' holds the data
          if (entry['id'] == log['id']) {
            entry['khaiwal_dispute'] = true;
            entry['action_note'] = note.isEmpty ? null : note;
            break;
          }
        }
      });

      // Show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispute raised successfully')),
      );
    } catch (error) {
      // Show an error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error raising dispute: $error')),
      );
    }
  }


  void _handleSolveDispute(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Resolve Dispute'),
          content: const Text(
            'Are you sure you want to revoke the dispute from your side?',
          ),
          actions: [
            // Cancel Button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Cancel'),
            ),

            // Resolve Button
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close the dialog before making the update
                Navigator.of(context).pop(); // Close the dialog before making the update

                setState(() {
                  loading = true;
                });
                // Call the update method to resolve the dispute
                await _resolveDispute(log);

                setState(() {
                  loading = false;
                });
              },
              child: const Text('Resolve'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resolveDispute(Map<String, dynamic> log) async {
    try {
      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      // Update the khaiwal_dispute column in Supabase
      final response = await supabase
          .from('kp_logs')
          .update({'khaiwal_dispute': false})
          .eq('id', log['id']);

      if (response != null) {
        throw Exception(response.error!.message);
      }

      // Update the local data and refresh the UI
      setState(() {
        for (var entry in logs) { // Assuming 'logs' holds the data
          if (entry['id'] == log['id']) {
            entry['khaiwal_dispute'] = false;
            break;
          }
        }
      });

      // Show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispute resolved successfully')),
      );
    } catch (error) {
      // Show an error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resolving dispute: $error')),
      );
    }
  }


  void _handleEditNote(Map<String, dynamic> log) {
    TextEditingController _noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Note'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _noteController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Enter your note here...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close the dialog
                Navigator.of(context).pop(); // Close the dialog
                setState(() {
                  loading = true;
                });
                String note = _noteController.text.trim();
                await _updateNoteInDatabase(log['id'], note.isEmpty ? null : note);
                setState(() {
                  loading = false;
                });
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateNoteInDatabase(int logId, String? note) async {
    try {
      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      final response = await supabase
          .from('kp_logs')
          .update({'action_note': note})
          .eq('id', logId);

      if (response != null) {
        throw Exception(response.error!.message);
      }

      // Update the local data
      setState(() {
        for (var log in logs) { // Assuming 'logs' is your list of logs
          if (log['id'] == logId) {
            log['action_note'] = note;
            break;
          }
        }
      });

      // Optionally, show a success message or refresh data
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note updated successfully')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error updating note')),
      );
    }
  }



  // Show confirmation dialog with optional cancellation reason
  void _showCancelConfirmationDialog(Map<String, dynamic> log) {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to cancel.')),
      );
      return; // Terminate initialization if conditions are not met
    }

    TextEditingController reasonController = TextEditingController(); // Controller for the reason input

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Are you sure you want to cancel this request? This action cannot be undone.'),
              const SizedBox(height: 10),
              TextField(
                maxLength: 100,
                controller: reasonController, // Attach the controller to the text field
                decoration: const InputDecoration(
                  labelText: 'Cancellation Reason (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog without doing anything
              },
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                setState(() {
                  loading = true;
                });
                _cancelRequest(log, reasonController.text); // Pass the cancellation reason
                setState(() {
                  loading = false;
                });
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

// Cancel the request by updating the 'action' to null and adding the 'action_note'
  Future<void> _cancelRequest(Map<String, dynamic> log, String cancelReason) async {
    try {
      // Check for existing disputes
      final disputeCheckResponse = await supabase
          .from('kp_logs')
          .select('id')
          .eq('kp_id', widget.kpId)
          .or('user_dispute.eq.true,khaiwal_dispute.eq.true')
          .limit(1)
          .maybeSingle();

      if (disputeCheckResponse != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: There is unresolved dispute. Resolve it before proceeding.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
        return; // Halt further execution
      }
      // Check for device mismatch
      final isMismatch = await AppState().checkDeviceMismatch(context);
      if (isMismatch) return; // Halt if there's a mismatch

      // Update the request in the kp_logs table
      await supabase
          .from('kp_logs')
          .update({
        'action': false, // Set action to null
        'action_note': cancelReason.isNotEmpty ? cancelReason : null, // Add the reason if provided
        'action_timestamp': AppState().currentTime.toIso8601String(),
      }).eq('id', log['id']); // Match the log ID

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request canceled successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh the logs after cancellation
      _fetchKpLogs();
      Navigator.pop(context); // Close the modal after successful cancellation
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error canceling request: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  // Show confirmation dialog with an optional note for "Accept Request"
  void _showAcceptConfirmationDialog(Map<String, dynamic> log) {

    if (AppState().subscription != 'super' && AppState().subscription != 'premium') {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get a subscription to accept.')),
      );
      return; // Terminate initialization if conditions are not met
    }

    TextEditingController noteController = TextEditingController(); // Controller for the note input

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Accept Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Are you sure you want to accept this request?'),
              const SizedBox(height: 10),
              TextField(
                controller: noteController, // Attach the controller to the text field
                maxLength: 100,  // Set the maximum length to 100
                decoration: const InputDecoration(
                  labelText: 'Note (Optional)',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(100),  // Limits input to 200 characters
                ],
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog without doing anything
              },
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                _acceptRequest(log, noteController.text); // Pass the note
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  // Accept the request by setting 'action' to true and updating the 'wallet' if recharge or withdrawal
  Future<void> _acceptRequest(Map<String, dynamic> log, String acceptNote) async {
    try {
      // Check for existing disputes
      final disputeCheckResponse = await supabase
          .from('kp_logs')
          .select('id')
          .eq('kp_id', widget.kpId)
          .or('user_dispute.eq.true,khaiwal_dispute.eq.true')
          .limit(1)
          .maybeSingle();

      if (disputeCheckResponse != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: There is unresolved dispute. Resolve it before proceeding.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
        return; // Halt further execution
      }

      final num? rechargeAmount = (log['recharge_amt'] as num?);
      final num? withdrawAmount = (log['withdraw_amt'] as num?);

      if (rechargeAmount != null || withdrawAmount != null) {
        final response = await supabase
            .from('khaiwals_players')
            .select('balance')
            .eq('id', widget.kpId)
            .single();

        final logResponse = await supabase
            .from('kp_logs')
            .select('id')
            .eq('id', log['id'])
            .maybeSingle();

        if (logResponse == null) {
          Navigator.pop(context);
          _showDialog('Notice', 'Request has been cancelled by user');
          _fetchKpLogs();
          return;
        }

        if (response['balance'] != null) {
          final num currentWallet = (response['balance']);
          String transactionType = '';
          num amount = 0;

          if (rechargeAmount != null) {

            transactionType = 'Recharge';
            amount = rechargeAmount;
          } else if (withdrawAmount != null) {
            if (currentWallet < withdrawAmount) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: Not enough balance in the user wallet for withdrawal. Current balance: $currentWallet'),
                  backgroundColor: Colors.red,
                ),
              );
              AppState().userSettings['balance'] = currentWallet;
              AppState().updateSelectedUserWallet(widget.kpId, currentWallet + amount);
              return;
            }

            transactionType = 'Withdraw';
            amount = -withdrawAmount;
          }
          // Show progress indicator
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            },
          );
          try {
            // Check for device mismatch
            final isMismatch = await AppState().checkDeviceMismatch(context);
            if (isMismatch) return; // Halt if there's a mismatch

            await supabase.rpc('process_transaction', params: {
              '_kp_id': widget.kpId,
              '_log_id': log['id'],
              '_transaction_type': transactionType,
              '_amount': amount,
              '_accept_note': acceptNote ?? '',
              '_action_timestamp': AppState().currentTime.toIso8601String(),
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$transactionType request accepted'),
                backgroundColor: Colors.green,
              ),
            );

            AppState().userSettings['balance'] = currentWallet + amount;
            AppState().updateSelectedUserWallet(widget.kpId, currentWallet + amount);
          } catch (error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error processing transaction: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }

          Navigator.pop(context);

        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Wallet not found for the player'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      _fetchKpLogs();
      Navigator.pop(context);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accepting request: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
    _tabController.dispose(); // Dispose of TabController to free resources
    super.dispose();
  }

}
