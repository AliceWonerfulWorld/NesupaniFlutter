import 'dart:async';
import 'package:flutter/material.dart';

class GameState extends ChangeNotifier {
  bool _isGameStarted = false;
  bool _isGameOver = false;
  int _score = 0;
  String _currentStation = '';
  int _currentStationIndex = 0;
  int _consecutiveBlinkCount = 0;
  bool _wasEyesOpen = true;
  Timer? _stationTimer;

  static const int STATION_CHANGE_SECONDS = 3;
  static const double EYE_CLOSED_THRESHOLD = 0.2;
  static const int SCORE_PER_BLINK = 10;
  static const int MAX_CONSECUTIVE_BLINKS = 5;

  final List<String> _stations = [
    '基山駅',
    'けやき台',
    '原田',
    '天拝山',
    '二日市',
    '都府楼南',
    '水城',
    '大野城',
    '春日',
    '南福岡',
    '笹原',
    '竹下',
    '博多',
    '吉塚',
    '箱崎',
    '千早',
    '香椎',
    '九産大前',
    '福工大前',
    '新宮中央'
  ];

  // Getters
  bool get isGameStarted => _isGameStarted;
  bool get isGameOver => _isGameOver;
  int get score => _score;
  String get currentStation => _currentStation;
  int get consecutiveBlinkCount => _consecutiveBlinkCount;
  List<String> get stations => List.unmodifiable(_stations);

  void startGame() {
    _isGameStarted = true;
    _isGameOver = false;
    _score = 0;
    _currentStation = _stations[0];
    _currentStationIndex = 0;
    _consecutiveBlinkCount = 0;
    _wasEyesOpen = true;
    _startStationTimer();
    notifyListeners();
  }

  void _startStationTimer() {
    _stationTimer?.cancel();
    _stationTimer = Timer.periodic(Duration(seconds: STATION_CHANGE_SECONDS), (timer) {
      if (!_isGameStarted || _isGameOver) {
        timer.cancel();
        return;
      }
      if (_currentStationIndex < _stations.length - 1) {
        _currentStationIndex++;
        _currentStation = _stations[_currentStationIndex];
      } else {
        _isGameOver = true;
        _isGameStarted = false;
        timer.cancel();
      }
      notifyListeners();
    });
  }

  void processEyeState(bool isEyesOpen, bool bothEyesClosed) {
    if (!_isGameStarted || _isGameOver) return;

    // 「開→完全に両目が閉じた瞬間」だけ加算
    if (_wasEyesOpen && bothEyesClosed) {
      _addScore();
    }
    _wasEyesOpen = isEyesOpen;

    // 目が開いたら連続カウントをリセット
    if (isEyesOpen) {
      _consecutiveBlinkCount = 0;
    }

    notifyListeners();
  }

  void _addScore() {
    _score += SCORE_PER_BLINK;
    _consecutiveBlinkCount++;
    
    if (_consecutiveBlinkCount >= MAX_CONSECUTIVE_BLINKS) {
      _isGameOver = true;
      _isGameStarted = false;
      _stationTimer?.cancel();
    }
  }

  void resetGame() {
    _isGameStarted = false;
    _isGameOver = false;
    _score = 0;
    _currentStation = '';
    _currentStationIndex = 0;
    _consecutiveBlinkCount = 0;
    _wasEyesOpen = true;
    _stationTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _stationTimer?.cancel();
    super.dispose();
  }
} 