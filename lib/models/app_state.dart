import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ntp/ntp.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../main.dart';

class AppState extends ChangeNotifier {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();
  final user = supabase.auth.currentUser;

  String khaiwalId = '';
  String khaiwalName = '';
  String khaiwalUserName = '';
  String khaiwalEmail = '';
  String khaiwalTimezone = '';
  String avatarUrl = '';
  int defaultRate = 90;
  int refreshDifference = -360;
  int menuOption = 1;
  int superGames = 0;
  int superUsers = 0;
  int premiumGames = 0;

  bool isSuper = false;
  bool isPremium = false;
  bool rcSuper = false;
  bool rcPremium = false;
  bool checkDouble = false;
  bool? appAccess;
  String deviceId = '';
  String subscription = '';
  String granted = '';
  String updateType = '';
  int currentVersion = 0;
  int minVersion = 0;
  int maxVersion = 0;

  DateTime? sgUpdatedAt;
  DateTime? pgUpdatedAt;
  bool isResetting = false;

  late DateTime currentTime;
  Timer? _timer;
  Timer? _limitUpdateTimer; // to update limit_check after 2 seconds
  Timer? _cutUpdateTimer; // to update limit_check after 2 seconds
  Timer? _menuUpdateTimer; // to update menu_option after 2 seconds

  List<String> gameNames = [];
  Map<String, List<Map<String, dynamic>>> gameResults = {};
  List<Map<String, dynamic>> games = [];
  Map<int, bool> gamePlayExists = {};

  // List to store users' data
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> originalUsers = [];

  Map<String, dynamic> userSettings = {};

  bool initialized = false;

