import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class RaceSessionTime {
  const RaceSessionTime({required this.name, required this.start});

  final String name;
  final DateTime start;
}

class RaceWeekend {
  const RaceWeekend({
    required this.round,
    required this.name,
    required this.locality,
    required this.country,
    required this.sessions,
  });

  final String round;
  final String name;
  final String locality;
  final String country;
  final List<RaceSessionTime> sessions;
}

class RaceScheduleService {
  RaceScheduleService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<RaceWeekend>> loadSeason(int year) async {
    final uri = Uri.parse(
      'https://api.jolpi.ca/ergast/f1/$year.json?limit=100',
    );
    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'FreeF1-Cockpit/1.0',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Schedule service returned HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException('Unexpected schedule response.');
      }
      final mrData = decoded['MRData'];
      if (mrData is! Map) throw const FormatException('Missing schedule data.');
      final raceTable = mrData['RaceTable'];
      if (raceTable is! Map || raceTable['Races'] is! List) {
        throw const FormatException('Missing race list.');
      }

      const sessionKeys = <String, String>{
        'FirstPractice': 'Practice 1',
        'SecondPractice': 'Practice 2',
        'ThirdPractice': 'Practice 3',
        'SprintQualifying': 'Sprint qualifying',
        'SprintShootout': 'Sprint qualifying',
        'Sprint': 'Sprint',
        'Qualifying': 'Qualifying',
        'Race': 'Race',
      };

      final weekends = <RaceWeekend>[];
      for (final rawRace in raceTable['Races'] as List) {
        if (rawRace is! Map) continue;
        final race = Map<String, dynamic>.from(rawRace);
        final sessions = <RaceSessionTime>[];
        for (final entry in sessionKeys.entries) {
          final rawSession = race[entry.key];
          if (rawSession is! Map) continue;
          final row = Map<String, dynamic>.from(rawSession);
          final date = row['date']?.toString() ?? '';
          if (date.isEmpty) continue;
          final time = row['time']?.toString() ?? '';
          final parsed = DateTime.tryParse(
            time.isEmpty ? '${date}T00:00:00Z' : '${date}T$time',
          );
          if (parsed != null) {
            sessions.add(RaceSessionTime(name: entry.value, start: parsed));
          }
        }
        sessions.sort((a, b) => a.start.compareTo(b.start));
        final circuit = race['Circuit'];
        final location = circuit is Map ? circuit['Location'] : null;
        final place = location is Map ? location : const <String, dynamic>{};
        if (sessions.isEmpty) continue;
        weekends.add(
          RaceWeekend(
            round: race['round']?.toString() ?? '',
            name: race['raceName']?.toString() ?? 'Grand Prix',
            locality: place['locality']?.toString() ?? '',
            country: place['country']?.toString() ?? '',
            sessions: List.unmodifiable(sessions),
          ),
        );
      }
      return List.unmodifiable(weekends);
    } on TimeoutException {
      throw Exception('Race times took too long to load.');
    } on http.ClientException {
      throw Exception('Could not reach the race schedule service.');
    }
  }

  void dispose() => _client.close();
}
