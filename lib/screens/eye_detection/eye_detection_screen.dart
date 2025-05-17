import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mlkit_fd; // Alias to avoid conflict
import 'package:nesupani/screens/eye_detection/painters/train_interior_painter.dart';
import 'package:nesupani/screens/eye_detection/painters/face_landmark_painter.dart';
import 'package:nesupani/screens/eye_detection/widgets/animated_scenery_widget.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:js/js.dart' as packageJs; // Renamed alias to avoid conflict
import 'dart:js' as dartJs; // Added for allowInterop
import 'package:universal_html/html.dart' as html;
import 'dart:ui' as ui;
import 'dart:js_util' as js_util;
import 'dart:ui_web' if (dart.library.io) 'dart:ui' as ui_web;

// MediaPipe Task objects will be handled by js_util typically,
// but if direct JS interop with @JS is needed for some structures, keep js.dart.

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
  late mlkit_fd.FaceDetector _faceDetector; // For mobile
  
  // For MediaPipe Web
  dynamic _mediaPipeFaceDetector; // Stores the MediaPipe FaceDetector task instance
  bool _isMediaPipeInitialized = false;
  bool _isMediaPipeInitializing = false; // 初期化処理中フラグを追加

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
  
  // スコア計算に関する変数
  bool _wasEyesClosedDuringStation = false; // 現在の駅で目を閉じていたか
  int _consecutiveStationsWithEyesClosed = 0; // 連続で目を閉じていた駅の数
  static const int STATION_BASE_SCORE = 10; // 基本点（駅ごと）
  static const double CONSECUTIVE_BONUS_MULTIPLIER = 0.5; // 連続ボーナス係数
  
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
  mlkit_fd.Face? _debugFace; // For mobile
  dynamic _mediaPipeDebugResult; // For web
  bool _wasEyesOpen = true;
  bool _isGameOver = false;
  int _consecutiveBlinkCount = 0;
  static const int STATION_CHANGE_SECONDS = 3;
  static const double EYE_CLOSED_THRESHOLD = 0.3; // This might need adjustment for MediaPipe
  static const int SCORE_PER_BLINK = 10;
  static const int MAX_CONSECUTIVE_BLINKS = 5;
  Timer? _webDetectTimer;
  // bool _areFaceAPILoaded = false; // Remove this, use _isMediaPipeInitialized

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      _initializeMediaPipe();
      // Use ui_web.platformViewRegistry for web
      ui_web.platformViewRegistry.registerViewFactory(
        'webcam-video',
        (int viewId) {
          var video = html.document.getElementById('webcam-video') as html.VideoElement?;
          if (video == null) {
            video = html.VideoElement()
              ..id = 'webcam-video'
              ..autoplay = true
              ..style.display = 'none'; 
            html.document.body?.append(video);
          }
          return video;
        },
      );
    }
    _initializeCamera(); 

    // Mobile face detector initialization
    _faceDetector = mlkit_fd.FaceDetector(
      options: mlkit_fd.FaceDetectorOptions(
        performanceMode: mlkit_fd.FaceDetectorMode.accurate,
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.1,
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
        if (mounted) {
          setState(() {
            // This will trigger a repaint when animation value changes
          });
        }
      });
  }

  Future<void> _initializeMediaPipe() async {
    if (!kIsWeb) return;
    if (_isMediaPipeInitialized || _isMediaPipeInitializing) { // 既に初期化済みか初期化中なら何もしない
      print('MediaPipe already initialized or is initializing. Skipping.');
      return;
    }
    _isMediaPipeInitializing = true; // 初期化処理開始
    print('Starting MediaPipe initialization process...');

    try {
      print('Initializing MediaPipe Face Detector...');

      // MyMediaPipeGlobal が利用可能になるまで少し待つ (最大5秒程度)
      dynamic myMediaPipeGlobalJs;
      for (int i = 0; i < 100; i++) { // 100ms * 100 = 10秒
        myMediaPipeGlobalJs = js_util.getProperty(html.window, 'MyMediaPipeGlobal');
        if (myMediaPipeGlobalJs != null && js_util.hasProperty(myMediaPipeGlobalJs, 'FilesetResolver')) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (myMediaPipeGlobalJs == null) {
        print("エラー: MyMediaPipeGlobal が window オブジェクトに見つかりません (タイムアウト後)。");
        _debugStatus = 'MediaPipeグローバルオブジェクト未検出(T)';
        if (mounted) setState(() {});
        return;
      }

      final filesetResolverClass = js_util.getProperty(myMediaPipeGlobalJs, 'FilesetResolver');
      if (filesetResolverClass == null) {
        print("エラー: FilesetResolver が MyMediaPipeGlobal に見つかりません。");
        _debugStatus = 'MediaPipe FilesetResolver未検出';
        if (mounted) setState(() {});
        return;
      }

      // FaceDetectorの代わりにFaceLandmarkerを使用
      final faceLandmarkerClass = js_util.getProperty(myMediaPipeGlobalJs, 'FaceLandmarker');
      if (faceLandmarkerClass == null) {
        print("エラー: FaceLandmarker が MyMediaPipeGlobal に見つかりません。");
        _debugStatus = 'MediaPipe FaceLandmarker API未検出';
        if (mounted) setState(() {});
        return;
      }

      print('MediaPipe Global objects (FilesetResolver, FaceLandmarker) found.');

      // Step 1: Create a FilesetResolver for Vision Tasks
      final filesetResolver = await js_util.promiseToFuture(
        js_util.callMethod(filesetResolverClass, 'forVisionTasks', [
          // WASMファイルのパス
          'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.9/wasm' // バージョンを0.10.9に固定
        ])
      );

      if (filesetResolver == null) {
        print('MediaPipe FilesetResolver の作成に失敗しました。');
        _debugStatus = 'MediaPipe FilesetResolver作成失敗';
        if (mounted) setState(() {});
        return;
      }
      print('MediaPipe FilesetResolver created successfully.');

      // Step 2: Create FaceLandmarker with options
      final faceDetectorOptions = js_util.newObject();
      final baseOptions = js_util.newObject();
      js_util.setProperty(baseOptions, 'modelAssetPath', 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task');
      js_util.setProperty(baseOptions, 'delegate', 'GPU'); // または 'CPU'
      js_util.setProperty(faceDetectorOptions, 'baseOptions', baseOptions);
      js_util.setProperty(faceDetectorOptions, 'outputFaceBlendshapes', true); // 表情認識のための出力を有効化
      js_util.setProperty(faceDetectorOptions, 'numFaces', 1); // 検出する顔の数（1人分で十分）
      js_util.setProperty(faceDetectorOptions, 'runningMode', 'VIDEO'); // VIDEOモード

      // FaceLandmarkerを作成
      _mediaPipeFaceDetector = await js_util.promiseToFuture(
        js_util.callMethod(faceLandmarkerClass, 'createFromOptions', [filesetResolver, faceDetectorOptions])
      );

      if (_mediaPipeFaceDetector != null) {
        print('MediaPipe Face Landmarker instance created successfully.');
        _isMediaPipeInitialized = true;
        _debugStatus = 'MediaPipe 初期化完了';

        // FaceDetectorインスタンス作成後、少し待機してみる (例: 1秒)
        print('Waiting a bit after FaceLandmarker creation (1 second)...');
        await Future.delayed(const Duration(seconds: 1));
        print('Finished waiting after FaceLandmarker creation.');
      } else {
        print('MediaPipe Face Landmarker の初期化に失敗しました (detector is null)。');
        _debugStatus = 'MediaPipe 初期化失敗 (detector null)';
      }
    } catch (e, s) {
      print('MediaPipe 初期化エラー: $e\n$s');
      _debugStatus = 'MediaPipe 初期化エラー: $e';
    } finally {
      _isMediaPipeInitializing = false; // 初期化処理完了
      if (mounted) {
        setState(() {});
      }
    }
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
      var video = html.document.getElementById('webcam-video') as html.VideoElement?;
      if (video == null) {
        video = html.VideoElement()
          ..autoplay = true
          ..width = 640 // 明示的なサイズ設定が役立つことがある
          ..height = 480
          ..style.display = 'none';
        video.id = 'webcam-video';
        html.document.body?.append(video);
      }

      try {
        final stream = await html.window.navigator.mediaDevices?.getUserMedia({'video': true});
        if (stream != null) {
          video.srcObject = stream;
          await video.onLoadedMetadata.first; // メタデータがロードされるまで待つ
          print('Webcam stream acquired and metadata loaded for video element.');

          // videoWidth と videoHeight が利用可能になるまで待機 (最大5秒程度)
          int attempts = 0;
          while ((video.videoWidth == null || video.videoWidth == 0 || video.videoHeight == null || video.videoHeight == 0) && attempts < 50) {
            await Future.delayed(const Duration(milliseconds: 100));
            attempts++;
          }
          print('Video dimensions available after $attempts attempts: width=${video.videoWidth}, height=${video.videoHeight}');

          if (video.videoWidth == null || video.videoWidth == 0 || video.videoHeight == null || video.videoHeight == 0) {
            print('Failed to get video dimensions after waiting.');
            _debugStatus = 'Webcam dimensions not available.';
            if (mounted) setState(() {});
            // ここで早期リターンするか、エラー処理を継続するか検討
          } else {
            // MediaPipeが初期化済みで、ゲームが開始されている or デバッグモードならループ開始
            if ((_isGameStarted || _isDebugMode) && _isMediaPipeInitialized && _mediaPipeFaceDetector != null) {
                 print('Camera initialized and conditions met, starting web face detection loop from _initializeCamera.');
                _startWebFaceDetectionLoop();
            } else {
                 print('Camera initialized but conditions not met to start loop from _initializeCamera (isGameStarted: $_isGameStarted, isDebugMode: $_isDebugMode, isMediaPipeInitialized: $_isMediaPipeInitialized)');
            }
          }
        } else {
          print('Failed to get webcam stream.');
          _debugStatus = 'Webcam stream acquisition failed.';
          if (mounted) setState(() {});
        }
      } catch (e) {
        print('Error initializing webcam for web: $e');
        _debugStatus = 'Webcam initialization error: $e';
        if (mounted) setState(() {});
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

  Future<void> _processImage(CameraImage image) async {
    if (!_isGameStarted && !_isDebugMode) return;
    if (_isProcessing || _isGameOver) return;

    _isProcessing = true;
    try {
      if (kIsWeb) {
        // Web用の顔認識処理 - MediaPipeに置き換えるため、古いface-api.jsコードは削除
        if (!_isMediaPipeInitialized || _mediaPipeFaceDetector == null) {
          _debugStatus = 'MediaPipe未初期化';
          if(mounted) setState(() {});
          _isProcessing = false;
          return;
        }
        
        final videoElement = html.document.getElementById('webcam-video') as html.VideoElement?;
        if (videoElement == null || videoElement.readyState != 4 || videoElement.videoWidth == 0 || videoElement.videoHeight == 0) {
           if(mounted) {
            setState(() {
              _debugStatus = 'Webcam video not ready for MediaPipe.';
            });
           }
          _isProcessing = false;
          return;
        }

        // TODO: Implement MediaPipe detection call here
        // final num frameTime = html.window.performance.now(); // Example timestamp
        // js_util.callMethod(_mediaPipeFaceDetector, 'detectForVideo', [videoElement, frameTime]);
        // Detection results will be handled by a listener or callback if configured, 
        // or directly if detectForVideo returns results synchronously (less common for video).
        // For now, just a placeholder:
        _debugStatus = 'MediaPipe detecting...';
        if (mounted) setState(() {});

        // Mock processing to allow game logic to proceed for testing UI
        // This section needs to be replaced with actual MediaPipe result processing.
        // setState(() {
        //   _isEyesOpen = true; // Assume open for now
        //   _consecutiveBlinkCount = 0;
        //   _mediaPipeDebugResult = null; // Store actual result here
        // });

      } else {
        // 既存のモバイル用顔認識処理 (google_mlkit_face_detection)
        final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
        final rotation = _controller!.description.sensorOrientation;

        print('Processing image with width: ${image.width}, height: ${image.height}');

        final inputImage = mlkit_fd.InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: mlkit_fd.InputImageMetadata(
            size: imageSize,
            rotation: mlkit_fd.InputImageRotation.values[rotation ~/ 90],
            format: mlkit_fd.InputImageFormat.nv21, // Ensure this matches your CameraImage format
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

        final leftEyeOpen = !leftEyeClosed;
        final rightEyeOpen = !rightEyeClosed;

        setState(() {
          _debugStatus = '左目: ${leftEyeOpen ? "開" : "閉"}\n右目: ${rightEyeOpen ? "開" : "閉"}';
          _isEyesOpen = leftEyeOpen || rightEyeOpen;
          _debugFace = face;
        });
        print('processImage: _isGameStarted=$_isGameStarted, _isDebugMode=$_isDebugMode, left: $leftEyeOpen, right: $rightEyeOpen');

        if (_isGameStarted && _wasEyesOpen && leftEyeClosed && rightEyeClosed) {
          _addScore();
          print('スコア加算!');
        }
        _wasEyesOpen = leftEyeOpen || rightEyeOpen;

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

  List<Map<String, double>> _getEyePointsWeb(dynamic landmarks, bool isLeftEye) {
    // face-api.jsのlandmarks.getPositions()は68点の配列
    final points = <Map<String, double>>[];
    final start = isLeftEye ? 36 : 42; // 左目のランドマークインデックス (0-indexed)
    final end = isLeftEye ? 41 : 47;   // 右目のランドマークインデックス (0-indexed)
    
    // landmarksオブジェクトから座標リストを取得 (getRelativePositionsまたはgetPositions)
    // face-api.jsのバージョンやランドマークモデルによってプロパティ名が異なる場合がある
    var positions = js_util.getProperty(landmarks, 'positions');
    if (positions == null) {
      // getPositionsメソッドを試す (古いバージョンの場合)
      if (js_util.hasProperty(landmarks, 'getPositions')) {
        positions = js_util.callMethod(landmarks, 'getPositions', []);
      }
    }

    if (positions == null) return points;

    final length = js_util.getProperty(positions, 'length') as int?;
    if (length == null || length < end + 1) return points; // 必要な点があるか確認

    for (var i = start; i <= end; i++) {
      final point = js_util.getProperty(positions, i);
      if (point != null) {
        final x = js_util.getProperty(point, 'x');
        final y = js_util.getProperty(point, 'y');
        if (x is num && y is num) {
          points.add({
            'x': x.toDouble(),
            'y': y.toDouble(),
          });
        }
      }
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
      _debugStatus = 'ゲーム状態準備完了'; // 初期ステータス
    });
    print('ゲーム状態: _isGameStarted=$_isGameStarted, _isGameOver=$_isGameOver');

    await _initializeCamera();
    print('カメラ初期化完了 (_startGame)');

    if (kIsWeb) {
      if (!_isMediaPipeInitialized && !_isMediaPipeInitializing) {
        print('START_GAME: MediaPipe未初期化。_initializeMediaPipeを呼び出します。');
        await _initializeMediaPipe(); // MediaPipeを初期化
      }
      // MediaPipeが初期化されたか、既にされていた場合
      if (_isMediaPipeInitialized && _mediaPipeFaceDetector != null) {
        print('START_GAME: MediaPipe初期化済。Web顔検出ループを開始します。');
        if (mounted) setState(() => _debugStatus = 'MP検出ループ開始試行(SG)');
        _startWebFaceDetectionLoop();
      } else {
        print('START_GAME: MediaPipeの準備ができていません。検出ループは開始されません。');
        if (mounted) setState(() => _debugStatus = 'MP準備未完了(SG)');
      }
    } else {
      // モバイルの場合はここでカメラのストリーム処理が開始されているはず
    }

    _startStationTimer();
    print('駅タイマー開始 (startGame)');
  }

  void _startStationTimer() {
    _stationTimer?.cancel();
    _wasEyesClosedDuringStation = false; // 駅が変わるたびにリセット
    
    _stationTimer = Timer.periodic(Duration(seconds: STATION_CHANGE_SECONDS), (timer) {
      if (!_isGameStarted || _isGameOver) {
        timer.cancel();
        return;
      }
      
      // 駅変更前にスコア計算
      if (!_isEyesOpen || _wasEyesClosedDuringStation) {
        // 駅通過中に目を閉じていた場合
        _wasEyesClosedDuringStation = true;
        _consecutiveStationsWithEyesClosed++;
        
        // 基本点 + 連続ボーナス
        int stationBonus = (_consecutiveStationsWithEyesClosed * CONSECUTIVE_BONUS_MULTIPLIER * STATION_BASE_SCORE).round();
        int totalStationScore = STATION_BASE_SCORE + stationBonus;
        
        setState(() {
          _score += totalStationScore;
          _debugStatus = 'MP: 駅通過ボーナス! +$totalStationScore (_consecutiveStationsWithEyesClosed駅連続)';
        });
        
        print('駅通過ボーナス: 基本点=$STATION_BASE_SCORE + 連続ボーナス=$stationBonus = $totalStationScore, 連続駅数=$_consecutiveStationsWithEyesClosed');
      } else {
        // 目を開けていた場合は連続カウントリセット
        _consecutiveStationsWithEyesClosed = 0;
        print('駅通過: 目を開けていたためボーナスなし。連続カウントリセット');
      }
      
      setState(() {
        // 駅を進める
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
            _wasEyesClosedDuringStation = false; // 新しい駅のフラグをリセット
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
      _wasEyesClosedDuringStation = false;
      _consecutiveStationsWithEyesClosed = 0; // 連続駅カウントもリセット
      _wasEyesOpen = true;
      _isDebugMode = false; 
      _debugStatus = '';
      _debugFace = null;
      _mediaPipeDebugResult = null; // MediaPipeのデバッグ結果もリセット
    });
    _stationTimer?.cancel();
    _stopWebFaceDetectionLoop(); // Web検出ループを停止
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
    if (!_isMediaPipeInitialized) {
      print('MediaPipe Face Detector not loaded yet. Skipping web detection loop.');
      if (mounted) {
        setState(() {
          _debugStatus = 'MediaPipe FaceDetectorが未ロードです。';
        });
      }
      return;
    }
    _webDetectTimer?.cancel();
    _webDetectTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!kIsWeb || !_isMediaPipeInitialized || _mediaPipeFaceDetector == null) {
        _webDetectTimer?.cancel();
        return;
      }
      final videoElement = html.document.getElementById('webcam-video') as html.VideoElement?;
      if (videoElement != null && videoElement.readyState == 4 && videoElement.videoWidth! > 0 && videoElement.videoHeight! > 0) {
        try {
          final num frameTime = html.window.performance.now();
          print('MP LOOP: Attempting to call detectForVideo with frameTime: $frameTime for video id: ${videoElement.id}');
          
          // FaceLandmarkerのdetectForVideoメソッドを正しく呼び出す
          final result = js_util.callMethod(_mediaPipeFaceDetector, 'detectForVideo', [videoElement, frameTime]);
          
          // 結果を直接処理（結果がnullでない場合）
          if (result != null) {
            print('MP LOOP: Direct result processing');
            _processMediaPipeResultsWeb(result);
          } else {
            print('MP LOOP: detectForVideo returned null result');
          }
          
          print('MP LOOP: detectForVideo call completed.');
        } catch (e, s) {
          print('Web MediaPipe detection error in loop: \\${e}\\n\\${s}');
          if (mounted) {
            setState(() {
              _debugStatus = 'MediaPipe検出エラー: \\${e}';
            });
          }
        }
      } else {
         if (mounted) {
            setState(() {
              _debugStatus = 'Video element not ready for MediaPipe detection.';
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
    print('DEBUG_MODE: _toggleDebugMode called. Current _isDebugMode: $_isDebugMode');
    final newDebugModeState = !_isDebugMode;

    if (newDebugModeState) { // デバッグモードを有効にする場合
      print('DEBUG_MODE: Enabling debug mode...');
      setState(() {
        _isDebugMode = true;
        _debugStatus = 'デバッグモード準備中...';
      });

      if (kIsWeb) {
        print('DEBUG_MODE: Platform is Web.');
        await _initializeCamera(); // カメラを先に準備
        print('DEBUG_MODE: Camera initialized for debug mode.');

        if (!_isMediaPipeInitialized && !_isMediaPipeInitializing) {
          print('DEBUG_MODE: MediaPipe not initialized. Calling _initializeMediaPipe.');
          await _initializeMediaPipe();
        }

        if (_isMediaPipeInitialized && _mediaPipeFaceDetector != null) {
          print('DEBUG_MODE: MediaPipe ready, starting web face detection loop.');
          setState(() => _debugStatus = 'MPデバッグ検出ループ開始試行');
          _startWebFaceDetectionLoop();
        } else {
          print('DEBUG_MODE: MediaPipe NOT ready. Cannot start detection loop.');
          setState(() => _debugStatus = 'MP準備未完了(デバッグ)');
        }
      } else { // Mobile
        print('DEBUG_MODE: Platform is Mobile, calling _initializeCamera.');
        await _initializeCamera();
        setState(() => _debugStatus = 'モバイルデバッグモード有効');
      }
    } else { // デバッグモードを無効にする場合
      print('DEBUG_MODE: Disabling debug mode...');
      if (kIsWeb) {
        print('DEBUG_MODE: Stopping web face detection loop (web).');
        _stopWebFaceDetectionLoop();
      }
      // _stopCamera(); // これは_resetToTitleに任せるか、状態に応じて判断
      setState(() {
        _isDebugMode = false;
        _debugStatus = '';
        _debugFace = null;
        _mediaPipeDebugResult = null;
      });
      print('DEBUG_MODE: Debug mode disabled.');
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

  // MediaPipeからの検出結果を処理するコールバック関数 (Web用)
  void _processMediaPipeResultsWeb(dynamic result) {
    print('MP CALLED: _processMediaPipeResultsWeb with result type: ${result.runtimeType}');
    print('MP RESULT KEYS: ${js_util.getProperty(result, 'constructor')?.toString() ?? 'undefined constructor'}');

    // jsUtilでオブジェクトのすべてのプロパティを列挙
    try {
      final jsKeys = js_util.objectKeys(result);
      print('MP RESULT KEYS: ${js_util.dartify(jsKeys)}');
    } catch (e) {
      print('Failed to get result keys: $e');
    }
    
    if (_isProcessing || (!_isGameStarted && !_isDebugMode) || _isGameOver) {
      _isProcessing = false;
      return;
    }
    _isProcessing = true;

    try {
      final faceLandmarks = js_util.getProperty(result, 'faceLandmarks');
      final faceBlendshapes = js_util.getProperty(result, 'faceBlendshapes');

      print('MP faceLandmarks: ${faceLandmarks != null ? "present" : "null"}');
      if (faceLandmarks != null) {
        print('MP faceLandmarks.length: ${js_util.getProperty(faceLandmarks, 'length')}');
      }

      if (faceLandmarks == null || js_util.getProperty(faceLandmarks, 'length') == 0) {
        if (mounted) {
          setState(() {
            _debugStatus = 'MP: 顔未検出 (\\${DateTime.now().second}s)';
            _isEyesOpen = true;
            _consecutiveBlinkCount = 0;
            _mediaPipeDebugResult = null;
          });
        }
        _isProcessing = false;
        return;
      }

      // 最初の顔のランドマークを取得
      final firstFaceLandmarks = js_util.getProperty(faceLandmarks, 0);
      print('MP firstFaceLandmarks type: ${firstFaceLandmarks.runtimeType}');
      
      // ダーティファイする前にランドマークの長さを確認
      final landmarksLength = js_util.hasProperty(firstFaceLandmarks, 'length') 
          ? js_util.getProperty(firstFaceLandmarks, 'length') 
          : 'unknown';
      print('MP landmarks length before dartify: $landmarksLength');
      
      final landmarks = js_util.dartify(firstFaceLandmarks) as List<dynamic>;
      print('MP landmarks dartified length: ${landmarks.length}');
      
      // 目のランドマークのインデックス（MediaPipe Face Landmarker）
      // 左目の上下のランドマークは約159（上）と145（下）
      // 右目の上下のランドマークは約386（上）と374（下）
      const int leftEyeUpperIndex = 159;
      const int leftEyeLowerIndex = 145;
      const int rightEyeUpperIndex = 386;
      const int rightEyeLowerIndex = 374;
      
      bool leftEyeOpen = true;
      bool rightEyeOpen = true;
      
      if (landmarks.length > rightEyeUpperIndex) {
        // 左目の開閉判定
        print('左目ランドマーク型: ${landmarks[leftEyeUpperIndex].runtimeType}');
        
        // キャストを修正し、より一般的なMap型として扱う
        final leftEyeUpper = landmarks[leftEyeUpperIndex] as Map;
        final leftEyeLower = landmarks[leftEyeLowerIndex] as Map;
        
        // yプロパティの取得も安全に行う
        final leftEyeUpperY = leftEyeUpper['y'] is num ? (leftEyeUpper['y'] as num).toDouble() : 0.0;
        final leftEyeLowerY = leftEyeLower['y'] is num ? (leftEyeLower['y'] as num).toDouble() : 0.0;
        final leftEyeDistance = (leftEyeUpperY - leftEyeLowerY).abs();
        
        // 右目の開閉判定
        final rightEyeUpper = landmarks[rightEyeUpperIndex] as Map;
        final rightEyeLower = landmarks[rightEyeLowerIndex] as Map;
        final rightEyeUpperY = rightEyeUpper['y'] is num ? (rightEyeUpper['y'] as num).toDouble() : 0.0;
        final rightEyeLowerY = rightEyeLower['y'] is num ? (rightEyeLower['y'] as num).toDouble() : 0.0;
        final rightEyeDistance = (rightEyeUpperY - rightEyeLowerY).abs();
        
        // しきい値以下なら目を閉じていると判定
        const eyeClosedThreshold = 0.005; // しきい値を下げる（目を閉じている判定を緩める）
        leftEyeOpen = leftEyeDistance > eyeClosedThreshold;
        rightEyeOpen = rightEyeDistance > eyeClosedThreshold;
        
        final newEyesOpenState = leftEyeOpen || rightEyeOpen;
        _debugStatus = 'MP: 顔検出 L: \\${leftEyeDistance.toStringAsFixed(4)} R: \\${rightEyeDistance.toStringAsFixed(4)}';
        
        if (mounted) {
          setState(() {
            _isEyesOpen = newEyesOpenState;
            
            // 目を閉じた場合は駅通過フラグを立てる
            if (!newEyesOpenState) {
              _wasEyesClosedDuringStation = true;
            }
            
            // まばたき検出は一時的に保持
            if (_wasEyesOpen && !newEyesOpenState) {
              _addScore(); // まばたき連続カウント用
              print('MP: まばたき検出');
            }
            _wasEyesOpen = newEyesOpenState;
            
            if (newEyesOpenState) {
              _consecutiveBlinkCount = 0;
            }
            _mediaPipeDebugResult = result;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _debugStatus = 'MP: ランドマーク不足 (\\${landmarks.length})';
            _isEyesOpen = true;
          });
        }
      }
    } catch (e, s) {
      print('MediaPipe結果処理エラー: \\${e}\\n\\${s}');
      if (mounted) setState(() => _debugStatus = 'MP結果処理エラー: \\${e}');
    } finally {
      _isProcessing = false;
    }
  }
}