import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage, InputImageData, InputImagePlaneMetadata;

class EyeDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const EyeDetectionScreen({
    super.key,
    required this.cameras,
  });

  @override
  State<EyeDetectionScreen> createState() => _EyeDetectionScreenState();
}

class _EyeDetectionScreenState extends State<EyeDetectionScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  late FaceDetector _faceDetector;
  bool _isGameStarted = false;
  int _score = 0;
  Timer? _gameTimer;
  Timer? _stationTimer;
  String _currentStation = '';
  bool _isDebugMode = false;
  String _debugStatus = '';
  bool _isProcessing = false;
  bool _isEyesOpen = true;
  late AnimationController _animationController;
  late Animation<double> _sceneryAnimation;
  final List<String> _stations = [
    '福工大前',
    '水城',
    '二日市',
    '天拝山',
    '原田',
    '基山'
  ];
  int _currentStationIndex = 0;
  double _sceneryOffset = 0.0;
  Face? _debugFace;
  bool _wasEyesOpen = true;
  bool _isGameOver = false;
  int _consecutiveBlinkCount = 0;
  static const int MAX_CONSECUTIVE_BLINKS = 3;
  static const int GAME_DURATION_SECONDS = 30;
  static const int STATION_CHANGE_SECONDS = 5;
  static const double EYE_CLOSED_THRESHOLD = 0.2;
  static const int SCORE_PER_BLINK = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.15,
        enableLandmarks: true,
      ),
    );

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _sceneryAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animationController)
      ..addListener(() {
        setState(() {
          _sceneryOffset = _sceneryAnimation.value;
        });
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _stopCamera() async {
    if (_controller != null) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
      _controller = null;
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      print('カメラが見つかりません');
      return;
    }

    if (_controller != null) {
      await _stopCamera();
    }

    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      if (!mounted) {
        await _stopCamera();
        return;
      }

      _controller!.startImageStream((image) {
        if (!_isProcessing) {
          _processImage(image);
        }
      });
    } catch (e) {
      print('カメラの初期化エラー: $e');
      await _stopCamera();
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (!_isGameStarted && !_isDebugMode) return;
    if (_isProcessing || _isGameOver) return;

    _isProcessing = true;
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      final rotation = _controller!.description.sensorOrientation;
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.values[rotation ~/ 90],
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        setState(() {
          _debugStatus = '顔が検出されていません';
          _debugFace = null;
        });
        print('processImage: 顔が検出されていません, _isGameStarted=$_isGameStarted, _isDebugMode=$_isDebugMode');
        return;
      }

      final face = faces.first;
      if (face.leftEyeOpenProbability == null || face.rightEyeOpenProbability == null) {
        setState(() {
          _debugStatus = '目の状態を検出できません';
        });
        print('processImage: 目の状態を検出できません, _isGameStarted=$_isGameStarted, _isDebugMode=$_isDebugMode');
        return;
      }

      final isFrontCamera = _controller!.description.lensDirection == CameraLensDirection.front;
      final leftProb = isFrontCamera
          ? face.rightEyeOpenProbability ?? 1.0
          : face.leftEyeOpenProbability ?? 1.0;
      final rightProb = isFrontCamera
          ? face.leftEyeOpenProbability ?? 1.0
          : face.rightEyeOpenProbability ?? 1.0;

      final leftEyeClosed = leftProb < EYE_CLOSED_THRESHOLD;
      final rightEyeClosed = rightProb < EYE_CLOSED_THRESHOLD;
      final leftEyeOpen = !leftEyeClosed;
      final rightEyeOpen = !rightEyeClosed;

      setState(() {
        _debugStatus = '左目: ${leftEyeOpen ? "開" : "閉"}\n右目: ${rightEyeOpen ? "開" : "閉"}';
        _isEyesOpen = leftEyeOpen || rightEyeOpen;
        _debugFace = face;
      });
      print('processImage: _isGameStarted=$_isGameStarted, _isDebugMode=$_isDebugMode, left: $leftEyeOpen, right: $rightEyeOpen');

      // 「開→完全に両目が閉じた瞬間」だけ加算
      if (_isGameStarted && _wasEyesOpen && leftEyeClosed && rightEyeClosed) {
        _addScore();
        print('スコア加算!');
      }
      _wasEyesOpen = leftEyeOpen || rightEyeOpen;

      // 目が開いたら連続カウントをリセット
      if (_isEyesOpen) {
        setState(() {
          _consecutiveBlinkCount = 0;
        });
      }
    } catch (e) {
      print('画像処理エラー: $e');
      setState(() {
        _debugStatus = 'エラー: $e';
      });
    } finally {
      _isProcessing = false;
    }
  }

  void _startGame() async {
    print('ゲーム開始: _startGame() が呼び出されました');
    setState(() {
      _isGameStarted = true;
      _isGameOver = false;
      _score = 0;
      _currentStation = _stations[0];
      _currentStationIndex = 0;
      _consecutiveBlinkCount = 0;
      _wasEyesOpen = true;
    });
    print('ゲーム状態: _isGameStarted=$_isGameStarted, _isGameOver=$_isGameOver');

    await _initializeCamera();
    print('カメラ初期化完了');

    _gameTimer?.cancel();
    _gameTimer = Timer(Duration(seconds: GAME_DURATION_SECONDS), () {
      print('ゲームタイマー終了');
      if (!_isGameOver) {
        setState(() {
          _isGameOver = true;
          _isGameStarted = false;
        });
        _showGameOver();
      }
    });

    _startStationTimer();
    print('駅タイマー開始');
  }

  void _startStationTimer() {
    _stationTimer?.cancel();
    _stationTimer = Timer.periodic(Duration(seconds: STATION_CHANGE_SECONDS), (timer) {
      if (!_isGameStarted || _isGameOver) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_currentStationIndex < _stations.length - 1) {
          _currentStationIndex++;
          _currentStation = _stations[_currentStationIndex];
        } else {
          // 基山駅に到着したらゲームクリア
          _isGameOver = true;
          _isGameStarted = false;
          timer.cancel();
          _showGameClear();
        }
      });
    });
  }

  void _addScore() {
    if (!_isGameStarted || _isGameOver) return;

    setState(() {
      _score += SCORE_PER_BLINK;
      _consecutiveBlinkCount++;
      
      // 連続で目を閉じすぎるとゲームオーバー
      if (_consecutiveBlinkCount >= MAX_CONSECUTIVE_BLINKS) {
        _isGameOver = true;
        _isGameStarted = false;
        _gameTimer?.cancel();
        _stationTimer?.cancel();
        _showGameOver();
      }
    });
  }

  void _showGameOver() {
    String message = _isGameOver ? '連続で目を閉じすぎました！' : '時間切れです！';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ゲームオーバー'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 10),
            Text('スコア: $_score'),
            const SizedBox(height: 10),
            Text('連続で目を閉じた回数: $_consecutiveBlinkCount'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showGameClear() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ゲームクリア！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('基山駅に到着しました！'),
            const SizedBox(height: 10),
            Text('スコア: $_score'),
            const SizedBox(height: 10),
            Text('連続で目を閉じた回数: $_consecutiveBlinkCount'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toggleDebugMode() async {
    setState(() {
      _isDebugMode = !_isDebugMode;
      if (!_isDebugMode) {
        _debugStatus = '';
        _debugFace = null;
      }
    });
    if (_isDebugMode) {
      await _initializeCamera();
    } else {
      await _stopCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gameTimer?.cancel();
    _stationTimer?.cancel();
    _stopCamera();
    _faceDetector.close();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('build: _isGameStarted=$_isGameStarted, _isGameOver=$_isGameOver');
    return Scaffold(
      body: Stack(
        children: [
          // 背景
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.blue[900]!,
                    Colors.blue[700]!,
                  ],
                ),
              ),
            ),
          ),
          // 電車のイラスト（背景）
          Positioned(
            bottom: -50,
            left: -100,
            child: Transform.scale(
              scale: 1.5,
              child: Icon(
                Icons.train,
                size: 300,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          // メインコンテンツ
          if (!_isGameStarted && !_isDebugMode)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // タイトルアニメーション
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(seconds: 1),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: value,
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      children: [
                        const Text(
                          '目を閉じて',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(2, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '電車に乗ろう！',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(2, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        // スタートボタン
                        ElevatedButton(
                          onPressed: _isGameStarted ? null : _startGame,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.blue[900],
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 20,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 8,
                          ),
                          child: const Text(
                            'スタート',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // デバッグモードボタン
                        ElevatedButton(
                          onPressed: _toggleDebugMode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isDebugMode ? Colors.red : Colors.grey[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 30,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            _isDebugMode ? 'デバッグモード終了' : 'デバッグモード開始',
                            style: const TextStyle(
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // 説明テキスト
                  AnimatedOpacity(
                    opacity: _isGameStarted ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 500),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Column(
                        children: [
                          Text(
                            '目を閉じると景色が動きます',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            '目を開けると景色が止まります',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // デバッグモード時のカメラプレビュー
          if (_isDebugMode && _controller != null && _controller!.value.isInitialized)
            Positioned.fill(
              child: Builder(
                builder: (context) {
                  Size adjustedPreviewSize = _controller!.value.previewSize!;
                  if (MediaQuery.of(context).orientation == Orientation.portrait && adjustedPreviewSize.width > adjustedPreviewSize.height) {
                    adjustedPreviewSize = Size(adjustedPreviewSize.height, adjustedPreviewSize.width);
                  }
                  return Center(
                    child: AspectRatio(
                      aspectRatio: 1 / _controller!.value.aspectRatio,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final previewW = constraints.maxWidth;
                          final previewH = constraints.maxHeight;
                          return Stack(
                            children: [
                              CameraPreview(_controller!),
                              if (_debugFace != null)
                                CustomPaint(
                                  painter: FaceLandmarkPainter(
                                    _debugFace!,
                                    adjustedPreviewSize,
                                    _controller!.description.lensDirection == CameraLensDirection.front,
                                    previewW,
                                    previewH,
                                  ),
                                  size: Size(previewW, previewH),
                                ),
                              Positioned(
                                top: 40,
                                right: 40,
                                child: ElevatedButton(
                                  onPressed: _toggleDebugMode,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text('デバッグモード終了'),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          // ゲーム画面
          if (_isGameStarted)
            Stack(
              children: [
                // 1. カメラプレビュー（最背面）
                if (_controller != null && _controller!.value.isInitialized)
                  Positioned.fill(child: CameraPreview(_controller!)),
                // 2. 電車内イラスト
                Positioned.fill(child: CustomPaint(painter: TrainInteriorPainter())),
                // 3. 窓の外の景色アニメーション
                Positioned(
                  left: MediaQuery.of(context).size.width * 0.08,
                  top: MediaQuery.of(context).size.height * 0.18,
                  width: MediaQuery.of(context).size.width * 0.84,
                  height: MediaQuery.of(context).size.height * 0.18,
                  child: AnimatedSceneryWidget(
                    offset: _sceneryOffset,
                    isEyesOpen: _isEyesOpen,
                  ),
                ),
                // 4. 上部情報バー（駅名・残り時間・スコア）
                Positioned(
                  top: 32,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 残り時間
                      Container(
                        margin: const EdgeInsets.only(left: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.13),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.timer, color: Colors.blueGrey, size: 22),
                            const SizedBox(width: 6),
                            Text(
                              '${GAME_DURATION_SECONDS - (_gameTimer?.tick ?? 0)}秒',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 駅名（中央）
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue[800]!.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.13),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.train, color: Colors.white, size: 26),
                            const SizedBox(width: 10),
                            Text(
                              _currentStation,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // スコア（右）
                      Container(
                        margin: const EdgeInsets.only(right: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.13),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 22),
                            const SizedBox(width: 6),
                            Text(
                              '$_score',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 5. 顔認識状態表示（右下）
                Positioned(
                  right: 16,
                  bottom: 32,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _debugStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class AnimatedSceneryWidget extends StatelessWidget {
  final double offset;
  final bool isEyesOpen;
  const AnimatedSceneryWidget({
    super.key, 
    required this.offset,
    required this.isEyesOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // 空・雲
          Positioned.fill(
            child: Container(color: Colors.lightBlueAccent),
          ),
          // 雲（遠景）
          Positioned(
            left: 100 - offset * 200,
            top: 20,
            child: Icon(Icons.cloud, color: Colors.white.withOpacity(0.7), size: 60),
          ),
          Positioned(
            left: 300 - offset * 250,
            top: 50,
            child: Icon(Icons.cloud, color: Colors.white.withOpacity(0.5), size: 40),
          ),
          // 高層ビル群（遠景）
          Positioned(
            left: -offset * 100,
            bottom: 80,
            child: Row(
              children: List.generate(6, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                width: 30 + (i % 2) * 10,
                height: 80 + (i % 3) * 30,
                decoration: BoxDecoration(
                  color: Colors.blueGrey[700 + (i % 2) * 100],
                  borderRadius: BorderRadius.circular(6),
                ),
              )),
            ),
          ),
          // 中景ビル・マンション
          Positioned(
            left: 100 - offset * 300,
            bottom: 40,
            child: Row(
              children: List.generate(4, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                width: 36,
                height: 60 + (i % 2) * 20,
                decoration: BoxDecoration(
                  color: Colors.grey[400 + (i % 2) * 200],
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
          ),
          // 道路（手前）
          Positioned(
            left: -offset * 400,
            bottom: 0,
            child: Container(
              width: 600,
              height: 30,
              color: Colors.grey[800],
              child: Stack(
                children: [
                  // 白線
                  Positioned(
                    left: 20,
                    top: 13,
                    child: Container(width: 60, height: 4, color: Colors.white),
                  ),
                  Positioned(
                    left: 120,
                    top: 13,
                    child: Container(width: 60, height: 4, color: Colors.white),
                  ),
                  Positioned(
                    left: 220,
                    top: 13,
                    child: Container(width: 60, height: 4, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          // 車（手前）
          Positioned(
            left: 80 - offset * 400,
            bottom: 10,
            child: Icon(Icons.directions_car, color: Colors.red[400], size: 36),
          ),
          Positioned(
            left: 300 - offset * 400,
            bottom: 10,
            child: Icon(Icons.directions_car, color: Colors.blue[400], size: 36),
          ),
          // 電柱・木（手前）
          Positioned(
            left: 200 - offset * 400,
            bottom: 30,
            child: Column(
              children: [
                Container(width: 6, height: 40, color: Colors.brown[700]),
                Icon(Icons.park, color: Colors.green[800], size: 28),
              ],
            ),
          ),
          Positioned(
            left: 400 - offset * 400,
            bottom: 30,
            child: Column(
              children: [
                Container(width: 6, height: 40, color: Colors.brown[700]),
                Icon(Icons.park, color: Colors.green[700], size: 28),
              ],
            ),
          ),
          // 目を閉じた時の暗いオーバーレイ
          if (!isEyesOpen)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.7),
              ),
            ),
        ],
      ),
    );
  }
}

class TrainInteriorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    // 床
    paint.color = const Color(0xFFE0C9A6);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.7, size.width, size.height * 0.3), paint);
    // 壁
    paint.color = const Color(0xFFe5e5e5);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.7), paint);
    // 座席（区切りあり）
    for (int i = 0; i < 5; i++) {
      paint.color = i % 2 == 0 ? Colors.green[400]! : Colors.green[600]!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.05 + i * size.width * 0.18, size.height * 0.6, size.width * 0.16, size.height * 0.12),
          const Radius.circular(18),
        ),
        paint,
      );
    }
    // 座席端の仕切り
    paint.color = Colors.grey[700]!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.04, size.height * 0.6, 6, size.height * 0.12), paint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.92, size.height * 0.6, 6, size.height * 0.12), paint);
    // 背もたれ
    paint.color = Colors.green[700]!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.04, size.height * 0.52, size.width * 0.92, size.height * 0.09),
        const Radius.circular(18),
      ),
      paint,
    );
    // 窓枠
    paint.color = Colors.grey[400]!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.08, size.height * 0.18, size.width * 0.84, size.height * 0.18),
        const Radius.circular(18),
      ),
      paint,
    );
    // 窓ガラス
    paint.color = Colors.white.withOpacity(0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.09, size.height * 0.19, size.width * 0.82, size.height * 0.16),
        const Radius.circular(14),
      ),
      paint,
    );
    // 広告スペース
    paint.color = Colors.pink[200]!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.12, size.height * 0.13, size.width * 0.2, size.height * 0.04), paint);
    paint.color = Colors.blue[200]!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.68, size.height * 0.13, size.width * 0.2, size.height * 0.04), paint);
    // つり革（2列、奥行き感）
    paint.color = Colors.grey[400]!;
    for (int row = 0; row < 2; row++) {
      for (int i = 0; i < 6; i++) {
        final x = size.width * (0.15 + i * 0.13) + row * 10;
        final y = size.height * 0.13 + row * 18;
        // 紐
        paint.strokeWidth = 4;
        canvas.drawLine(Offset(x, y), Offset(x, y + 30), paint);
        // 輪
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 3;
        canvas.drawCircle(Offset(x, y + 40), 10, paint);
        paint.style = PaintingStyle.fill;
      }
    }
    // ドア
    paint.color = Colors.grey[600]!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.01, size.height * 0.18, 8, size.height * 0.38), paint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.97, size.height * 0.18, 8, size.height * 0.38), paint);
    // 天井照明
    paint.color = Colors.white.withOpacity(0.7);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.08), width: size.width * 0.5, height: 24), paint);
    // エアコン吹き出し口
    paint.color = Colors.grey[300]!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.35, size.height * 0.03, size.width * 0.3, 10), paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class FaceLandmarkPainter extends CustomPainter {
  final Face face;
  final Size previewSize;
  final bool isFrontCamera;
  final double displayW;
  final double displayH;
  FaceLandmarkPainter(this.face, this.previewSize, this.isFrontCamera, this.displayW, this.displayH);

  @override
  void paint(Canvas canvas, Size size) {
    // カメラプレビューの表示サイズに合わせてスケーリング
    final scaleX = displayW / previewSize.width;
    final scaleY = displayH / previewSize.height;
    final paintPoint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final paintLine = Paint()
      ..color = Colors.green
      ..strokeWidth = 2;

    Offset transform(Offset p) {
      double x = p.dx.toDouble() * scaleX;
      double y = p.dy.toDouble() * scaleY;
      if (isFrontCamera) {
        x = displayW - x;
      }
      return Offset(x, y);
    }

    for (final landmarkType in FaceLandmarkType.values) {
      final landmark = face.landmarks[landmarkType];
      if (landmark != null) {
        final offset = transform(Offset(landmark.position.x.toDouble(), landmark.position.y.toDouble()));
        canvas.drawCircle(offset, 5, paintPoint);
      }
    }
    void drawLine(FaceLandmarkType a, FaceLandmarkType b) {
      final la = face.landmarks[a];
      final lb = face.landmarks[b];
      if (la != null && lb != null) {
        final offsetA = transform(Offset(la.position.x.toDouble(), la.position.y.toDouble()));
        final offsetB = transform(Offset(lb.position.x.toDouble(), lb.position.y.toDouble()));
        canvas.drawLine(offsetA, offsetB, paintLine);
      }
    }
    drawLine(FaceLandmarkType.leftEye, FaceLandmarkType.rightEye);
    drawLine(FaceLandmarkType.leftEye, FaceLandmarkType.noseBase);
    drawLine(FaceLandmarkType.rightEye, FaceLandmarkType.noseBase);
    drawLine(FaceLandmarkType.noseBase, FaceLandmarkType.leftMouth);
    drawLine(FaceLandmarkType.noseBase, FaceLandmarkType.rightMouth);
    drawLine(FaceLandmarkType.leftMouth, FaceLandmarkType.rightMouth);
  }

  @override
  bool shouldRepaint(covariant FaceLandmarkPainter oldDelegate) => true;
} 