  Future<void> initialize() async {

    await _checkAppVersion();
    if (updateType.isNotEmpty){
      appAccess = false;
      return;
    }

    await _getCurrentDeviceId();
    await fetchUserProfileId();

    // Add the condition to terminate initialization if neither condition is met
    // if (subscription != 'super' && subscription != 'premium') {
    //   return; // Terminate initialization if conditions are not met
    // }

    if (kDebugMode) {
      print('printing the current subsciption: $subscription');
    }

    // Check for app access
    // if (appAccess == false) {
    //   return; // Terminate further navigation
    // }

    // Start timer to periodically update accurateCurrentTime
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      currentTime = currentTime.add(const Duration(seconds: 1));
      if (currentTime.hour == 0 && currentTime.minute == 0 && currentTime.second == 0) {
        // await fetchDataForCurrentMonth();
        await fetchGameNamesAndResults();
        await fetchGamesForCurrentDateOrTomorrow();
      }
    });

    // Start another timer to refresh time every minute
    Timer.periodic(const Duration(minutes: 1), (timer) async {
      await refreshTime();
      notifyListeners(); // Notify listeners if you want to update the UI
    });

    await checkGamePlayExistence();

    await fetchMenuUsers();

    initialized = true;
    notifyListeners();
  }

  // Method to fetch the current device ID
  Future<void> _getCurrentDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id ?? ''; // Unique Android ID
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? ''; // Unique iOS ID
    } else {
      throw UnsupportedError('Unsupported platform');
    }

  }

  Future<void> _checkAppVersion() async {
    try {
      // Fetch the app's build number (version code)
      final packageInfo = await PackageInfo.fromPlatform();
      currentVersion = int.parse(packageInfo.buildNumber); // e.g., 10

      // Fetch the configuration for the app version from Supabase
      final response = await supabase
          .from('khaiwal_app_config')
          .select('min_version, max_version, force_update')
          .eq('id', 1) // Adjust this for iOS if needed
          .maybeSingle();

      if (response != null) {
        minVersion = response['min_version'] ?? 0;
        maxVersion = response['max_version'] ?? 0;
        final maxForceUpdate = response['force_update'] ?? false;

        if (currentVersion < minVersion) {
          // Handle version lower than min_version
          updateType = 'min_version';
          // _showUpdateDialog("App version is too old. Please update the app.");
        } else if (maxForceUpdate && currentVersion < maxVersion) {
          // Handle version higher than max_version (optional check)
          updateType = 'force_update';
          // _showUpdateDialog("Your app version is not supported anymore. Please update.");
        }
      }
    } catch (error) {
      if (kDebugMode) {
        print("Error checking app version: $error");
      }
    }
  }


  Future<void> fetchUserProfileId() async {
    if (user != null) {
      final khaiwalResponse = await supabase
          .from('khaiwals')
          .select('id, full_name, username, rate, timezone, refresh_diff, sg_updated_at, pg_updated_at, avatar_url, device_id, menu_option, is_super, is_premium, granted, super_games, super_active_users, premium_games, app_access')
          .eq('id', user!.id);

      if (khaiwalResponse.isEmpty) {
        final playerResponse = await supabase
            .from('profiles')
            .select('id, email, full_name, avatar_url, device_id')
            .eq('id', user!.id);

        if (playerResponse.isNotEmpty) {
          String timezone = getTimeZone();

          khaiwalId = playerResponse[0]['id'] ?? '';
          khaiwalName = playerResponse[0]['full_name'] ?? '';
          avatarUrl = playerResponse[0]['avatar_url'] ?? '';

          await supabase.from('khaiwals').insert({
            'id': playerResponse[0]['id'],
            'email': user!.email!,
            'full_name': playerResponse[0]['full_name'] ?? '',
            'device_id': playerResponse[0]['device_id'] ?? '',
            'timezone': timezone,
          });


          await supabase.from('khaiwals').update({
            'timezone': timezone,
            if (playerResponse[0]['device_id'] != deviceId) 'device_id': deviceId,
          }).eq('id', khaiwalId);

          khaiwalTimezone = timezone;

        } else {
          String timezone = getTimeZone();
          // If both khaiwalResponse and playerResponse are empty, insert into Khaiwals
          await supabase.from('khaiwals').insert({
            'id': user!.id,
            'email': user!.email!,
            'full_name': user!.userMetadata?['full_name'],
            'timezone': timezone,
            'device_id': deviceId,
          });

          // Set default values after insertion
          khaiwalId = user!.id;
          khaiwalEmail = user!.email!;
          khaiwalName = user!.userMetadata?['full_name'] ?? '';
          khaiwalTimezone = timezone;
        }
      } else {
        khaiwalId = khaiwalResponse[0]['id'] ?? '';
        khaiwalName = khaiwalResponse[0]['full_name'] ?? '';
        khaiwalUserName = khaiwalResponse[0]['username'] ?? '';
        avatarUrl = khaiwalResponse[0]['avatar_url'] ?? '';
        granted = khaiwalResponse[0]['granted'].toString().trim() ?? '';
        appAccess = khaiwalResponse[0]['app_access'];
        isSuper = khaiwalResponse[0]['is_super'] ?? false;
        isPremium = khaiwalResponse[0]['is_premium'] ?? false;
        sgUpdatedAt = khaiwalResponse[0]['sg_updated_at'] != null
            ? DateTime.parse(khaiwalResponse[0]['sg_updated_at'])
            : null;
        pgUpdatedAt = khaiwalResponse[0]['pg_updated_at'] != null
            ? DateTime.parse(khaiwalResponse[0]['pg_updated_at'])
            : null;
        defaultRate = khaiwalResponse[0]['rate'] ?? 90;
        refreshDifference = khaiwalResponse[0]['refresh_diff'] ?? -360;
        menuOption = khaiwalResponse[0]['menu_option'] ?? 0;
        superGames = khaiwalResponse[0]['super_games'] ?? 0;
        superUsers = khaiwalResponse[0]['super_active_users'] ?? 0;
        premiumGames = khaiwalResponse[0]['premium_games'] ?? 0;

        if (khaiwalResponse[0]['device_id'] != deviceId){
          await updateDeviceId();
        }

        if (khaiwalResponse[0]['timezone'] == null || khaiwalResponse[0]['timezone'] == ''){
          String timezone = getTimeZone();
          final timezoneResponse = await supabase
              .from('khaiwals')
              .update({'timezone': timezone})
              .eq('id', khaiwalId);
          if (timezoneResponse == null){
            khaiwalTimezone = timezone;
          }
        } else {
          khaiwalTimezone = khaiwalResponse[0]['timezone'] ?? 'UTC +05:30';
        }

      }
      khaiwalEmail = user!.email!;

      if (subscription == 'premium' || granted == 'premium') {
        subscription = 'premium';
      } else if (subscription == 'super' || granted == 'super') {
        subscription = 'super';
      } else {
        subscription = '';
      }

      if (granted == 'super' && isSuper != true) {
        await supabase
            .from('khaiwals')
            .update({'is_super': true})
            .eq('id', khaiwalId);
      }
      if (granted == 'premium' && isPremium != true) {
        await supabase
            .from('khaiwals')
            .update({'is_premium': true})
            .eq('id', khaiwalId);
      }

      if (rcSuper != isSuper && granted != 'super' || rcPremium != isPremium && granted != 'premium'){
        if (kDebugMode) {
          print('again fetching purchases');
        }
        // Fetch user details from RevenueCat
        // Fetch online UTC time
        final response = await supabase
            .from('khaiwal_app_config')
            .select('rc_sub_key')
            .eq('id', 1)
            .maybeSingle();

        final subscriberData = await fetchRevenueCatDetails(user!.id, response?['rc_sub_key']);

        if (subscriberData.isNotEmpty) {
          final entitlements = subscriberData['subscriber']['entitlements'];
          final currentTimeUTC = await getOnlineDateTime();

          rcSuper = entitlements['super']?['expires_date'] != null
              ? DateTime.parse(entitlements['super']['expires_date']).isAfter(
              currentTimeUTC)
              : false;

          rcPremium = entitlements['premium']?['expires_date'] != null
              ? DateTime.parse(entitlements['premium']['expires_date']).isAfter(
              currentTimeUTC)
              : false;

          if ((rcSuper != isSuper && granted != 'super') || (rcPremium != isPremium && granted != 'premium')) {
            if (kDebugMode) {
              print('updating through rc check');
            }
            await supabase.from('khaiwals').update({
              if (rcSuper != isSuper && granted != 'super') 'is_super': rcSuper,
              if (rcPremium != isPremium && granted != 'premium') 'is_premium': rcPremium,
            }).eq('id', khaiwalId);
          }
        }
      }

      // Add the condition to terminate initialization if neither condition is met
      // if (subscription != 'super' && subscription != 'premium') {
      //   return; // Terminate initialization if conditions are not met
      // }
      //
      // // Check for app access
      // if (appAccess == false) {
      //   return; // Terminate further navigation
      // }

      await refreshTime();
      await fetchGameNamesAndResults();
      await fetchGamesForCurrentDateOrTomorrow();
    }
  }

  Future<Map<String, dynamic>> fetchRevenueCatDetails(String appUserId, String? apiKey) async {
    final url = 'https://api.revenuecat.com/v1/subscribers/$appUserId';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        if (kDebugMode) {
          print('Failed to fetch RevenueCat details: ${response.statusCode}');
        }
        return {};
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching RevenueCat details: $e');
      }
      return {};
    }
  }

  Future<void> refreshTime() async {
    currentTime = await getAccurateTimeWithTimeZone();
  }

  Future<DateTime> getAccurateTimeWithTimeZone() async {
    // DateTime time = DateTime.now().toUtc();
    // return time.add(const Duration(minutes: 330));
    try {
      // Get the current UTC time from the internet
      DateTime utcTime = await getOnlineDateTime();

      // Merge UTC time with timezone
      return mergeTimezoneWithUTC(utcTime, khaiwalTimezone);
    } catch (e) {
      if (kDebugMode) {
        print('Error merging time with timezone: $e');
      }
      DateTime time = DateTime.now().toUtc();
      return time.add(const Duration(minutes: 330)); // Fallback to device time in case of an error
    }
  }

  Future<DateTime> getOnlineDateTime() async {
    try {
      DateTime currentTime = await NTP.now();
      return currentTime.toUtc();
    } catch (e) {
      // print('Error fetching time: $e');
      return fetchSupabaseDateTime(); // Fallback to device time in case of an error
    }
  }

  Future<DateTime> fetchSupabaseDateTime() async {
    try {
      // Use Supabase to fetch current time
      final response = await supabase.rpc('get_supabase_time');

      if (response != null) {
        return DateTime.parse(response as String).toUtc();
      } else {
        throw Exception('Failed to fetch time');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching time');
      }
      _terminateApp();
      throw Exception('All time-fetching methods failed');
    }
  }

  // Function to terminate the app
  void _terminateApp() {
    SystemChannels.platform.invokeMethod('SystemNavigator.pop'); // Close the app
    exit(0); // Forcefully terminate the app
  }

  // Future<DateTime> fetchHttpDateTime() async {
  //   final response = await http.get(Uri.parse('http://worldtimeapi.org/api/timezone/Etc/UTC'));
  //   if (response.statusCode == 200) {
  //     final data = jsonDecode(response.body);
  //     return DateTime.parse(data['utc_datetime']);
  //   } else {
  //     throw Exception('Failed to load date and time');
  //   }
  // }

  DateTime mergeTimezoneWithUTC(DateTime utcTime, String khaiwalTimezone) {
    // Extract the sign (+ or -), hours, and minutes from khaiwalTimezone string
    final timezonePattern = RegExp(r'UTC ([+-])(\d{2}):(\d{2})');
    final match = timezonePattern.firstMatch(khaiwalTimezone);

    if (match != null) {
      String sign = match.group(1)!; // '+' or '-'
      int hours = int.parse(match.group(2)!); // Hours part
      int minutes = int.parse(match.group(3)!); // Minutes part

      // Convert hours and minutes to a Duration
      Duration offset = Duration(hours: hours, minutes: minutes);

      // Adjust UTC time based on the sign of the timezone
      if (sign == '+') {
        return utcTime.add(offset);
      } else {
        return utcTime.subtract(offset);
      }
    }

    // Return UTC time if parsing fails (fallback)
    return utcTime;
  }
  Future<void> fetchGameNamesAndResults() async {
    try {
      if (khaiwalId.isEmpty) return;

      final now = getLiveTime();
      final firstDayOfMonth = DateTime.utc(now.year, now.month, 1);
      final lastDayOfMonth = DateTime.utc(now.year, now.month + 1, 0);

      // First query to fetch 'id' and 'short_game_name' from 'game_info'
      final gameInfoResponse = await supabase
          .from('game_info')
          .select('id, short_game_name, sequence')
          .eq('khaiwal_id', khaiwalId);

      if (gameInfoResponse.isEmpty) {
        gameNames = [];
        gameResults = {};
        games = [];
        notifyListeners(); // No data found in 'game_info'
        return;
      }

      List<dynamic> gameInfoData = gameInfoResponse as List<dynamic>;

      // Sort gameInfoData by 'id' (infoId) to maintain sequence
      gameInfoData.sort((a, b) => a['id'].compareTo(b['id']));

      // Sort gameInfoData by 'sequence', handling null values by assigning them the lowest priority
      gameInfoData.sort((a, b) {
        final sequenceA = a['sequence'] ?? double.infinity; // Null goes to the end
        final sequenceB = b['sequence'] ?? double.infinity;
        return sequenceA.compareTo(sequenceB);
      });

      // Create a map of info_id -> short_game_name
      Map<int, String> gameInfoMap = {
        for (var info in gameInfoData) info['id']: info['short_game_name']
      };

      // Collect all info_ids to query games table
      List<int> infoIds = gameInfoMap.keys.toList();

      if (infoIds.isEmpty) {
        notifyListeners(); // No info_ids found
        return;
      }

      // Build an OR filter string for all the infoIds
      final orFilter = infoIds.map((id) => 'info_id.eq.$id').join(',');

      // Second query to fetch from 'games' table where info_id matches any of the fetched infoIds
      final gamesResponse = await supabase
          .from('games')
          .select('id, info_id, game_date, game_result, off_day')
          .or(orFilter)
          .gte('game_date', firstDayOfMonth.toIso8601String())
          .lte('game_date', lastDayOfMonth.toIso8601String());


      if (gamesResponse.isEmpty) {
        gameNames = [];
        gameResults = {};
        games = [];
        notifyListeners(); // No games found for the selected info_ids
        return;
      }

      List<dynamic> gamesData = gamesResponse as List<dynamic>;
      if (gamesData.isEmpty) {
        notifyListeners(); // Notify listeners when no data is found
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

      gameNames = newGameNames;
      gameResults = results;


      notifyListeners(); // Notify listeners after updating gameNames and gameResults
    } catch (error) {
      // Handle error
      if (kDebugMode) {
        print('Error fetching game names and results: $error');
      }
    }
  }


  // Future<void> fetchGameNamesAndResults() async {
  //   try {
  //     if (khaiwalId.isEmpty) return;
  //
  //     final now = getLiveTime();
  //     final firstDayOfMonth = DateTime.utc(now.year, now.month, 1);
  //     final lastDayOfMonth = DateTime.utc(now.year, now.month + 1, 0);
  //
  //     final response = await supabase
  //         .from('games')
  //         .select('id, game_date, short_game_name, game_result')
  //         .eq('khaiwal_id', khaiwalId)
  //         .gte('game_date', firstDayOfMonth.toIso8601String())
  //         .lte('game_date', lastDayOfMonth.toIso8601String());
  //
  //     if (response.isEmpty) {
  //       gameNames = [];
  //       gameResults = {};
  //       notifyListeners();
  //       return;
  //     }
  //
  //     List<dynamic> data = response as List<dynamic>;
  //     if (data.isEmpty) {
  //       notifyListeners(); // Notify listeners when no data is found
  //       return;
  //     }
  //
  //     // Sort the data by 'game_date' before processing it
  //     data.sort((a, b) {
  //       DateTime gameDateA = DateTime.parse(a['game_date']);
  //       DateTime gameDateB = DateTime.parse(b['game_date']);
  //       return gameDateA.compareTo(gameDateB); // Ascending order
  //     });
  //
  //     Map<String, List<Map<String, dynamic>>> results = {};
  //     Set<String> newGameNames = {};
  //
  //     for (var game in data) {
  //       String shortGameName = game['short_game_name'];
  //
  //       if (!results.containsKey(shortGameName)) {
  //         results[shortGameName] = [];
  //       }
  //       results[shortGameName]?.add(game as Map<String, dynamic>);
  //       newGameNames.add(shortGameName);
  //     }
  //
  //     gameNames = newGameNames.toList();
  //     gameResults = results;
  //
  //     notifyListeners(); // Notify listeners after updating gameNames and gameResults
  //   } catch (error) {
  //     // Handle error
  //   }
  // }
  // Future<void> fetchGamesForCurrentDateOrTomorrow() async {
  //   try {
  //     if (khaiwalId.isEmpty) return;
  //
  //     final now = getLiveTime();
  //     final currentDate = DateTime.utc(now.year, now.month, now.day);
  //     final tomorrowDate = DateTime.utc(now.year, now.month, now.day + 1);
  //     final dayAfterTomorrowDate = DateTime.utc(now.year, now.month, now.day + 2); // Day after tomorrow
  //
  //     final response = await supabase
  //         .from('games')
  //         .select('id, game_date, full_game_name, game_result, open_time, close_time_min, last_big_play_min, result_time_min, pause, off_day, day_before')
  //         .eq('khaiwal_id', khaiwalId)
  //         .not('active', 'is', 'false')
  //         .gte('game_date', currentDate.toIso8601String())
  //         .lte('game_date', tomorrowDate.toIso8601String()); // Include games for today and tomorrow
  //
  //     if (response.isEmpty) {
  //       games = [];
  //       return;
  //     }
  //
  //     List<dynamic> data = response as List<dynamic>;
  //     if (data.isEmpty) {
  //       notifyListeners(); // Notify listeners when no data is found
  //       return;
  //     }
  //
  //     List<Map<String, dynamic>> gamesForCurrentDate = [];
  //
  //     for (var game in data) {
  //       DateTime gameDate = DateTime.parse(game['game_date']);
  //       bool dayBefore = game['day_before'] ?? false;
  //
  //       DateTime targetDate = dayBefore ? tomorrowDate : currentDate;
  //       if (gameDate.year == targetDate.year &&
  //           gameDate.month == targetDate.month &&
  //           gameDate.day == targetDate.day) {
  //         gamesForCurrentDate.add(game as Map<String, dynamic>);
  //       }
  //     }
  //     print('printing gamesForCurrentDate: $gamesForCurrentDate');
  //
  //     // Check the refreshDifference != 0 condition
  //     if (refreshDifference != 0) {
  //       // Check games from tomorrow
  //       for (var game in data) {
  //         // Combine gameDate and open_time to create a full DateTime
  //         DateTime gameDate = DateTime.parse(game['game_date']);
  //
  //         if (gameDate.year == tomorrowDate.year &&
  //             gameDate.month == tomorrowDate.month &&
  //             gameDate.day == tomorrowDate.day) {
  //
  //           List<String> timeParts = game['open_time'].split(':');
  //           DateTime openTime = DateTime.utc(
  //             gameDate.year,
  //             gameDate.month,
  //             gameDate.day,
  //             int.parse(timeParts[0]), // hours
  //             int.parse(timeParts[1]), // minutes
  //             int.parse(timeParts[2]), // seconds
  //           );
  //
  //           // If the open_time of the game falls between midnight and now for today, add it
  //           if (openTime.isAfter(DateTime.utc(currentDate.year, currentDate.month, currentDate.day, 0, 0, 0)) &&
  //               openTime.isBefore(currentTime)) {
  //
  //             if (game['day_before'] != true) {
  //               // Check if the game already exists by comparing full_game_name and game_date
  //               gamesForCurrentDate.removeWhere((existingGame) =>
  //               existingGame['full_game_name'] == game['full_game_name'] &&
  //                   DateTime.parse(existingGame['game_date']).year == currentDate.year &&
  //                   DateTime.parse(existingGame['game_date']).month == currentDate.month &&
  //                   DateTime.parse(existingGame['game_date']).day == currentDate.day);
  //
  //               gamesForCurrentDate.add(game as Map<String, dynamic>);
  //             } else {
  //               final responseDayAfterTomorrow = await supabase
  //                   .from('games')
  //                   .select('id, game_date, full_game_name, game_result, open_time, close_time_min, last_big_play_min, result_time_min, pause, off_day, day_before')
  //                   .eq('full_game_name', game['full_game_name'])
  //                   .eq('khaiwal_id', khaiwalId)
  //                   .not('active', 'is', 'false')
  //                   .eq('game_date', dayAfterTomorrowDate.toIso8601String());
  //
  //               // Check if the game already exists by comparing full_game_name and game_date
  //               gamesForCurrentDate.removeWhere((existingGame) =>
  //               existingGame['full_game_name'] == game['full_game_name'] &&
  //                   DateTime.parse(existingGame['game_date']).year == tomorrowDate.year &&
  //                   DateTime.parse(existingGame['game_date']).month == tomorrowDate.month &&
  //                   DateTime.parse(existingGame['game_date']).day == tomorrowDate.day);
  //
  //               // If a game is found, add it to gamesForCurrentAndTomorrow
  //               if (responseDayAfterTomorrow.isNotEmpty) {
  //                 gamesForCurrentDate.add(responseDayAfterTomorrow[0] as Map<String, dynamic>);
  //               }
  //             }
  //           }
  //         }
  //       }
  //     }
  //
  //     // Sort games by 'game_date' and 'close_time_min'
  //     gamesForCurrentDate.sort((a, b) {
  //       DateTime gameDateA = DateTime.parse(a['game_date']);
  //       DateTime gameDateB = DateTime.parse(b['game_date']);
  //
  //       // Compare 'game_date' first
  //       int dateComparison = gameDateA.compareTo(gameDateB);
  //       if (dateComparison != 0) {
  //         return dateComparison;
  //       }
  //
  //       // If 'game_date' is the same, compare 'close_time_min'
  //       int closeTimeMinA = a['close_time_min'];
  //       int closeTimeMinB = b['close_time_min'];
  //       return closeTimeMinA.compareTo(closeTimeMinB);
  //     });
  //
  //     games = gamesForCurrentDate;
  //
  //     notifyListeners(); // Notify listeners after updating games
  //   } catch (error) {
  //     // Handle error
  //   }
  // }


  Future<void> fetchGamesForCurrentDateOrTomorrow() async {
    try {
      if (khaiwalId.isEmpty) return;

      final now = getLiveTime();
      final currentDate = DateTime.utc(now.year, now.month, now.day);
      final tomorrowDate = DateTime.utc(now.year, now.month, now.day + 1);
      final dayAfterTomorrowDate = DateTime.utc(now.year, now.month, now.day + 2); // Day after tomorrow

      // First query to fetch 'id' and 'short_game_name' from 'game_info'
      final gameInfoResponse = await supabase
          .from('game_info')
          .select('id, full_game_name, open_time, big_play_min, close_time_min, result_time_min, day_before, is_active')
          .eq('khaiwal_id', khaiwalId);

      if (gameInfoResponse.isEmpty) {
        gameNames = [];
        gameResults = {};
        games = [];
        notifyListeners(); // No data found in 'game_info'
        return;
      }

      List<dynamic> gameInfoData = gameInfoResponse as List<dynamic>;

      // Function to locally limit active games
      void limitActiveGamesLocally(int limit) {
        // Find all active games
        final activeGames = gameInfoData.where((game) => game['is_active'] == true).toList();

        if (activeGames.length > limit) {
          // Sort active games by the same order used in the database (e.g., by 'id')
          activeGames.sort((a, b) => a['id'].compareTo(b['id']));

          // Deactivate games exceeding the limit
          for (int i = limit; i < activeGames.length; i++) {
            final gameToDeactivate = activeGames[i];
            final index = gameInfoData.indexWhere((game) => game['id'] == gameToDeactivate['id']);
            if (index != -1) {
              gameInfoData[index]['is_active'] = false;
            }
          }
        }
      }

      // print('printing isResetting: $isResetting');
      // print('printing superGames: $superGames');
      if (AppState().isResetting != true) {
        // Count active games
        final activeGamesCount = gameInfoData.where((game) => game['is_active'] == true).length;
        // Check if 'superGames' limit is exceeded
        if (subscription == 'super' && activeGamesCount > superGames) {
          if (sgUpdatedAt == null) {
            isResetting = true;
            // Call the RPC method to adjust 'is_active'
            final rpcResponse = await supabase.rpc(
              'limit_active_games',
              params: {'_khaiwal_id': khaiwalId},
            );

            if (rpcResponse != null) {
              // print('RPC Error: ${rpcResponse.error!.message}');
            } else {
              // print('Successfully adjusted active games to the limit: $superGames');
              limitActiveGamesLocally(superGames);
            }
          } else {
            final now1 = currentTime;
            final diff = now1.difference(sgUpdatedAt!);

            print('printing diff inHour: ${diff.inHours}');
            if (diff.inHours < 1) {
              isResetting = true;
              print('printing isResetting later: $isResetting');
            }

            if (activeGamesCount > superGames && isResetting != true) {
              // Call the RPC method to adjust 'is_active'
              final rpcResponse = await supabase.rpc(
                'limit_active_games',
                params: {'_khaiwal_id': khaiwalId},
              );

              if (rpcResponse != null) {
                print('RPC Error: ${rpcResponse.error!.message}');
              } else {
                print('Successfully adjusted active games to the limit: $superGames');
                limitActiveGamesLocally(superGames);
              }
            }
          }

        } else if (subscription == 'premium' && activeGamesCount > premiumGames) {
          if (pgUpdatedAt == null) {
            isResetting = true;
            // Call the RPC method to adjust 'is_active'
            final rpcResponse = await supabase.rpc(
              'limit_active_games',
              params: {'_khaiwal_id': khaiwalId},
            );

            if (rpcResponse != null) {
              // print('RPC Error: ${rpcResponse.error!.message}');
            } else {
              // print('Successfully adjusted active games to the limit: $premiumGames');
              limitActiveGamesLocally(premiumGames);
            }
          } else {
            final diff = now.difference(pgUpdatedAt!);

            if (diff.inHours < 1) {
              isResetting = true;
              // print('printing isResetting later: $isResetting');
            }
            // Count active games
            // final activeGamesCount = gameInfoData.where((game) => game['is_active'] == true).length;

            if (activeGamesCount > premiumGames && isResetting != true) {
              // Call the RPC method to adjust 'is_active'
              final rpcResponse = await supabase.rpc(
                'limit_active_games',
                params: {'_khaiwal_id': khaiwalId},
              );

              if (rpcResponse != null) {
                // print('RPC Error: ${rpcResponse.error!.message}');
              } else {
                // print('Successfully adjusted active games to the limit: $premiumGames');
                limitActiveGamesLocally(premiumGames);
              }
            }
          }

        }
      }

      // Create a map of info_id -> full_game_name (from game_info)
      Map<int, Map<String, dynamic>> gameInfoMap = {
        for (var info in gameInfoData)
          info['id']: {
            'full_game_name': info['full_game_name'],
            'open_time': info['open_time'],
            'big_play_min': info['big_play_min'],
            'close_time_min': info['close_time_min'],
            'result_time_min': info['result_time_min'],
            'day_before': info['day_before'],
            'is_active': info['is_active'],
          }
      };

      // Collect all info_ids to query games table
      List<int> infoIds = gameInfoMap.keys.toList();

      if (infoIds.isEmpty) {
        notifyListeners(); // No info_ids found
        return;
      }

      // Build an OR filter string for all the infoIds
      final orFilter = infoIds.map((id) => 'info_id.eq.$id').join(',');

      final response = await supabase
          .from('games')
          .select('id, info_id, game_date, game_result, pause, off_day')
          .or(orFilter)
          .gte('game_date', currentDate.toIso8601String())
          .lte('game_date', tomorrowDate.toIso8601String()); // Include games for today and tomorrow

      if (response.isEmpty) {
        games = [];
        return;
      }

      List<dynamic> data = response as List<dynamic>;
      if (data.isEmpty) {
        notifyListeners(); // Notify listeners when no data is found
        return;
      }

      List<Map<String, dynamic>> gamesForCurrentDate = [];

      for (var game in data) {
        DateTime gameDate = DateTime.parse(game['game_date']);
        bool dayBefore = gameInfoMap[game['info_id']]?['day_before'] ?? false;

        DateTime targetDate = dayBefore ? tomorrowDate : currentDate;
        if (gameDate.year == targetDate.year &&
            gameDate.month == targetDate.month &&
            gameDate.day == targetDate.day) {
          // Merge game_info details with game data
          gamesForCurrentDate.add({
            'id': game['id'],
            'info_id': game['info_id'],
            'game_date': game['game_date'],
            'game_result': game['game_result'],
            'pause': game['pause'],
            'off_day': game['off_day'],
            'full_game_name': gameInfoMap[game['info_id']]?['full_game_name'],
            'open_time': gameInfoMap[game['info_id']]?['open_time'],
            'big_play_min': gameInfoMap[game['info_id']]?['big_play_min'],
            'close_time_min': gameInfoMap[game['info_id']]?['close_time_min'],
            'result_time_min': gameInfoMap[game['info_id']]?['result_time_min'],
            'day_before': gameInfoMap[game['info_id']]?['day_before'],
            'is_active': gameInfoMap[game['info_id']]?['is_active'],
          });
        }
      }
      // Check the refreshDifference != 0 condition
      if (refreshDifference != 0) {
        // Check games from tomorrow
        for (var game in data) {
          // Combine gameDate and open_time to create a full DateTime
          DateTime gameDate = DateTime.parse(game['game_date']);

          // Fetch the game info for this game using info_id
          var gameInfo = gameInfoMap[game['info_id']];
          if (gameInfo == null) continue; // Skip if no matching game_info found

          List<String> timeParts = (gameInfo['open_time'] as String).split(':');
          DateTime openTime = DateTime.utc(
            gameDate.year,
            gameDate.month,
            gameDate.day,
            int.parse(timeParts[0]), // hours
            int.parse(timeParts[1]), // minutes
            int.parse(timeParts[2]), // seconds
          );

          // If the gameDate is tomorrow and the open_time is between midnight and now
          if (gameDate.year == tomorrowDate.year &&
              gameDate.month == tomorrowDate.month &&
              gameDate.day == tomorrowDate.day) {

            // Check if the open time falls between midnight and now for today
            if (openTime.isAfter(DateTime.utc(currentDate.year, currentDate.month, currentDate.day, 0, 0, 0)) &&
                openTime.isBefore(currentTime)) {

              // If the game is not set to 'day_before'
              if (gameInfo['day_before'] != true) {
                // Remove existing games that match the full_game_name and game_date
                gamesForCurrentDate.removeWhere((existingGame) =>
                existingGame['full_game_name'] == gameInfo['full_game_name'] &&
                    DateTime.parse(existingGame['game_date']).year == currentDate.year &&
                    DateTime.parse(existingGame['game_date']).month == currentDate.month &&
                    DateTime.parse(existingGame['game_date']).day == currentDate.day
                );

                // Merge gameInfo data with the game and add to the list
                gamesForCurrentDate.add({
                  'id': game['id'],
                  'info_id': game['info_id'],
                  'game_date': game['game_date'],
                  'game_result': game['game_result'],
                  'pause': game['pause'],
                  'off_day': game['off_day'],
                  'full_game_name': gameInfo['full_game_name'],
                  'open_time': gameInfo['open_time'],
                  'big_play_min': gameInfo['big_play_min'],
                  'close_time_min': gameInfo['close_time_min'],
                  'result_time_min': gameInfo['result_time_min'],
                  'day_before': gameInfo['day_before'],
                  'is_active': gameInfo['is_active'],
                });
              } else {
                // If the game is set to 'day_before', fetch games for the day after tomorrow
                final responseDayAfterTomorrow = await supabase
                    .from('games')
                    .select('id, info_id, game_date, game_result, pause, off_day')
                    .eq('info_id', game['info_id'])
                    .eq('game_date', dayAfterTomorrowDate.toIso8601String());

                if (responseDayAfterTomorrow.isNotEmpty) {
                  var gameDayAfterTomorrow = responseDayAfterTomorrow[0];
                  // Remove existing games that match the full_game_name and game_date for tomorrow
                  gamesForCurrentDate.removeWhere((existingGame) =>
                  existingGame['full_game_name'] == gameInfo['full_game_name'] &&
                      DateTime.parse(existingGame['game_date']).year == tomorrowDate.year &&
                      DateTime.parse(existingGame['game_date']).month == tomorrowDate.month &&
                      DateTime.parse(existingGame['game_date']).day == tomorrowDate.day
                  );

                  // Merge gameInfo data with game from day after tomorrow and add it to the list
                  gamesForCurrentDate.add({
                    'id': gameDayAfterTomorrow['id'],
                    'info_id': gameDayAfterTomorrow['info_id'],
                    'game_date': gameDayAfterTomorrow['game_date'],
                    'game_result': gameDayAfterTomorrow['game_result'],
                    'pause': gameDayAfterTomorrow['pause'],
                    'off_day': gameDayAfterTomorrow['off_day'],
                    'full_game_name': gameInfo['full_game_name'],
                    'open_time': gameInfo['open_time'],
                    'big_play_min': gameInfo['big_play_min'],
                    'close_time_min': gameInfo['close_time_min'],
                    'result_time_min': gameInfo['result_time_min'],
                    'day_before': gameInfo['day_before'],
                    'is_active': gameInfo['is_active'],
                  });
                }
              }
            }
          }
        }
      }

      // Sort games by 'game_date' and 'close_time_min'
      gamesForCurrentDate.sort((a, b) {
        DateTime gameDateA = DateTime.parse(a['game_date']);
        DateTime gameDateB = DateTime.parse(b['game_date']);

        // Compare 'game_date' first
        int dateComparison = gameDateA.compareTo(gameDateB);
        if (dateComparison != 0) {
          return dateComparison;
        }

        // Parse and calculate close times for comparison
        DateTime closeTimeA = _calculateCloseTime(a['open_time'], a['close_time_min'], currentDate);
        DateTime closeTimeB = _calculateCloseTime(b['open_time'], b['close_time_min'], currentDate);

        return closeTimeA.compareTo(closeTimeB);
      });

      games = gamesForCurrentDate;

      notifyListeners(); // Notify listeners after updating games
    } catch (error) {
      // Handle error
    }
  }

  // Helper function to calculate close time
  DateTime _calculateCloseTime(String openTime, int closeTimeMinutes, DateTime currentDate) {
    List<String> openTimeParts = openTime.split(':');
    return DateTime.utc(
      currentDate.year,
      currentDate.month,
      currentDate.day,
      int.parse(openTimeParts[0]), // hours
      int.parse(openTimeParts[1]), // minutes
      int.parse(openTimeParts[2]), // seconds
    ).add(Duration(minutes: closeTimeMinutes));
  }


  Future<void> fetchGameResultsForCurrentDayAndYesterday() async {
    try {
      if (khaiwalId.isEmpty) return;

      final now = getLiveTime();
      final currentDate = DateTime.utc(now.year, now.month, now.day);
      final tomorrowDate = DateTime.utc(now.year, now.month, now.day + 1);

      // Calculate yesterday's date
      DateTime yesterday = currentDate.subtract(const Duration(days: 1));

      // First query to fetch 'id' and 'short_game_name' from 'game_info'
      final gameInfoResponse = await supabase
          .from('game_info')
          .select('id, short_game_name, full_game_name, open_time, big_play_min, close_time_min, result_time_min, day_before, is_active')
          // .not('is_active', 'is', 'false')
          .eq('khaiwal_id', khaiwalId);

      if (gameInfoResponse.isEmpty) {
        gameNames = [];
        gameResults = {};
        games = [];
        notifyListeners(); // No data found in 'game_info'
        return;
      }

      List<dynamic> gameInfoData = gameInfoResponse as List<dynamic>;

      // Create a map of info_id -> full_game_name (from game_info)
      Map<int, Map<String, dynamic>> gameInfoMap = {
        for (var info in gameInfoData)
          info['id']: {
            'short_game_name': info['short_game_name'],
            'full_game_name': info['full_game_name'],
            'open_time': info['open_time'],
            'big_play_min': info['big_play_min'],
            'close_time_min': info['close_time_min'],
            'result_time_min': info['result_time_min'],
            'day_before': info['day_before'],
            'is_active': info['is_active'],
          }
      };

      // Collect all info_ids to query games table
      List<int> infoIds = gameInfoMap.keys.toList();
      // Build an OR filter string for all the infoIds
      final orFilter = infoIds.map((id) => 'info_id.eq.$id').join(',');

      // Fetch fresh game_results for the current day
      final responseToday = await supabase
          .from('games')
          .select('id, info_id, game_date, game_result, pause, off_day')
          .or(orFilter)
          .eq('game_date', currentDate.toIso8601String());

      // Check if all responseToday['id'] exist in gameResults (for the current date)
      bool allIdsExistInGameResults = true;
      for (var game in responseToday) {
        String gameId = game['id'].toString();
        bool gameExists = gameResults.values.any((gameList) =>
            gameList.any((existingGame) => existingGame['id'].toString() == gameId));
        if (!gameExists) {
          allIdsExistInGameResults = false;
          break;
        }
      }

      // Check if all gameResults['id'] (for the current date only) exist in responseToday['id']
      bool allIdsExistInResponseToday = true;
      for (var gameList in gameResults.values) {
        for (var game in gameList) {
          DateTime gameDate = DateTime.parse(game['game_date']);
          if (gameDate.year == currentDate.year &&
              gameDate.month == currentDate.month &&
              gameDate.day == currentDate.day) {
            String gameId = game['id'].toString();
            bool gameExistsInResponseToday = responseToday.any(
                    (todayGame) => todayGame['id'].toString() == gameId);
            if (!gameExistsInResponseToday) {
              allIdsExistInResponseToday = false;
              break;
            }
          }
        }
        if (!allIdsExistInResponseToday) break;
      }

      // If any ID does not exist in either direction, fetch data for the entire month and return
      if (!allIdsExistInGameResults || !allIdsExistInResponseToday) {
        if (kDebugMode) {
          print('returned with main methods');
        }
        // await fetchDataForCurrentMonth();
        await fetchGameNamesAndResults();
        await fetchGamesForCurrentDateOrTomorrow();

        return;
      }

      // Fetch game_results for yesterday if it's not the first day of the month
      List<dynamic> responseYesterday = [];
      if (currentDate.day != 1) {
        responseYesterday = await supabase
            .from('games')
            .select('id, info_id, game_date, game_result, off_day')
            .or(orFilter)
            .eq('game_date', yesterday.toIso8601String());
      }

      // If both responses are empty, return
      if (responseToday.isEmpty && responseYesterday.isEmpty) return;

      // Process today's data
      List<dynamic> freshDataToday = responseToday as List<dynamic>;
      Map<String, List<Map<String, dynamic>>> freshResultsForToday = {};
      for (var game in freshDataToday) {
        String shortGameName = gameInfoMap[game['info_id']]?['short_game_name'];
        if (!freshResultsForToday.containsKey(shortGameName)) {
          freshResultsForToday[shortGameName] = [];
        }
        freshResultsForToday[shortGameName]?.add({
          'id': game['id'],
          'info_id': game['info_id'],
          'game_date': game['game_date'],
          'game_result': game['game_result'],
          'short_game_name': gameInfoMap[game['info_id']]?['short_game_name'],
          'off_day': game['off_day'],
        });
      }

      // Fetch games for tomorrow only
      final responseTomorrow = await supabase
          .from('games')
          .select('id, info_id, game_date, game_result, pause, off_day')
          .or(orFilter)
          .eq('game_date', tomorrowDate.toIso8601String());

      // Process today's data
      List<dynamic> freshDataTomorrow = responseTomorrow as List<dynamic>;
      Map<String, List<Map<String, dynamic>>> freshResultsForTomorrow = {};
      for (var game in freshDataTomorrow) {
        String shortGameName = gameInfoMap[game['info_id']]?['short_game_name'];
        if (!freshResultsForTomorrow.containsKey(shortGameName)) {
          freshResultsForTomorrow[shortGameName] = [];
        }
        freshResultsForTomorrow[shortGameName]?.add({
          'id': game['id'],
          'info_id': game['info_id'],
          'game_date': game['game_date'],
          'game_result': game['game_result'],
          'short_game_name': gameInfoMap[game['info_id']]?['short_game_name'],
          'off_day': game['off_day'],
        });
      }


      // Process yesterday's data if available
      Map<String, List<Map<String, dynamic>>> freshResultsForYesterday = {};
      if (responseYesterday.isNotEmpty) {
        List<dynamic> freshDataYesterday = responseYesterday;
        for (var game in freshDataYesterday) {
          String shortGameName = gameInfoMap[game['info_id']]?['short_game_name'];
          if (!freshResultsForYesterday.containsKey(shortGameName)) {
            freshResultsForYesterday[shortGameName] = [];
          }
          freshResultsForYesterday[shortGameName]?.add({
            'id': game['id'],
            'info_id': game['info_id'],
            'game_date': game['game_date'],
            'game_result': game['game_result'],
            'pause': game['pause'],
            'off_day': game['off_day'],
            'short_game_name': gameInfoMap[game['info_id']]?['short_game_name'],
            'full_game_name': gameInfoMap[game['info_id']]?['full_game_name'],
            'open_time': gameInfoMap[game['info_id']]?['open_time'],
            'big_play_min': gameInfoMap[game['info_id']]?['big_play_min'],
            'close_time_min': gameInfoMap[game['info_id']]?['close_time_min'],
            'result_time_min': gameInfoMap[game['info_id']]?['result_time_min'],
            'day_before': gameInfoMap[game['info_id']]?['day_before'],
            'is_active': gameInfoMap[game['info_id']]?['is_active'],
          });
        }
      }

      // Update the current day and yesterday's game results in gameResults
      for (var gameName in freshResultsForToday.keys) {
        if (gameResults.containsKey(gameName)) {
          List<Map<String, dynamic>> updatedResults = gameResults[gameName]!
              .where((result) {
            final gameDate = DateTime.parse(result['game_date']);
            return !(gameDate.year == currentDate.year &&
                gameDate.month == currentDate.month &&
                gameDate.day == currentDate.day);
          }).toList(); // Keep previous days' data except current day

          updatedResults.addAll(freshResultsForToday[gameName]!); // Add fresh current day results

          // Sort by 'game_date'
          updatedResults.sort((a, b) {
            DateTime gameDateA = DateTime.parse(a['game_date']);
            DateTime gameDateB = DateTime.parse(b['game_date']);
            return gameDateA.compareTo(gameDateB);
          });

          gameResults[gameName] = updatedResults;
        } else {
          gameResults[gameName] = freshResultsForToday[gameName]!;
        }
      }

      // Update the Tomorrow day game results in gameResults
      for (var gameName in freshResultsForTomorrow.keys) {
        if (gameResults.containsKey(gameName)) {
          List<Map<String, dynamic>> updatedResults = gameResults[gameName]!
              .where((result) {
            final gameDate = DateTime.parse(result['game_date']);
            return !(gameDate.year == tomorrowDate.year &&
                gameDate.month == tomorrowDate.month &&
                gameDate.day == tomorrowDate.day);
          }).toList(); // Keep previous days' data except current day

          updatedResults.addAll(freshResultsForTomorrow[gameName]!); // Add fresh current day results

          // Sort by 'game_date'
          updatedResults.sort((a, b) {
            DateTime gameDateA = DateTime.parse(a['game_date']);
            DateTime gameDateB = DateTime.parse(b['game_date']);
            return gameDateA.compareTo(gameDateB);
          });

          gameResults[gameName] = updatedResults;
        } else {
          gameResults[gameName] = freshResultsForTomorrow[gameName]!;
        }
      }

      // Similarly update yesterday's game results
      for (var gameName in freshResultsForYesterday.keys) {
        if (gameResults.containsKey(gameName)) {
          List<Map<String, dynamic>> updatedResults = gameResults[gameName]!
              .where((result) {
            final gameDate = DateTime.parse(result['game_date']);
            return !(gameDate.year == yesterday.year &&
                gameDate.month == yesterday.month &&
                gameDate.day == yesterday.day);
          }).toList(); // Keep previous days' data except yesterday

          updatedResults.addAll(freshResultsForYesterday[gameName]!); // Add fresh yesterday results

          // Sort by 'game_date'
          updatedResults.sort((a, b) {
            DateTime gameDateA = DateTime.parse(a['game_date']);
            DateTime gameDateB = DateTime.parse(b['game_date']);
            return gameDateA.compareTo(gameDateB);
          });

          gameResults[gameName] = updatedResults;
        } else {
          gameResults[gameName] = freshResultsForYesterday[gameName]!;
        }
      }

      List<Map<String, dynamic>> todayData = [];

      for (var game in responseToday) {
        var info = gameInfoMap[game['info_id']];
        if (info != null) {
          todayData.add({
            'id': game['id'],
            'info_id': game['info_id'],
            'game_date': game['game_date'],
            'game_result': game['game_result'],
            'pause': game['pause'],
            'off_day': game['off_day'],
            'full_game_name': info['full_game_name'],
            'open_time': info['open_time'],
            'big_play_min': info['big_play_min'],
            'close_time_min': info['close_time_min'],
            'result_time_min': info['result_time_min'],
            'day_before': info['day_before'],
            'is_active': info['is_active'],
          });
        }
      }


      await mergeCurrentTomorrowData(todayData, gameInfoMap, responseTomorrow);

      // notifyListeners(); // Notify listeners after updating the results
    } catch (error) {
      // Handle error, e.g., show a snackbar with the error message
    }
  }

  // Future<void> fetchGameResultsForCurrentDayAndYesterday() async {
  //   try {
  //     if (khaiwalId.isEmpty) return;
  //
  //     final now = getLiveTime();
  //     final currentDate = DateTime.utc(now.year, now.month, now.day);
  //
  //     // Calculate yesterday's date
  //     DateTime yesterday = currentDate.subtract(const Duration(days: 1));
  //
  //     // Fetch fresh game_results for the current day
  //     final responseToday = await supabase
  //         .from('games')
  //         .select('id, game_date, short_game_name, full_game_name, game_result, open_time, close_time_min, last_big_play_min, result_time_min, pause, off_day, day_before')
  //         .eq('khaiwal_id', khaiwalId)
  //         .eq('game_date', currentDate.toIso8601String())
  //         .not('active', 'is', 'false');
  //
  //     // Check if all responseToday['id'] exist in gameResults (for the current date)
  //     bool allIdsExistInGameResults = true;
  //     for (var game in responseToday) {
  //       String gameId = game['id'].toString();
  //       bool gameExists = gameResults.values.any((gameList) =>
  //           gameList.any((existingGame) => existingGame['id'].toString() == gameId));
  //       if (!gameExists) {
  //         allIdsExistInGameResults = false;
  //         break;
  //       }
  //     }
  //
  //     // Check if all gameResults['id'] (for the current date only) exist in responseToday['id']
  //     bool allIdsExistInResponseToday = true;
  //     for (var gameList in gameResults.values) {
  //       for (var game in gameList) {
  //         DateTime gameDate = DateTime.parse(game['game_date']);
  //         if (gameDate.year == currentDate.year &&
  //             gameDate.month == currentDate.month &&
  //             gameDate.day == currentDate.day) {
  //           String gameId = game['id'].toString();
  //           bool gameExistsInResponseToday = responseToday.any(
  //                   (todayGame) => todayGame['id'].toString() == gameId);
  //           if (!gameExistsInResponseToday) {
  //             allIdsExistInResponseToday = false;
  //             break;
  //           }
  //         }
  //       }
  //       if (!allIdsExistInResponseToday) break;
  //     }
  //
  //     // If any ID does not exist in either direction, fetch data for the entire month and return
  //     if (!allIdsExistInGameResults || !allIdsExistInResponseToday) {
  //       // await fetchDataForCurrentMonth();
  //       await fetchGameNamesAndResults();
  //       await fetchGamesForCurrentDateOrTomorrow();
  //
  //       return;
  //     }
  //
  //     // Fetch game_results for yesterday if it's not the first day of the month
  //     List<dynamic> responseYesterday = [];
  //     if (currentDate.day != 1) {
  //       responseYesterday = await supabase
  //           .from('games')
  //           .select('id, game_date, short_game_name, game_result')
  //           .eq('khaiwal_id', khaiwalId)
  //           .eq('game_date', yesterday.toIso8601String())
  //           .not('active', 'is', 'false');
  //     }
  //
  //     // If both responses are empty, return
  //     if (responseToday.isEmpty && responseYesterday.isEmpty) return;
  //
  //     // Process today's data
  //     List<dynamic> freshDataToday = responseToday as List<dynamic>;
  //     Map<String, List<Map<String, dynamic>>> freshResultsForToday = {};
  //     for (var game in freshDataToday) {
  //       String shortGameName = game['short_game_name'];
  //       if (!freshResultsForToday.containsKey(shortGameName)) {
  //         freshResultsForToday[shortGameName] = [];
  //       }
  //       freshResultsForToday[shortGameName]?.add(game as Map<String, dynamic>);
  //     }
  //
  //     // Process yesterday's data if available
  //     Map<String, List<Map<String, dynamic>>> freshResultsForYesterday = {};
  //     if (responseYesterday.isNotEmpty) {
  //       List<dynamic> freshDataYesterday = responseYesterday;
  //       for (var game in freshDataYesterday) {
  //         String shortGameName = game['short_game_name'];
  //         if (!freshResultsForYesterday.containsKey(shortGameName)) {
  //           freshResultsForYesterday[shortGameName] = [];
  //         }
  //         freshResultsForYesterday[shortGameName]?.add(game as Map<String, dynamic>);
  //       }
  //     }
  //
  //     // Update the current day and yesterday's game results in gameResults
  //     for (var gameName in freshResultsForToday.keys) {
  //       if (gameResults.containsKey(gameName)) {
  //         List<Map<String, dynamic>> updatedResults = gameResults[gameName]!
  //             .where((result) {
  //           final gameDate = DateTime.parse(result['game_date']);
  //           return !(gameDate.year == currentDate.year &&
  //               gameDate.month == currentDate.month &&
  //               gameDate.day == currentDate.day);
  //         }).toList(); // Keep previous days' data except current day
  //
  //         updatedResults.addAll(freshResultsForToday[gameName]!); // Add fresh current day results
  //
  //         // Sort by 'game_date'
  //         updatedResults.sort((a, b) {
  //           DateTime gameDateA = DateTime.parse(a['game_date']);
  //           DateTime gameDateB = DateTime.parse(b['game_date']);
  //           return gameDateA.compareTo(gameDateB);
  //         });
  //
  //         gameResults[gameName] = updatedResults;
  //       } else {
  //         gameResults[gameName] = freshResultsForToday[gameName]!;
  //       }
  //     }
  //
  //     // Similarly update yesterday's game results
  //     for (var gameName in freshResultsForYesterday.keys) {
  //       if (gameResults.containsKey(gameName)) {
  //         List<Map<String, dynamic>> updatedResults = gameResults[gameName]!
  //             .where((result) {
  //           final gameDate = DateTime.parse(result['game_date']);
  //           return !(gameDate.year == yesterday.year &&
  //               gameDate.month == yesterday.month &&
  //               gameDate.day == yesterday.day);
  //         }).toList(); // Keep previous days' data except yesterday
  //
  //         updatedResults.addAll(freshResultsForYesterday[gameName]!); // Add fresh yesterday results
  //
  //         // Sort by 'game_date'
  //         updatedResults.sort((a, b) {
  //           DateTime gameDateA = DateTime.parse(a['game_date']);
  //           DateTime gameDateB = DateTime.parse(b['game_date']);
  //           return gameDateA.compareTo(gameDateB);
  //         });
  //
  //         gameResults[gameName] = updatedResults;
  //       } else {
  //         gameResults[gameName] = freshResultsForYesterday[gameName]!;
  //       }
  //     }
  //     await mergeCurrentTomorrowData(responseToday);
  //
  //     // notifyListeners(); // Notify listeners after updating the results
  //   } catch (error) {
  //     // Handle error, e.g., show a snackbar with the error message
  //   }
  // }

  // Helper method to calculate live time
  DateTime getLiveTime() {
    return refreshDifference != 0
        ? currentTime.add(Duration(minutes: refreshDifference))
        : currentTime;
  }

  Future<void> mergeCurrentTomorrowData(List<dynamic> responseToday, Map<int, Map<String, dynamic>> gameInfoMap, List<dynamic> responseTomorrow) async {
    try {
      if (khaiwalId.isEmpty) return;

      final now = getLiveTime();
      final currentDate = DateTime.utc(now.year, now.month, now.day);
      final tomorrowDate = DateTime.utc(now.year, now.month, now.day + 1);
      final dayAfterTomorrowDate = DateTime.utc(now.year, now.month, now.day + 2); // Day after tomorrow

      // First query to fetch 'id' and 'short_game_name' from 'game_info'
      // final gameInfoResponse = await supabase
      //     .from('game_info')
      //     .select('id, full_game_name, open_time, big_play_min, close_time_min, result_time_min, day_before, is_active')
      //     // .not('is_active', 'is', 'false')
      //     .eq('khaiwal_id', khaiwalId);
      //
      // if (gameInfoResponse.isEmpty) {
      //   notifyListeners(); // No data found in 'game_info'
      //   return;
      // }

      // List<dynamic> gameInfoData = gameInfoResponse;
      //
      // // Create a map of info_id -> full_game_name (from game_info)
      // Map<int, Map<String, dynamic>> gameInfoMap = {
      //   for (var info in gameInfoData)
      //     info['id']: {
      //       'short_game_name': info['short_game_name'],
      //       'full_game_name': info['full_game_name'],
      //       'open_time': info['open_time'],
      //       'big_play_min': info['big_play_min'],
      //       'close_time_min': info['close_time_min'],
      //       'result_time_min': info['result_time_min'],
      //       'day_before': info['day_before'],
      //       'is_active': info['is_active'],
      //     }
      // };

      // List<int> infoIds = gameInfoMap.keys.toList(); // Collect all info_ids to query games table
      // // Build an OR filter string for all the infoIds
      // final orFilter = infoIds.map((id) => 'info_id.eq.$id').join(',');


      // Fetch games for tomorrow only
      // final responseTomorrow = await supabase
      //     .from('games')
      //     .select('id, info_id, game_date, game_result, pause, off_day')
      //     .or(orFilter)
      //     .eq('game_date', tomorrowDate.toIso8601String());

      // If no data is found, return

      if (responseToday.isEmpty && responseTomorrow.isEmpty) {
        games = [];
        notifyListeners();
        return;
      }

      List<Map<String, dynamic>> tomorrowData = [];

      for (var game in responseTomorrow) {
        var info = gameInfoMap[game['info_id']];
        if (info != null) {
          tomorrowData.add({
            'id': game['id'],
            'info_id': game['info_id'],
            'game_date': game['game_date'],
            'game_result': game['game_result'],
            'pause': game['pause'],
            'off_day': game['off_day'],
            'short_game_name': info['short_game_name'],
            'full_game_name': info['full_game_name'],
            'open_time': info['open_time'],
            'big_play_min': info['big_play_min'],
            'close_time_min': info['close_time_min'],
            'result_time_min': info['result_time_min'],
            'day_before': info['day_before'],
            'is_active': info['is_active'],
          });
        }
      }

      // Merge responseToday and responseTomorrow
      List<dynamic> mergedData = responseToday + tomorrowData;
      // print('printing mergedData: $mergedData');

      // Process and sort the merged data
      List<Map<String, dynamic>> gamesForCurrentAndTomorrow = [];

      for (var game in mergedData) {
        DateTime gameDate = DateTime.parse(game['game_date']);
        bool dayBefore = game['day_before'] ?? false;

        DateTime targetDate = dayBefore ? tomorrowDate : currentDate;
        if (gameDate.year == targetDate.year &&
            gameDate.month == targetDate.month &&
            gameDate.day == targetDate.day) {
          gamesForCurrentAndTomorrow.add(game as Map<String, dynamic>);
        }
        // optionally added below code in this loop to avoid the loop the again
        if (refreshDifference != 0 && gameDate.year == tomorrowDate.year &&
            gameDate.month == tomorrowDate.month &&
            gameDate.day == tomorrowDate.day){

          List<String> timeParts = game['open_time'].split(':');
          DateTime openTime = DateTime.utc(
            gameDate.year,
            gameDate.month,
            gameDate.day,
            int.parse(timeParts[0]), // hours
            int.parse(timeParts[1]), // minutes
            int.parse(timeParts[2]), // seconds
          );

          // If the open_time of the game falls between midnight and now for today, add it
          if (openTime.isAfter(DateTime.utc(currentDate.year, currentDate.month, currentDate.day, 0, 0, 0)) &&
              openTime.isBefore(currentTime)) {

            if (game['day_before'] != true) {
              // Check if the game already exists by comparing full_game_name and game_date
              gamesForCurrentAndTomorrow.removeWhere((existingGame) =>
              existingGame['info_id'] == game['info_id'] &&
                  DateTime.parse(existingGame['game_date']).year == currentDate.year &&
                  DateTime.parse(existingGame['game_date']).month == currentDate.month &&
                  DateTime.parse(existingGame['game_date']).day == currentDate.day);

              gamesForCurrentAndTomorrow.add(game as Map<String, dynamic>);
            } else {
              // Fetch games for tomorrow only
              final responseDayAfterTomorrow = await supabase
                  .from('games')
                  .select('id, info_id, game_date, game_result, pause, off_day')
                  .eq('info_id', game['info_id'])
                  .eq('game_date', dayAfterTomorrowDate.toIso8601String());

              // Check if the game already exists by comparing full_game_name and game_date
              gamesForCurrentAndTomorrow.removeWhere((existingGame) =>
              existingGame['info_id'] == game['info_id'] &&
                  DateTime.parse(existingGame['game_date']).year == tomorrowDate.year &&
                  DateTime.parse(existingGame['game_date']).month == tomorrowDate.month &&
                  DateTime.parse(existingGame['game_date']).day == tomorrowDate.day);

              // If a game is found, add it to gamesForCurrentAndTomorrow
              if (responseDayAfterTomorrow.isNotEmpty) {
                for (var game in responseDayAfterTomorrow) {
                  var info = gameInfoMap[game['info_id']];
                  if (info != null) {
                    gamesForCurrentAndTomorrow.add({
                      'id': game['id'],
                      'info_id': game['info_id'],
                      'game_date': game['game_date'],
                      'game_result': game['game_result'],
                      'pause': game['pause'],
                      'off_day': game['off_day'],
                      'full_game_name': info['full_game_name'],
                      'open_time': info['open_time'],
                      'big_play_min': info['big_play_min'],
                      'close_time_min': info['close_time_min'],
                      'result_time_min': info['result_time_min'],
                      'day_before': info['day_before'],
                      'is_active': info['is_active'],
                    });
                  }
                }
              }
            }

          }
        }
      }

      // Check the refreshDifference != 0 condition
      // if (refreshDifference != 0) {
      //   // Check games from tomorrow
      //   for (var game in responseTomorrow) {
      //
      //     // Combine gameDate and open_time to create a full DateTime
      //     DateTime gameDate = DateTime.parse(game['game_date']);
      //     List<String> timeParts = game['open_time'].split(':');
      //     DateTime openTime = DateTime.utc(
      //       gameDate.year,
      //       gameDate.month,
      //       gameDate.day,
      //       int.parse(timeParts[0]), // hours
      //       int.parse(timeParts[1]), // minutes
      //       int.parse(timeParts[2]), // seconds
      //     );
      //
      //     // If the open_time of the game falls between midnight and now for today, add it
      //     if (openTime.isAfter(DateTime.utc(currentDate.year, currentDate.month, currentDate.day, 0, 0, 0)) &&
      //         openTime.isBefore(currentTime)) {
      //
      //       if (game['day_before'] != true) {
      //         // Check if the game already exists by comparing full_game_name and game_date
      //         gamesForCurrentAndTomorrow.removeWhere((existingGame) =>
      //         existingGame['full_game_name'] == game['full_game_name'] &&
      //             DateTime.parse(existingGame['game_date']).year == currentDate.year &&
      //             DateTime.parse(existingGame['game_date']).month == currentDate.month &&
      //             DateTime.parse(existingGame['game_date']).day == currentDate.day);
      //
      //         gamesForCurrentAndTomorrow.add(game as Map<String, dynamic>);
      //       } else {
      //         final responseDayAfterTomorrow = await supabase
      //             .from('games')
      //             .select('id, game_date, full_game_name, game_result, open_time, close_time_min, last_big_play_min, result_time_min, off_day, day_before')
      //             .eq('full_game_name', game['full_game_name'])
      //             .eq('khaiwal_id', khaiwalId)
      //             .not('active', 'is', 'false')
      //             .eq('game_date', dayAfterTomorrowDate.toIso8601String());
      //
      //         // Check if the game already exists by comparing full_game_name and game_date
      //         gamesForCurrentAndTomorrow.removeWhere((existingGame) =>
      //         existingGame['full_game_name'] == game['full_game_name'] &&
      //             DateTime.parse(existingGame['game_date']).year == tomorrowDate.year &&
      //             DateTime.parse(existingGame['game_date']).month == tomorrowDate.month &&
      //             DateTime.parse(existingGame['game_date']).day == tomorrowDate.day);
      //
      //         // If a game is found, add it to gamesForCurrentAndTomorrow
      //         if (responseDayAfterTomorrow.isNotEmpty) {
      //           gamesForCurrentAndTomorrow.add(responseDayAfterTomorrow[0] as Map<String, dynamic>);
      //         }
      //       }
      //
      //     }
      //   }
      // }


      // Sort games by 'game_date' and 'close_time_min'
      // Sort games by 'game_date' and 'close_time_min'
      gamesForCurrentAndTomorrow.sort((a, b) {
        DateTime gameDateA = DateTime.parse(a['game_date']);
        DateTime gameDateB = DateTime.parse(b['game_date']);

        // Compare 'game_date' first
        int dateComparison = gameDateA.compareTo(gameDateB);
        if (dateComparison != 0) {
          return dateComparison;
        }

        // Parse and calculate close times for comparison
        DateTime closeTimeA = _calculateCloseTime(a['open_time'], a['close_time_min'], currentDate);
        DateTime closeTimeB = _calculateCloseTime(b['open_time'], b['close_time_min'], currentDate);

        return closeTimeA.compareTo(closeTimeB);
      });


      games = gamesForCurrentAndTomorrow;

      notifyListeners(); // Notify listeners after updating games
    } catch (error) {
      if (kDebugMode) {
        print('in the catch $error');
      }
      // Handle error
    }
  }

  String formatGameDate(String gameDate) {
    DateTime parsedDate = DateTime.parse(gameDate);
    return DateFormat('dd-MM-yyyy').format(parsedDate);
  }

  String formatTimestamp(String timestamp) {
    // Parse the timestamp string to DateTime object
    DateTime parsedTimestamp = DateTime.parse(timestamp);
    // Format the DateTime to the desired format
    return DateFormat('d MMMM, yyyy \'at\' hh:mm a').format(parsedTimestamp);
  }


  Future<void> checkGamePlayExistence() async {

    for (var game in games) {
      final gamePlayResponse = await supabase
          .from('game_play')
          .select('id')
          .eq('game_id', game['id'])
          .limit(1);

      if (gamePlayResponse.isNotEmpty) {
        gamePlayExists[game['id']] = true;
      } else {
        gamePlayExists[game['id']] = false;
      }
    }
  }

  Future<void> fetchMenuUsers() async {
    if (menuOption == 0) {
      return;
    } else if (menuOption == 1) {
      await fetchUsers('allowed.is.true');
    } else if (menuOption == 2) {
      await fetchUsers('allowed.is.true,allowed.is.null');
    } else if (menuOption == 3) {
      await fetchUsers('allowed.is.true,allowed.is.null,allowed.is.false');
    } else if (menuOption == 4) {
      await fetchUsers('allowed.is.true,allowed.is.false');
    }
  }

  // Fetch users from khaiwals_players and profiles
  Future<void> fetchUsers(String query) async {

    // Temporary list to store fetched data
    List<Map<String, dynamic>> fetchedUsers = [];

    // Fetch users from khaiwals_players where allowed is true
    final kpResponse = await supabase
        .from('khaiwals_players')
        .select('id, player_id, balance, allowed, player_renamed')
        .eq('khaiwal_id', khaiwalId)
        .or(query);

    // Iterate over the players and fetch their profile details
    for (var player in kpResponse) {
      final playerId = player['player_id'];
      final kpId = player['id'];
      final renamed = player['player_renamed'];

      // Fetch the user profile data
      final profileResponse = await supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', playerId)
          .single();

      final kpResponse = await supabase
          .from('kp_logs')
          .select('action')
          .or('action.is.null')
          .eq('kp_id', kpId);

      // Count the number of records where action is null
      int nullActionCount = kpResponse.length;

      if (profileResponse.isNotEmpty) {
        // Combine player and profile data
        fetchedUsers.add({
          'kp_id': player['id'],
          'player_id': playerId,
          'balance': player['balance'],
          'full_name': renamed ?? profileResponse['full_name'],
          'avatar_url': profileResponse['avatar_url'],
          'null_action_count': nullActionCount,
          'allowed': player['allowed'],
          'default_name': profileResponse['full_name'],
          'is_renamed': renamed != null,
        });
      }
    }

    // Function to locally limit active users
    void limitActiveUsersLocally(int limit) {
      // Find all active users
      final activeUsers = fetchedUsers.where((kp) => kp['allowed'] == true).toList();

      if (activeUsers.length > limit) {
        // Sort active users by the same order used in the database (e.g., by 'id')
        activeUsers.sort((a, b) => a['kp_id'].compareTo(b['kp_id']));

        // Deactivate users exceeding the limit
        for (int i = limit; i < activeUsers.length; i++) {
          final userToDeactivate = activeUsers[i];
          final index = fetchedUsers.indexWhere((kp) => kp['kp_id'] == userToDeactivate['kp_id']);
          if (index != -1) {
            fetchedUsers[index]['allowed'] = null;
          }
        }
      }
    }

    if (AppState().isResetting != true) {
      // Check if 'superUsers' limit is exceeded
      if (subscription == 'super' && fetchedUsers.length > superUsers) {
        final activeUsers = fetchedUsers.where((kp) => kp['allowed'] == true).length;

        // print('printing active users: $activeUsers');
        // print('printing supers users: $superUsers');


        if (activeUsers > superUsers) {
          // Call the RPC method to adjust 'is_active'
          final rpcResponse = await supabase.rpc(
            'limit_active_users',
            params: {'_khaiwal_id': khaiwalId},
          );

          if (rpcResponse != null) {
            if (kDebugMode) {
              print('RPC Error: ${rpcResponse.error!.message}');
            }
          } else {
            if (kDebugMode) {
              print('Successfully adjusted active users to the limit: $superUsers');
            }
            limitActiveUsersLocally(superUsers);
          }
        }
      }
    }

    // Sort fetched users into three sections: true, null, false
    fetchedUsers.sort((a, b) {
      int sectionA = a['allowed'] == true
          ? 0
          : a['allowed'] == null
          ? 1
          : 2;
      int sectionB = b['allowed'] == true
          ? 0
          : b['allowed'] == null
          ? 1
          : 2;

      if (sectionA == sectionB) {
        return a['kp_id'].compareTo(b['kp_id']); // Sort by kp_id within sections
      }
      return sectionA.compareTo(sectionB); // Sort by section
    });

    // Update users list after all data is fetched
    users = fetchedUsers; // Replace the old users with the new data
    originalUsers = List.from(fetchedUsers); // Keep a copy of the original
    notifyListeners();
  }

  void updateMenuOptions() {
    // Cancel any existing timer to avoid redundant calls
    if (_menuUpdateTimer != null && _menuUpdateTimer!.isActive) {
      _menuUpdateTimer!.cancel();
    }
    // Schedule the update after a delay of 1 second
    _menuUpdateTimer = Timer(const Duration(seconds: 5), () async {
      // Update the Supabase database
      try {
        await supabase
            .from('khaiwals')
            .update({'menu_option': menuOption})
            .eq('id', khaiwalId);

      } catch (e) {
        if (kDebugMode) {
          print('Error during update: $e');
        }
      }
    });

  }

  // Fetch users from khaiwals_players and profiles
  // Future<void> fetchPendingUsers() async {
  //
  //   // Temporary list to store fetched data
  //   List<Map<String, dynamic>> fetchedUsers = [];
  //
  //   // Fetch users from khaiwals_players where allowed is true
  //   final playersResponse = await supabase
  //       .from('khaiwals_players')
  //       .select('id, player_id, balance')
  //       .eq('khaiwal_id', khaiwalId)
  //       .or('allowed.is.null');
  //
  //   // Iterate over the players and fetch their profile details
  //   for (var player in playersResponse) {
  //     final playerId = player['player_id'];
  //     final kpId = player['id'];
  //
  //     // Fetch the user profile data
  //     final profileResponse = await supabase
  //         .from('profiles')
  //         .select('full_name, avatar_url')
  //         .eq('id', playerId)
  //         .single();
  //
  //     final kpResponse = await supabase
  //         .from('kp_logs')
  //         .select('action')
  //         .or('action.is.null')
  //         .eq('kp_id', kpId);
  //
  //     // Count the number of records where action is null
  //     int nullActionCount = kpResponse.length;
  //
  //     if (profileResponse.isNotEmpty) {
  //       // Combine player and profile data
  //       fetchedUsers.add({
  //         'kp_id': player['id'],
  //         'player_id': playerId,
  //         'balance': player['balance'],
  //         'full_name': profileResponse['full_name'],
  //         'avatar_url': profileResponse['avatar_url'],
  //         'null_action_count': nullActionCount,
  //       });
  //     }
  //   }
  //   // Sort the fetchedUsers by kp_id
  //   fetchedUsers.sort((a, b) => a['kp_id'].compareTo(b['kp_id']));
  //
  //   // Update users list after all data is fetched
  //   pendingUsers = fetchedUsers; // Replace the old users with the new data
  //   pendingOriginalUsers = List.from(fetchedUsers); // Keep a copy of the original
  //   notifyListeners();
  // }
  //
  // // Fetch users from khaiwals_players and profiles
  // Future<void> fetchBlockedUsers() async {
  //
  //   // Temporary list to store fetched data
  //   List<Map<String, dynamic>> fetchedUsers = [];
  //
  //   // Fetch users from khaiwals_players where allowed is true
  //   final playersResponse = await supabase
  //       .from('khaiwals_players')
  //       .select('id, player_id, balance')
  //       .eq('khaiwal_id', khaiwalId)
  //       .eq('allowed', false);
  //
  //   // Iterate over the players and fetch their profile details
  //   for (var player in playersResponse) {
  //     final playerId = player['player_id'];
  //     final kpId = player['id'];
  //
  //     // Fetch the user profile data
  //     final profileResponse = await supabase
  //         .from('profiles')
  //         .select('full_name, avatar_url')
  //         .eq('id', playerId)
  //         .single();
  //
  //     final kpResponse = await supabase
  //         .from('kp_logs')
  //         .select('action')
  //         .or('action.is.null')
  //         .eq('kp_id', kpId);
  //
  //     // Count the number of records where action is null
  //     int nullActionCount = kpResponse.length;
  //
  //     if (profileResponse.isNotEmpty) {
  //       // Combine player and profile data
  //       fetchedUsers.add({
  //         'kp_id': player['id'],
  //         'player_id': playerId,
  //         'balance': player['balance'],
  //         'full_name': profileResponse['full_name'],
  //         'avatar_url': profileResponse['avatar_url'],
  //         'null_action_count': nullActionCount,
  //       });
  //     }
  //   }
  //
  //   // Sort the fetchedUsers by kp_id
  //   fetchedUsers.sort((a, b) => a['kp_id'].compareTo(b['kp_id']));
  //
  //   // Update users list after all data is fetched
  //   blockedUsers = fetchedUsers; // Replace the old users with the new data
  //   blockedOriginalUsers = List.from(fetchedUsers); // Keep a copy of the original
  //   notifyListeners();
  // }

  Future<void> fetchUserSettings(int kpId) async {
    // Fetch user settings from 'khaiwals_players'
    final response = await supabase
        .from('khaiwals_players')
        .select('rate, commission, balance, edit_minutes, debt_limit, big_play_limit, allowed')
        .eq('id', kpId)
        .maybeSingle();

    if (response == null) {
      // Set userSettings to an empty map if no data is returned
      userSettings = {};
      return;
    }

    // Safely cast the response to a Map
    Map<String, dynamic> data = response;

    // Fetch null actions from 'kp_logs'
    final kpResponse = await supabase
        .from('kp_logs')
        .select('action')
        .or('action.is.null')
        .eq('kp_id', kpId);

    // Count the number of records where action is null
    int nullActionCount = kpResponse.length;

    // Add null_action_count to the user settings
    data['null_action_count'] = nullActionCount;

    // Update userSettings with the combined data
    userSettings = data;
  }


  // Method to update the wallet of a user by kp_id
  void updateSelectedUserWallet(int kpId, num newWallet) {
    for (var user in users) {
      if (user['kp_id'] == kpId) {
        user['balance'] = newWallet;
        break;
      }
    }
    notifyListeners();
  }

  Future<bool> checkDeviceMismatch(BuildContext context) async {
    try {
      // Fetch the device ID from the 'khaiwals' table
      final response = await supabase
          .from('khaiwals')
          .select('device_id')
          .eq('id', khaiwalId)
          .maybeSingle();

      if (response == null || response['device_id'] != deviceId) {
        // Close any progress indicator if open
        Navigator.of(context).popUntil((route) => route.isFirst);

        // Show mismatch dialog
        await showDialog<bool>(
          context: context,
          // barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Device Mismatch'),
              content: const Text(
                  'This is not your default device. Would you like to make this device default for Master King?'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false); // User declined
                  },
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await updateDeviceId(); // Update the device ID
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Device updated successfully.')),
                      );
                    } catch (error) {
                      // Show error message
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update device: $error')),
                      );
                    }
                    Navigator.of(context).pop(true); // User accepted
                  },
                  child: const Text('Yes'),
                ),
              ],
            );
          },
        );

        await fetchGameNamesAndResults();
        await fetchGamesForCurrentDateOrTomorrow();
        // Regardless of Yes or No, stop further execution
        return true; // Indicate that a mismatch was handled
      }

      return false; // No mismatch
    } catch (error) {
      // Close any progress indicator if open
      Navigator.of(context).popUntil((route) => route.isFirst);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking device mismatch: $error')),
      );
      await fetchGameNamesAndResults();
      await fetchGamesForCurrentDateOrTomorrow();
      return true; // Indicate mismatch to halt operations
    }
  }


  // Update the device ID in the 'khaiwals' table
  Future<void> updateDeviceId() async {
    try {
      // Update the device_id column in the 'khaiwals' table
      final response = await supabase.from('khaiwals').update({
        'device_id': deviceId, // Set the current device ID
      }).eq('id', khaiwalId);

      if (response != null) {
        throw Exception('Failed to update device ID: $response');
      }

      notifyListeners(); // Notify listeners about the change
    } catch (error) {
      throw Exception('Error updating device ID: $error');
    }
  }

  void scheduleLimitUpdate(int gameId, int? limitValue) {
    // Cancel any existing timer to avoid redundant calls
    if (_limitUpdateTimer != null && _limitUpdateTimer!.isActive) {
      _limitUpdateTimer!.cancel();
    }

    // Schedule the update after a delay of 1 second
    _limitUpdateTimer = Timer(const Duration(seconds: 2), () async {
      // Update the Supabase database
      try {
        final response = await supabase
            .from('games')
            .update({'limit_check': limitValue})
            .eq('id', gameId);

        if (response != null) {
          if (kDebugMode) {
            print('Error updating limit_check: $response');
          }
        } else {
          if (kDebugMode) {
            print('Limit check updated successfully');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error during update: $e');
        }
      }
    });
  }

  void scheduleCutUpdate(int gameId, int? cutValue, int? totalCutAmount, int? finalAmount) {
    // Cancel any existing timer to avoid redundant calls
    if (_cutUpdateTimer != null && _cutUpdateTimer!.isActive) {
      _cutUpdateTimer!.cancel();
    }

    // Treat totalCutAmount and finalAmount as null if they are 0
    totalCutAmount = (totalCutAmount == 0) ? null : totalCutAmount;
    finalAmount = (finalAmount == 0) ? null : finalAmount;

    // Schedule the update after a delay of 1 second
    _cutUpdateTimer = Timer(const Duration(seconds: 2), () async {
      // Update the Supabase database
      try {
        final response = await supabase
            .from('games')
            .update({'cut_amount': cutValue, 'total_cut_amount': totalCutAmount, 'final_amount': finalAmount})
            .eq('id', gameId);

        if (response != null) {
          if (kDebugMode) {
            print('Error updating limit_check: $response');
          }
        } else {
          if (kDebugMode) {
            print('Limit check updated successfully');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error during update: $e');
        }
      }
    });
  }

  String getTimeZone() {
    DateTime now = DateTime.now();
    Duration offset = now.timeZoneOffset;

    // Calculate the absolute value of hours and minutes
    int hours = offset.inHours.abs();
    int minutes = offset.inMinutes.remainder(60).abs();

    // Determine the offset sign
    String offsetSign = offset.isNegative ? '-' : '+';

    return 'UTC $offsetSign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  Future<void> resetState() async {
    // Reset Khaiwal-related details
    khaiwalId = '';
    khaiwalName = '';
    khaiwalUserName = '';
    khaiwalEmail = '';
    khaiwalTimezone = '';
    avatarUrl = '';
    defaultRate = 90;
    refreshDifference = -360;
    menuOption = 1;

    // Reset game-related data
    gameNames.clear();
    gameResults.clear();
    games.clear();
    gamePlayExists.clear();

    // Reset users and settings
    users.clear();
    originalUsers.clear();
    userSettings.clear();

    // Reset miscellaneous fields
    subscription = '';
    granted = '';
    appAccess = null;

    // Stop any active timers
    _timer?.cancel();
    _limitUpdateTimer?.cancel();
    _cutUpdateTimer?.cancel();
    _menuUpdateTimer?.cancel();

    initialized = false;

    // Notify listeners of changes
    notifyListeners();
  }



  @override
  void dispose() {
    _timer?.cancel();  // Cancel the timer when the object is disposed
    _limitUpdateTimer?.cancel();
    _cutUpdateTimer?.cancel();
    _menuUpdateTimer?.cancel();
    super.dispose();
  }

}
