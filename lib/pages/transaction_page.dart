import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/app_state.dart'; // Import intl package for date formatting

class TransactionPage extends StatefulWidget {
  final int kpId;
  final String fullName;

  const TransactionPage({super.key, required this.kpId, required this.fullName});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      loading = true; // Set loading to true when fetching starts
    });

    try {
      final response = await supabase
          .from('wallet')
          .select('id, game_id, kplog_id, transaction_type, amount, timestamp, note')
          .eq('kp_id', widget.kpId)
          .order('timestamp', ascending: false) // Fetch in descending order
          .limit(100); // Limit to the latest 100 records

      setState(() {
        transactions = response.isNotEmpty ? response : [];
        loading = false; // Set loading to false after data is fetched
      });
    } catch (e) {
      setState(() {
        loading = false; // Ensure loading is false in case of error
      });
      // Handle errors (optional)
      if (kDebugMode) {
        print('Error fetching transactions: $e');
      }
    }
  }


  Future<String?> _fetchFullGameName(int gameId) async {
    try {
      // Step 1: Fetch info_id and game_date from the games table
      final response = await supabase
          .from('games')
          .select('info_id, game_date')
          .eq('id', gameId);

      if (response.isEmpty) {
        return 'Game deleted'; // If no matching game is found
      }

      final int infoId = response[0]['info_id'];
      final String gameDate = response[0]['game_date'];

      // Step 2: Fetch full_game_name and is_active status from the game_info table
      final infoResponse = await supabase
          .from('game_info')
          .select('full_game_name, is_active')
          .eq('id', infoId);

      if (infoResponse.isNotEmpty) {
        final String fullGameName = infoResponse[0]['full_game_name'];
        final bool isActive = infoResponse[0]['is_active'] ?? true;

        // Combine game date and full game name
        if (!isActive) {
          return '$fullGameName (Inactive) - ${AppState().formatGameDate(gameDate)}';
        } else {
          return '$fullGameName - ${AppState().formatGameDate(gameDate)}';
        }
      }

      return 'Game deleted'; // If no game name found in game_info
    } catch (error) {
      print('Error fetching game name and date: $error');
      return 'Error fetching data';
    }
  }

  Future<String?> _fetchSlotAmount(int txnId) async {
    // Fetch the existing slot_amount from the game_play table
    final response = await supabase
        .from('game_play')
        .select('slot_amount')
        .or('play_txn_id.eq.$txnId, result_txn_id.eq.$txnId');

    if (response.isNotEmpty) {
      return response[0]['slot_amount'];
    }
    return 'data expired'; // Return null if no game name found
  }

  Future<Map<String, dynamic>?> _fetchKpLog(int kplogId) async {
    final response = await supabase
        .from('kp_logs')
        .select('id, recharge_amt, withdraw_amt, player_note, action, action_note, timestamp, action_timestamp')
        .eq('id', kplogId)
        .maybeSingle(); // Fetch the log details

    if (response != null) {
      return response;
    }
    return null;
  }


  @override
  Widget build(BuildContext context) {
    final allTransactions = transactions;
    final creditTransactions = transactions.where((transaction) => transaction['transaction_type'] == 'Credit').toList();
    final debitTransactions = transactions.where((transaction) => transaction['transaction_type'] == 'Debit').toList();
    final refundTransactions = transactions.where((transaction) => transaction['transaction_type'] == 'Refund').toList();
    final rechargeTransactions = transactions.where((transaction) => transaction['transaction_type'] == 'Recharge').toList();
    final withdrawTransactions = transactions.where((transaction) => transaction['transaction_type'] == 'Withdraw').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Transactions: (${widget.fullName})',
        ),
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
          // labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Debit'),
            Tab(text: 'Credit'),
            Tab(text: 'Refund'),
            Tab(text: 'Recharge'),
            Tab(text: 'Withdraw'),
          ],
        ),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : transactions.isEmpty
          ? Center(
        child: Text(
          'No Transactions Found',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          allTransactions.isEmpty ? Center(
            child: Text(
              'No Transaction Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildTransactionList(allTransactions),

          debitTransactions.isEmpty ? Center(
            child: Text(
              'No Debit Transaction Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildTransactionList(debitTransactions),

          creditTransactions.isEmpty ? Center(
            child: Text(
              'No Credit Transaction Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildTransactionList(creditTransactions),

          refundTransactions.isEmpty ? Center(
            child: Text(
              'No Refund Transaction Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildTransactionList(refundTransactions),

          rechargeTransactions.isEmpty ? Center(
            child: Text(
              'No Recharge Transaction Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildTransactionList(rechargeTransactions),

          withdrawTransactions.isEmpty ? Center(
            child: Text(
              'No Withdraw Transaction Found',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ) : _buildTransactionList(withdrawTransactions),

        ],
      ),
    );
  }

  Widget _buildTransactionList(List<dynamic> transactions) {
    return ListView.separated(
      // padding: const EdgeInsets.all(16.0),
      itemCount: transactions.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.grey,
      ),
      itemBuilder: (context, index) {
        final transaction = transactions[index];
        final transactionType = transaction['transaction_type'] ?? 'Unknown';
        final amount = transaction['amount'] ?? 0;
        final timestamp = transaction['timestamp'] != null
            ? AppState().formatTimestamp(transaction['timestamp'])
            : 'Unknown';

        // Define color and sign based on transaction type
        Color textColor;
        String sign;
        Color bgColor;

        if (transactionType == 'Debit') {
          textColor = Colors.redAccent;
          sign = '-';
          bgColor = Colors.red.shade50;
        } else if (transactionType == 'Credit') {
          textColor = Colors.green;
          sign = '+';
          bgColor = Colors.green.shade50;
        } else if (transactionType == 'Refund') {
          textColor = Colors.green;
          sign = '+';
          bgColor = Colors.orange.shade50;
        } else if (transactionType == 'Recharge') {
          textColor = Colors.green;
          sign = '+';
          bgColor = Colors.green.shade50;
        } else if (transactionType == 'Withdraw') {
          textColor = Colors.red;
          sign = '-';
          bgColor = Colors.blue.shade50;
        } else {
          textColor = Colors.grey;
          sign = '';
          bgColor = Colors.grey.shade50;
        }


        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: bgColor,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
                vertical: 6, horizontal: 16),
            title: Text(
              transactionType,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Txn ID: ${transaction['id']} \n$timestamp',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              '$sign $amount',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            onTap: () => _showTransactionDetails(transaction, bgColor, timestamp),
          ),
        );
      },
    );
  }


  void _showTransactionDetails(Map<String, dynamic> transaction, Color bgColor, String timestamp) async {
    if (transaction['game_id'] != null) {
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

      // Fetch additional details
      String? fullGameName = await _fetchFullGameName(transaction['game_id']);
      String? slotAmount = await _fetchSlotAmount(transaction['id']);

      Navigator.of(context).pop();
      showModalBottomSheet(
        backgroundColor: bgColor,
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext context) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.sports_esports_outlined,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${transaction['transaction_type']} Transaction',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(thickness: 1.0),
                  const SizedBox(height: 10),
                  Text(
                    'Amount: ${transaction['amount']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (fullGameName != null)
                    Text(
                      'Game: $fullGameName',
                      style: const TextStyle(fontSize: 16),
                    ),
                  const SizedBox(height: 10),
                  if (slotAmount != null)
                    Text(
                      'Played: $slotAmount',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Txn ID: ${transaction['id']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    'Time: $timestamp',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  if (transaction['note'] != null)
                    Text(
                      'Details: ${transaction['note']}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          );
        },
      );
    } else if (transaction['kplog_id'] != null) {
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

      // Fetch log details
      Map<String, dynamic>? log = await _fetchKpLog(transaction['kplog_id']);
      Navigator.of(context).pop();
      if (log != null) {
        _showLogDetails(log, bgColor);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Details not available"),
          ),
        );
      }
    }
  }


  void _showLogDetails(Map<String, dynamic> log, Color bgColor) {
    String status;
    Color statusColor = Colors.black;

    if (log['action'] == true && log['recharge_amt'] != null) {
      status = 'Recharge Successful';
      statusColor = Colors.green;
    } else if (log['action'] == false && log['recharge_amt'] != null) {
      status = 'Recharge Failed';
    } else if (log['action'] == null && log['recharge_amt'] != null) {
      status = 'Recharge Pending';
    } else if (log['action'] == true && log['withdraw_amt'] != null) {
      status = 'Withdrawal Successful';
      statusColor = Colors.blue;
    } else if (log['action'] == false && log['withdraw_amt'] != null) {
      status = 'Withdrawal Failed';
    } else if (log['action'] == null && log['withdraw_amt'] != null) {
      status = 'Withdrawal Pending';
    } else {
      status = 'Pending';
    }

    showModalBottomSheet(
      backgroundColor: bgColor,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
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
                      'Log Details',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const Divider(thickness: 1.0),
                const SizedBox(height: 10),
                Text('Status: $status', style: TextStyle(fontSize: 16, color: statusColor,)),
                const SizedBox(height: 10),
                Text(
                  'Amount: ${log['recharge_amt'] ?? log['withdraw_amt'] ?? 0}',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  'Log ID: ${log['id']}',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  'Time: ${AppState().formatTimestamp(log['timestamp'])}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 10),
                if (log['player_note'] != null)
                  Text(
                    'User Note: ${log['player_note']}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                if (log['action_timestamp'] != null)
                  Text(
                    'Response Time: ${AppState().formatTimestamp(log['action_timestamp'])}',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (log['action_note'] != null)
                  Text(
                    'Host Note: ${log['action_note']}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                const SizedBox(height: 10),
              ],
            ),
          ),
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
