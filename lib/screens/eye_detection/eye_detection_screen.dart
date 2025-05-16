import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:nesupani/screens/eye_detection/painters/train_interior_painter.dart';
import 'package:nesupani/screens/eye_detection/painters/face_landmark_painter.dart';
import 'package:nesupani/screens/eye_detection/widgets/animated_scenery_widget.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:js/js.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:ui' as ui;

@JS()
@anonymous
class FaceDetectionOptions {
  external factory FaceDetectionOptions();
  external dynamic get tinyFaceDetector;
}

@JS()
@anonymous
class FaceDetection {
  external factory FaceDetection();
  external dynamic get landmarks;
}

@JS('faceapi')
external dynamic get faceapi;

@JS('faceapi.nets')
external dynamic get nets;

@JS('faceapi.detectSingleFace')
external Future<FaceDetection?> detectSingleFace(dynamic input, dynamic options);

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
  Timer? _stationTimer;
  String _currentStation = '';
  bool _isDebugMode = false;
  String _debugStatus = '';
  bool _isProcessing = false;
  bool _isEyesOpen = true;
  late AnimationController _animationController;
  late Animation<double> _sceneryAnimation;
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
  int _currentStationIndex = 0;
  Face? _debugFace;
  bool _wasEyesOpen = true;
  bool _isGameOver = false;
  int _consecutiveBlinkCount = 0;
  static const int STATION_CHANGE_SECONDS = 3;
  static const double EYE_CLOSED_THRESHOLD = 0.3; // しきい値を調整
  static const int SCORE_PER_BLINK = 10;
  static const int MAX_CONSECUTIVE_BLINKS = 5;
  Timer? _webDetectTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      // viewType 'webcam-video' を登録（initStateで一度だけ）
      // ignore: undefined_prefixed_name
      ui.platformViewRegistry.registerViewFactory(
        'webcam-video',
        (int viewId) {
          final video = html.document.getElementById('webcam-video') as html.VideoElement?;
          if (video != null) {
            video.style.display = 'block';
            return video;
          } else {
            final newVideo = html.VideoElement()
              ..autoplay = true
              ..width = 640
              ..height = 480
              ..id = 'webcam-video';
            html.window.navigator.mediaDevices?.getUserMedia({'video': true}).then((stream) {
              newVideo.srcObject = stream;
            });
            html.document.body?.append(newVideo);
            return newVideo;
          }
        },
      );
    }
    _initializeCamera();
    _initializeFaceAPI();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate, // 高精度モード
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.1, // 小さい顔も検出可能に
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
          _sceneryAnimation.value;
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
    if (kIsWeb) {
      // Web用: video要素を削除
      final video = html.document.getElementById('webcam-video');
      if (video != null) {
        video.remove();
      }
      return;
    }
    if (_controller != null) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
      _controller = null;
    }
  }

  Future<void> _initializeCamera() async {
    if (kIsWeb) {
      // Web用: video要素を作成してbodyに追加
      final video = html.VideoElement()
        ..autoplay = true
        ..width = 640
        ..height = 480
        ..style.display = 'none'; // デバッグ時のみ表示したい場合はblockに
      html.window.navigator.mediaDevices?.getUserMedia({'video': true}).then((stream) {
        video.srcObject = stream;
      });
      video.id = 'webcam-video';
      // すでにvideo要素があれば追加しない
      if (html.document.getElementById('webcam-video') == null) {
        html.document.body?.append(video);
      }
      return;
    }

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
      imageFormatGroup: ImageFormatGroup.nv21,
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

  Future<void> _initializeFaceAPI() async {
    if (kIsWeb) {
      try {
        // Face-API.jsのモデルをロード
        await nets.tinyFaceDetector.loadFromUri('models');
        await nets.faceLandmark68Net.loadFromUri('models');
        await nets.faceRecognitionNet.loadFromUri('models');
        await nets.faceExpressionNet.loadFromUri('models');
        print('Face-API.js models loaded successfully');
      } catch (e) {
        print('Error loading Face-API.js models: $e');
      }
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (!_isGameStarted && !_isDebugMode) return;
    if (_isProcessing || _isGameOver) return;

    _isProcessing = true;
    try {
      if (kIsWeb) {
        // Web用の顔認識処理
        final canvas = html.CanvasElement()
          ..width = image.width
          ..height = image.height;
        final ctx = canvas.context2D;
        
        // 画像データをCanvasに描画
        final imageData = ctx.createImageData(image.width, image.height);
        imageData.data.setAll(0, image.planes[0].bytes);
        ctx.putImageData(imageData, 0, 0);

        // Face-API.jsで顔を検出
        final detection = await detectSingleFace(
          canvas,
          nets.tinyFaceDetector.options,
        );

        if (detection == null) {
          setState(() {
            _debugStatus = '顔が検出されていません';
            _debugFace = null;
          });
          return;
        }

        // 目の状態を取得
        final landmarks = detection.landmarks;
        final leftEye = _getEyePoints(landmarks, true);
        final rightEye = _getEyePoints(landmarks, false);
        
        // 目の開閉状態を判定
        final leftEyeOpen = _isEyeOpen(leftEye);
        final rightEyeOpen = _isEyeOpen(rightEye);

        setState(() {
          _debugStatus = '左目: ${leftEyeOpen ? "開" : "閉"}\n右目: ${rightEyeOpen ? "開" : "閉"}';
          _isEyesOpen = leftEyeOpen || rightEyeOpen;
        });

        if (_isGameStarted && _wasEyesOpen && !leftEyeOpen && !rightEyeOpen) {
          _addScore();
        }
        _wasEyesOpen = leftEyeOpen || rightEyeOpen;

        if (_isEyesOpen) {
          setState(() {
            _consecutiveBlinkCount = 0;
          });
        }
      } else {
        // 既存のモバイル用顔認識処理
        final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
        final rotation = _controller!.description.sensorOrientation;

        // デバッグログを追加
        print('Processing image with width: ${image.width}, height: ${image.height}');

        final inputImage = InputImage.fromBytes(
          bytes: image.planes[0].bytes,
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
            ? face.rightEyeOpenProbability ?? 1.0 // フロントカメラの場合、左右を入れ替え
            : face.leftEyeOpenProbability ?? 1.0;
        final rightProb = isFrontCamera
            ? face.leftEyeOpenProbability ?? 1.0 // フロントカメラの場合、左右を入れ替え
            : face.rightEyeOpenProbability ?? 1.0;

        final leftEyeClosed = leftProb < EYE_CLOSED_THRESHOLD;
        final rightEyeClosed = rightProb < EYE_CLOSED_THRESHOLD;

        // デバッグログを追加
        print('Left Eye Probability: $leftProb, Closed: $leftEyeClosed');
        print('Right Eye Probability: $rightProb, Closed: $rightEyeClosed');

        final leftEyeOpen = !leftEyeClosed;
        final rightEyeOpen = !rightEyeClosed;

        setState(() {
          _debugStatus = '左目: ${leftEyeOpen ? "開" : "閉"}\n右目: ${rightEyeOpen ? "開" : "閉"}';
          _isEyesOpen = leftEyeOpen || rightEyeOpen; // 両目が閉じた場合のみ閉じたと判定
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

  List<Map<String, double>> _getEyePoints(dynamic landmarks, bool isLeftEye) {
    final points = <Map<String, double>>[];
    final start = isLeftEye ? 36 : 42;
    final end = isLeftEye ? 41 : 47;
    
    for (var i = start; i <= end; i++) {
      final point = landmarks.getPoint(i);
      points.add({
        'x': point.x.toDouble(),
        'y': point.y.toDouble(),
      });
    }
    return points;
  }

  bool _isEyeOpen(List<Map<String, double>> eyePoints) {
    if (eyePoints.length < 6) return true;
    
    // 目の高さと幅の比率を計算
    final height = (eyePoints[1]['y']! - eyePoints[5]['y']!).abs();
    final width = (eyePoints[0]['x']! - eyePoints[3]['x']!).abs();
    final ratio = height / width;
    
    // 比率が一定値より小さい場合は目が開いていると判定
    return ratio > 0.25;
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
          // 福工大前から新宮中央に切り替わる瞬間にゲームオーバー
          if (_currentStation == '福工大前' && _stations[_currentStationIndex + 1] == '新宮中央') {
            _isGameOver = true;
            _isGameStarted = false;
            timer.cancel();
            _showGameOver(message: '福工大前を通り過ぎ、新宮中央に到達しました！');
          } else {
            _currentStationIndex++;
            _currentStation = _stations[_currentStationIndex];
          }
        } else {
          _isGameOver = true;
          _isGameStarted = false;
          timer.cancel();
          _showGameOver(message: '終点の${_stations.last}を通り過ぎました！');
        }
      });
    });
  }

  void _addScore() {
    if (!_isGameStarted || _isGameOver) return;

    setState(() {
      _score += SCORE_PER_BLINK;
      _consecutiveBlinkCount++;
      
      if (_consecutiveBlinkCount >= MAX_CONSECUTIVE_BLINKS) {
        _isGameOver = true;
        _isGameStarted = false;
        _stationTimer?.cancel();
        _showGameOver(message: '連続で目を閉じすぎました！');
      }
    });
  }

  void _resetToTitle() {
    setState(() {
      _isGameStarted = false;
      _isGameOver = false;
      _score = 0;
      _currentStation = '';
      _currentStationIndex = 0;
      _consecutiveBlinkCount = 0;
      _wasEyesOpen = true;
      _isDebugMode = false; 
      _debugStatus = '';
      _debugFace = null;
    });
    _stationTimer?.cancel();
    _stopCamera(); 
  }

  void _showGameOver({String? message, bool isClear = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isClear
                  ? [Color(0xFFFFF8E1), Color(0xFFFFECB3)]
                  : [Color(0xFFF8BBD0), Color(0xFFF48FB1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isClear ? Icons.emoji_events : Icons.sentiment_very_dissatisfied,
                color: isClear ? Colors.amber[800] : Colors.redAccent,
                size: 60,
              ),
              const SizedBox(height: 16),
              Text(
                isClear ? 'ゲームクリア！' : 'ゲームオーバー',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: isClear ? Colors.amber[800] : Colors.redAccent,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                message ?? (isClear ? 'おめでとうございます！' : 'また挑戦してね！'),
                style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: isClear ? Colors.amber[100] : Colors.pink[100],
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.orange, size: 28),
                    const SizedBox(width: 8),
                    const Text(
                      'SCORE',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$_score',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _resetToTitle();
                },
                icon: const Icon(Icons.home),
                label: const Text('タイトルへ戻る'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isClear ? Colors.amber : Colors.pinkAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  elevation: 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startWebFaceDetectionLoop() {
    _webDetectTimer?.cancel();
    _webDetectTimer = Timer.periodic(Duration(milliseconds: 300), (_) async {
      final video = html.document.getElementById('webcam-video') as html.VideoElement?;
      if (video != null && video.readyState == 4) {
        final canvas = html.CanvasElement(width: video.videoWidth, height: video.videoHeight);
        final ctx = canvas.context2D;
        ctx.drawImage(video, 0, 0);
        try {
          final detection = await detectSingleFace(canvas, nets.tinyFaceDetector.options);
          setState(() {
            _debugStatus = detection != null ? '顔検出！' : '顔なし';
          });
        } catch (e) {
          setState(() {
            _debugStatus = 'エラー: $e';
          });
        }
      }
    });
  }

  void _stopWebFaceDetectionLoop() {
    _webDetectTimer?.cancel();
    _webDetectTimer = null;
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
      if (kIsWeb) {
        // video要素がなければ生成
        var video = html.document.getElementById('webcam-video') as html.VideoElement?;
        if (video == null) {
          video = html.VideoElement()
            ..autoplay = true
            ..width = 640
            ..height = 480
            ..id = 'webcam-video';
          await html.window.navigator.mediaDevices?.getUserMedia({'video': true}).then((stream) {
            video!.srcObject = stream;
          });
          html.document.body?.append(video);
        }
        setState(() {});
        _startWebFaceDetectionLoop();
      } else {
        await _initializeCamera();
      }
    } else {
      if (kIsWeb) {
        _stopWebFaceDetectionLoop();
        // video要素のストリーム停止と削除
        var video = html.document.getElementById('webcam-video') as html.VideoElement?;
        if (video != null) {
          video.pause();
          video.srcObject = null;
          video.remove();
        }
      }
      await _stopCamera();
    }
  }

  void _showHowToPlayDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, color: Colors.blueAccent, size: 48),
                const SizedBox(height: 12),
                const Text(
                  '遊び方',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                const SizedBox(height: 18),
                _howToRow(Icons.remove_red_eye, '目を閉じると電車が進みます！'),
                const SizedBox(height: 12),
                _howToRow(Icons.star, '長く目を閉じるほどスコアUP！'),
                const SizedBox(height: 12),
                _howToRow(Icons.train, '降りたい駅で「降りる！」ボタンを押そう！'),
                const SizedBox(height: 12),
                _howToRow(Icons.warning_amber, '寝過ごしや連続で目を閉じすぎるとゲームオーバー！'),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('閉じる'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _howToRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.orange, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.4),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stationTimer?.cancel();
    _stopCamera();
    _faceDetector.close();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                          '寝過ごしパニック',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2.5,
                            fontFamily: 'Roboto',
                            shadows: [
                              Shadow(
                                color: Colors.black38,
                                offset: Offset(2, 2),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'STAGE3',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.amber[300],
                            letterSpacing: 8,
                            fontFamily: 'RobotoMono',
                            shadows: const [
                              Shadow(
                                color: Colors.black54,
                                offset: Offset(0, 3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
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
                        ElevatedButton.icon(
                          onPressed: () => _showHowToPlayDialog(context),
                          icon: const Icon(Icons.help_outline),
                          label: const Text('遊び方'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            elevation: 6,
                          ),
                        ),
                        const SizedBox(height: 20),
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
                            '寝過ごさないように気をつけろ！',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            '目を閉じてる時間が長いほどスコアUP！',
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
          if (_isDebugMode)
            if (kIsWeb)
              Positioned.fill(
                child: Stack(
                  children: [
                    HtmlElementView(viewType: 'webcam-video'),
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
                ),
              )
            else if (_controller != null && _controller!.value.isInitialized)
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
            Builder(
              builder: (context) {
                final windowRect = TrainInteriorPainter.getWindowRect(MediaQuery.of(context).size);
                return Stack(
                  children: [
                    // 電車内のイラスト（背景）
                    Positioned.fill(
                      child: CustomPaint(
                        painter: TrainInteriorPainter(
                          offset: _sceneryAnimation.value,
                          isEyesOpen: _isEyesOpen,
                        ),
                      ),
                    ),
                    // 窓の外の景色アニメーション（窓の内側だけにクリップ）
                    Positioned(
                      left: windowRect.left,
                      top: windowRect.top,
                      width: windowRect.width,
                      height: windowRect.height,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedSceneryWidget(
                          offset: _sceneryAnimation.value,
                          isEyesOpen: _isEyesOpen,
                        ),
                      ),
                    ),
                    // 駅名表示とスコア表示（上部中央に縦並びカード風）
                    Positioned(
                      top: 24,
                      left: 32,
                      right: 32,
                      child: Column(
                        children: [
                          // 駅名カード
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.train, color: Colors.blueAccent, size: 30),
                                const SizedBox(width: 14),
                                Text(
                                  _currentStation,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueAccent,
                                    letterSpacing: 2,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black26,
                                        offset: Offset(1, 2),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // スコアバッジ
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amberAccent,
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, color: Colors.white, size: 24),
                                const SizedBox(width: 8),
                                const Text(
                                  'SCORE',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '$_score',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 顔認識状態表示（右下）
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
                    // タイトルへ戻るボタン (左上に丸く浮かせる)
                    Positioned(
                      top: 32,
                      left: 17,
                      child: Material(
                        color: Colors.white.withOpacity(0.85),
                        shape: const CircleBorder(),
                        elevation: 6,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.blueAccent, size: 28),
                          onPressed: _resetToTitle,
                          tooltip: 'タイトルへ',
                        ),
                      ),
                    ),
                    // 降りる!ボタン（下中央に大きく）
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 32,
                      left: MediaQuery.of(context).size.width * 0.5 - 100,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (_currentStation == '福工大前') {
                            _isGameOver = true;
                            _isGameStarted = false;
                            _stationTimer?.cancel();
                            _showGameOver(message: 'ゲームクリア！福工大前で降りました！', isClear: true);
                          } else {
                            _isGameOver = true;
                            _isGameStarted = false;
                            _stationTimer?.cancel();
                            _showGameOver(message: '${_currentStation}で降りてしまいました。ゲームオーバー！');
                          }
                        },
                        icon: const Icon(Icons.directions_walk, color: Colors.white, size: 28),
                        label: const Text(
                          '降りる！',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                          ),
                          elevation: 12,
                          shadowColor: Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}