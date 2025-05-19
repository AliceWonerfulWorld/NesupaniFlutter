import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mlkit_fd; // Alias to avoid conflict
import 'package:nesupani/screens/eye_detection/painters/train_interior_painter.dart';
import 'package:nesupani/screens/eye_detection/painters/face_landmark_painter.dart';
import 'package:nesupani/screens/eye_detection/painters/mediapipe_face_painter.dart'; // MediaPipeFacePainterの追加
import 'package:nesupani/screens/eye_detection/painters/face_distance_warning_painter.dart'; // 追加
import 'package:nesupani/screens/eye_detection/widgets/animated_scenery_widget.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:js/js.dart' as packageJs; // Renamed alias to avoid conflict
import 'dart:js' as dartJs; // Added for allowInterop
import 'package:universal_html/html.dart' as html;
import 'dart:ui' as ui;
import 'dart:js_util' as js_util;
import 'dart:ui_web' if (dart.library.io) 'dart:ui' as ui_web;
import 'dart:math' as math; // math関数を使用するためのインポート
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:google_fonts/google_fonts.dart';  // Google Fontsをインポート

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
  Timer? _eyesClosedScoreTimer; // 目を閉じている間のスコア加算タイマー
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
  static const int EYES_CLOSED_SCORE_INTERVAL = 200; // 目を閉じている間のスコア加算間隔（ミリ秒）- 短くして反応を早く
  static const int EYES_CLOSED_SCORE_INCREMENT = 1; // 目を閉じている間の加算量
  
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
  AudioPlayer? _audioPlayer;
  bool _isPlayingSound = false;

  // ゲームオーバー・クリアSE用 AudioPlayer
  AudioPlayer? _gameOverSoundPlayer;
  AudioPlayer? _gameClearSoundPlayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // アプリ起動時の確実な初期化（最初のゲームから動くように）
    _performOneTimeInitialization();
    
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
    _initializeAudio();

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

  // アプリ起動時に1回だけ実行される初期化メソッド
  void _performOneTimeInitialization() {
    print('■■■ アプリ起動時の初期化を実行 ■■■');
    
    // ゲーム状態を確実にリセット
    _isGameStarted = false;
    _isGameOver = false;
    _score = 0;
    _currentStation = '';
    _currentStationIndex = 0;
    _consecutiveBlinkCount = 0;
    _wasEyesClosedDuringStation = false;
    _consecutiveStationsWithEyesClosed = 0;
    _wasEyesOpen = true;
    _isDebugMode = false;
    _debugStatus = '';
    _debugFace = null;
    _mediaPipeDebugResult = null;
    _isEyesOpen = true;
    
    // 既存のタイマーを全てキャンセル（念のため）
    _stationTimer?.cancel();
    _stationTimer = null;
    _eyesClosedScoreTimer?.cancel();
    _eyesClosedScoreTimer = null;
    _webDetectTimer?.cancel();
    _webDetectTimer = null;
    
    print('■■■ アプリ起動時の初期化完了 ■■■');
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
      bool foundGlobal = false;
      for (int i = 0; i < 100; i++) { // 100ms * 100 = 10秒
        myMediaPipeGlobalJs = js_util.getProperty(html.window, 'MyMediaPipeGlobal');
        if (myMediaPipeGlobalJs != null && js_util.hasProperty(myMediaPipeGlobalJs, 'FilesetResolver')) {
          foundGlobal = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!foundGlobal) {
        print("エラー: MyMediaPipeGlobal が window オブジェクトに見つかりません (タイムアウト後)。");
        print("MediaPipe scriptの遅延読み込みを試みます...");
        
        // スクリプトを強制的にロードしてみる
        final scriptElement = html.document.createElement('script') as html.ScriptElement;
        scriptElement.src = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.9/vision_bundle.js';
        scriptElement.type = 'text/javascript';
        html.document.head?.append(scriptElement);
        
        // さらに待機
        await Future.delayed(const Duration(seconds: 3));
        
        // 再度確認
        myMediaPipeGlobalJs = js_util.getProperty(html.window, 'MyMediaPipeGlobal');
        if (myMediaPipeGlobalJs == null) {
          _debugStatus = 'MediaPipeグローバルオブジェクト未検出(T)';
          if (mounted) setState(() {});
          _isMediaPipeInitializing = false;
          return;
        }
      }

      final filesetResolverClass = js_util.getProperty(myMediaPipeGlobalJs, 'FilesetResolver');
      if (filesetResolverClass == null) {
        print("エラー: FilesetResolver が MyMediaPipeGlobal に見つかりません。");
        _debugStatus = 'MediaPipe FilesetResolver未検出';
        if (mounted) setState(() {});
        _isMediaPipeInitializing = false;
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
        
        // JavaScript側の内部的な準備が整うのを少し待つ（経験的な値）
        await Future.delayed(const Duration(milliseconds: 300)); 
        print('Short delay after MediaPipe instance creation completed.');

        _isMediaPipeInitialized = true;
        if(mounted) setState(() => _debugStatus = 'MediaPipe 初期化完了'); // 即座に反映

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
          ..style.display = _isDebugMode ? 'block' : 'none'; // デバッグモードでは表示
        video.id = 'webcam-video';
        html.document.body?.append(video);
      } else {
        // すでに存在する場合はスタイルを更新
        video.style.display = _isDebugMode ? 'block' : 'none';
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
            // この呼び出しは _startGame に一本化するためコメントアウト、または削除
            /*
            if ((_isGameStarted || _isDebugMode) && _isMediaPipeInitialized && _mediaPipeFaceDetector != null) {
                 print('Camera initialized and conditions met, starting web face detection loop from _initializeCamera.');
                _startWebFaceDetectionLoop();
            } else {
                 print('Camera initialized but conditions not met to start loop from _initializeCamera (isGameStarted: $_isGameStarted, isDebugMode: $_isDebugMode, isMediaPipeInitialized: $_isMediaPipeInitialized)');
            }
            */
            print('Webcam video dimensions available. Loop start will be handled by _startGame.');
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

  Future<void> _startGame() async {
    print('■■■ ゲーム開始処理: 開始 ■■■');
    
    // 念のため、既存のタイマーを全てキャンセル
    _stationTimer?.cancel();
    _stationTimer = null;
    _eyesClosedScoreTimer?.cancel();
    _eyesClosedScoreTimer = null;
    
    // 状態リセットと初期設定
    setState(() {
      _isGameStarted = true;
      _isGameOver = false;
      _score = 0;
      _currentStation = _stations[0];
      _currentStationIndex = 0;
      _consecutiveBlinkCount = 0;
      _wasEyesOpen = true;
      _isEyesOpen = true; // 初期の目の状態を「開」に明確化
      _debugStatus = 'ゲーム状態準備中...';
    });
    
    print('■■■ カメラ初期化開始 ■■■');
    await _initializeCamera(); // カメラの準備をまず行う
    print('■■■ カメラ初期化完了 ■■■');

    // Webの場合はMediaPipe初期化
    if (kIsWeb) {
      print('■■■ Web: MediaPipe初期化開始 ■■■');
      if (!_isMediaPipeInitialized && !_isMediaPipeInitializing) {
        // _initializeMediaPipe内で_isMediaPipeInitializingがtrueになる
        await _initializeMediaPipe(); 
      }
      
      // MediaPipeの初期化が本当に完了するまで待つ (最大15秒)
      int attempts = 0;
      while (!_isMediaPipeInitialized && attempts < 150) { 
        print('MediaPipe完全初期化待機中... 試行: $attempts, 初期化済み: $_isMediaPipeInitialized, 初期化中フラグ: $_isMediaPipeInitializing');
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
        // _isMediaPipeInitializing が false になり、_isMediaPipeInitialized が true になるのを期待
      }
      
      if (!_isMediaPipeInitialized) {
        print('MediaPipe完全初期化待機タイムアウト。顔認識が機能しない可能性があります。');
        if(mounted) setState(() => _debugStatus = 'MP完全初期化失敗(T)');
        // タイムアウトしても、カメラとビデオ要素の準備ができていればループは試みる
        // ただし、MediaPipeインスタンスがないと検出はできない
      } else {
        print('MediaPipe完全初期化成功。');
        if(mounted) setState(() => _debugStatus = 'MP完全初期化成功');
      }

      // MediaPipeの初期化成否に関わらず、ループ開始は試みるが、
      // ループ内部でMediaPipeインスタンスの存在を確認する
      print('顔認識ループ開始試行 (MP初期化処理後)...');
      _startWebFaceDetectionLoop();

    } else { // モバイルの場合
      // モバイルではMediaPipeは使わないので、カメラ初期化後すぐにゲームロジックに進める
      print('モバイルプラットフォームです。MediaPipe処理はスキップします。');
    }

    print('■■■ 電車音声再生開始 ■■■');
    await _playTrainSound();
    
    await Future.delayed(Duration.zero); // イベントキュー処理
    print('イベントキュー処理後、タイマー作成開始');

    print('■■■ ゲームタイマー作成開始 ■■■');
    // 駅切り替えタイマー作成
    print('★★★ 駅切り替えタイマー作成開始 ★★★');
    _stationTimer = Timer.periodic(
      Duration(seconds: STATION_CHANGE_SECONDS),
      (timer) {
        print('【駅タイマー発火】isGameStarted: $_isGameStarted, isGameOver: $_isGameOver');
        if (!_isGameStarted || _isGameOver) {
          print('駅タイマー: 条件不一致またはゲーム終了のためキャンセル');
          timer.cancel();
          return;
        }
        
        if (mounted) {
          setState(() {
            if (_currentStationIndex < _stations.length - 1) {
              _currentStationIndex++;
              _currentStation = _stations[_currentStationIndex];
              print('駅を更新: $_currentStation (index: $_currentStationIndex)');
            } else {
              _isGameOver = true;
              _isGameStarted = false; 
              print('終点到着、ゲームオーバー');
              timer.cancel();
              _showGameOver(message: '終点に到着しました');
            }
          });
        } else {
          print('駅タイマー: mountedがfalseのためsetStateスキップ');
        }
      }
    );
    print('★★★ 駅タイマー作成成功 ★★★');
    
    // スコア加算タイマー
    print('◆◆◆ スコア加算タイマー作成開始 ◆◆◆');
    _eyesClosedScoreTimer = Timer.periodic(
      Duration(milliseconds: EYES_CLOSED_SCORE_INTERVAL),
      (timer) {
        if (!_isGameStarted || _isGameOver) {
          timer.cancel();
          return;
        }
        if (!_isEyesOpen) {
          if (mounted) {
            setState(() {
              _score += EYES_CLOSED_SCORE_INCREMENT;
            });
          }
        }
      }
    );
    print('◆◆◆ スコア加算タイマー作成成功 ◆◆◆');
    
    if (mounted) {
       setState(() {
         print('ゲーム開始処理の最後にUIを強制更新。現在の目の状態: $_isEyesOpen, スコア: $_score, 駅: $_currentStation');
         _debugStatus = kIsWeb ? _debugStatus : 'モバイルゲーム開始準備完了'; // Web以外の場合のステータス設定
       });
    }
    print('■■■ ゲーム開始処理: 完了 ■■■');
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

  Future<void> _resetToTitle() async {
    print('タイトルに戻ります: SE停止試行開始');
    await _stopTrainSound();
    // ゲームオーバー・クリアSEも停止
    await _gameOverSoundPlayer?.stop();
    await _gameClearSoundPlayer?.stop();
    print('タイトルに戻ります: SE停止完了');
    
    setState(() {
      _isGameStarted = false;
      _isGameOver = false;
      _score = 0;
      _currentStation = '';
      _currentStationIndex = 0;
      _consecutiveBlinkCount = 0;
      _wasEyesClosedDuringStation = false;
      _consecutiveStationsWithEyesClosed = 0;
      _wasEyesOpen = true;
      _isDebugMode = false; 
      _debugStatus = '';
      _debugFace = null;
      _mediaPipeDebugResult = null;
    });
    
    print('タイマーキャンセル開始');
    _stationTimer?.cancel();
    _eyesClosedScoreTimer?.cancel();
    _stopWebFaceDetectionLoop();
    _stopCamera();
    print('タイマーキャンセル完了');
  }

  Future<void> _showGameOver({String? message, bool isClear = false}) async {
    print('ゲームオーバー処理開始: SE停止試行');
    // 確実にSEを停止するため、ゲーム状態も先に変更
    setState(() {
      _isGameStarted = false;
      _isGameOver = true;
    });
    
    _stationTimer?.cancel();
    _stationTimer = null;
    _eyesClosedScoreTimer?.cancel();
    _eyesClosedScoreTimer = null;
    
    await _stopTrainSound();
    print('ゲームオーバー処理: SE停止完了');

    // ゲームオーバー/クリアSEの再生
    if (isClear) {
      _gameClearSoundPlayer?.seek(Duration.zero); // 再生位置を最初に戻す
      _gameClearSoundPlayer?.play();
    } else {
      _gameOverSoundPlayer?.seek(Duration.zero); // 再生位置を最初に戻す
      _gameOverSoundPlayer?.play();
    }
    
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
                style: GoogleFonts.mochiyPopOne(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: isClear ? Colors.amber[800] : Colors.redAccent,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                message ?? (isClear ? 'おめでとうございます！' : 'また挑戦してね！'),
                style: GoogleFonts.mochiyPopOne(fontSize: 18, color: Colors.black87, height: 1.5),
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
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _resetToTitle();
                },
                icon: const Icon(Icons.home),
                label: Text('タイトルへ戻る', style: GoogleFonts.mochiyPopOne()),
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
    print('▶▶▶ WebFaceDetectionLoopの開始試行');
    
    // 既存のタイマーを停止
    _webDetectTimer?.cancel();
    
    _webDetectTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!kIsWeb) {
        _webDetectTimer?.cancel();
        return;
      }
      
      // MediaPipeが未初期化の場合は初期化を試みる
      if (!_isMediaPipeInitialized && !_isMediaPipeInitializing) {
        print('MP LOOP: MediaPipe未初期化のため初期化を試みます');
        _initializeMediaPipe();
        // 初期化中は検出をスキップするが、ループ自体は継続
        if (mounted) {
          setState(() {
            _debugStatus = 'MediaPipe初期化中...';
          });
        }
        return;
      }
      
      // 初期化中ならステータス更新のみ
      if (_isMediaPipeInitializing) {
        if (mounted) {
          setState(() {
            _debugStatus = 'MediaPipe初期化処理中...';
          });
        }
        return;
      }
      
      // MediaPipeが初期化完了していれば検出処理を実行
      if (_isMediaPipeInitialized && _mediaPipeFaceDetector != null) {
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
            print('Web MediaPipe detection error in loop: $e\n$s');
            if (mounted) {
              setState(() {
                _debugStatus = 'MediaPipe検出エラー: $e';
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
      } else {
        if (mounted) {
          setState(() {
            _debugStatus = 'MediaPipe未初期化 (検出ループ実行中)';
          });
        }
      }
    });
    
    print('▶▶▶ WebFaceDetectionLoop開始完了');
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

        // ビデオ要素の表示を更新
        var video = html.document.getElementById('webcam-video') as html.VideoElement?;
        if (video != null) {
          video.style.display = 'block';
        }

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
                Text(
                  '遊び方',
                  style: GoogleFonts.mochiyPopOne(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blueAccent),
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
                  label: Text('閉じる', style: GoogleFonts.mochiyPopOne()),
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
            style: GoogleFonts.mochiyPopOne(fontSize: 18, color: Colors.black87, height: 1.4),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    print('dispose: リソース解放開始');
    WidgetsBinding.instance.removeObserver(this);
    _stationTimer?.cancel();
    _eyesClosedScoreTimer?.cancel(); // 目を閉じている間のスコア加算タイマーを停止
    _webDetectTimer?.cancel();
    _stopCamera();
    _faceDetector.close();
    _animationController.dispose();
    
    // 音声プレーヤーを確実に停止して解放
    if (_isPlayingSound) {
      _audioPlayer?.stop();
    }
    _audioPlayer?.dispose();
    _audioPlayer = null;
    
    // ゲームオーバー・クリアSEの解放
    _gameOverSoundPlayer?.dispose();
    _gameOverSoundPlayer = null;
    _gameClearSoundPlayer?.dispose();
    _gameClearSoundPlayer = null;
    
    print('dispose: リソース解放完了');
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
                        Text(
                          '寝過ごしパニック',
                          style: GoogleFonts.mochiyPopOne(
                            fontSize: 48,
                            color: Colors.white,
                            letterSpacing: 2.5,
                            shadows: const [
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
                          style: GoogleFonts.mochiyPopOne(
                            fontSize: 32,
                            color: Colors.amber[300],
                            letterSpacing: 8,
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
                          child: Text(
                            'スタート',
                            style: GoogleFonts.mochiyPopOne(
                              fontSize: 24,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => _showHowToPlayDialog(context),
                          icon: const Icon(Icons.help_outline),
                          label: Text(
                            '遊び方',
                            style: GoogleFonts.mochiyPopOne(
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
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
                            style: GoogleFonts.mochiyPopOne(
                              fontSize: 18,
                              color: Colors.white,
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
                      child: Column(
                        children: [
                          Text(
                            '寝過ごさないように気をつけろ！',
                            style: GoogleFonts.mochiyPopOne(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '目を閉じてる時間が長いほどスコアUP！',
                            style: GoogleFonts.mochiyPopOne(
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
                    // カメラビューは透明なHtmlElementViewで配置
                    Positioned.fill(
                      child: Container(
                        color: Colors.transparent, // 背景を透明に
                        child: HtmlElementView(viewType: 'webcam-video'),
                      ),
                    ),
                    
                    // 顔のランドマークを表示するオーバーレイ
                    if (_mediaPipeDebugResult != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: MediaPipeFacePainter(
                          _mediaPipeDebugResult,
                          MediaQuery.of(context).size,
                        ),
                        foregroundPainter: _isDebugMode ? null : FaceDistanceWarningPainter(
                          _mediaPipeDebugResult,
                          MediaQuery.of(context).size,
                        ),
                      ),
                    ),
                    
                    // デバッグ情報オーバーレイ
                    Positioned(
                      right: 20,
                      top: 20,
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        constraints: const BoxConstraints(maxWidth: 300),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isMediaPipeInitialized ? Colors.green : Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'MediaPipe: ${_isMediaPipeInitialized ? "初期化済み" : "未初期化"}',
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _debugStatus,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _isEyesOpen ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '目の状態: ${_isEyesOpen ? "開いています" : "閉じています"}',
                                style: TextStyle(
                                  color: _isEyesOpen ? Colors.greenAccent : Colors.redAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
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
                              color: Colors.white.withOpacity(0.5), // 透明度を 0.85 から 0.5 に変更
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
                                  style: GoogleFonts.mochiyPopOne(
                                    fontSize: 26,
                                    color: Colors.blueAccent,
                                    letterSpacing: 2,
                                    shadows: const [
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
                                Text(
                                  'SCORE',
                                  style: GoogleFonts.mochiyPopOne(
                                    fontSize: 18,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '$_score',
                                  style: GoogleFonts.mochiyPopOne(
                                    fontSize: 22,
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
                    // 降りる!ボタン（下中央に大きく）
                    Positioned(
                      bottom: MediaQuery.of(context).padding.bottom + 32,
                      left: MediaQuery.of(context).size.width * 0.5 - 100,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (_currentStation == '福工大前') {
                            _isGameOver = true;
                            _isGameStarted = false;
                            _stationTimer?.cancel();
                            await _showGameOver(message: 'ゲームクリア！福工大前で降りました！', isClear: true);
                          } else {
                            _isGameOver = true;
                            _isGameStarted = false;
                            _stationTimer?.cancel();
                            await _showGameOver(message: '${_currentStation}で降りてしまいました。ゲームオーバー！');
                          }
                        },
                        icon: const Icon(Icons.directions_walk, color: Colors.white, size: 28),
                        label: Text(
                          '降りる！',
                          style: GoogleFonts.mochiyPopOne(
                            fontSize: 22,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
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
    print('MP CALLED: _processMediaPipeResultsWeb with result');
    
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
            _debugStatus = 'MP: 顔未検出';
            _isEyesOpen = true;
            _consecutiveBlinkCount = 0;
            _mediaPipeDebugResult = result;
          });
        }
        _isProcessing = false;
        return;
      }

      // 最初の顔のランドマークを取得
      final firstFaceLandmarks = js_util.getProperty(faceLandmarks, 0);
      print('MP firstFaceLandmarks found');
      
      // ダーティファイする前にランドマークの長さを確認
      final landmarksLength = js_util.hasProperty(firstFaceLandmarks, 'length') 
          ? js_util.getProperty(firstFaceLandmarks, 'length') 
          : 'unknown';
      print('MP landmarks length: $landmarksLength');
      
      List<dynamic> landmarks;
      try {
        landmarks = js_util.dartify(firstFaceLandmarks) as List<dynamic>;
        print('MP landmarks dartified length: ${landmarks.length}');
      } catch (e) {
        print('Failed to dartify landmarks: $e');
        // ランドマークの変換に失敗した場合は代替手段を試す
        landmarks = [];
        final length = js_util.getProperty(firstFaceLandmarks, 'length') as int? ?? 0;
        for (int i = 0; i < length; i++) {
          try {
            final point = js_util.getProperty(firstFaceLandmarks, i);
            final x = js_util.getProperty(point, 'x');
            final y = js_util.getProperty(point, 'y');
            final z = js_util.getProperty(point, 'z');
            landmarks.add({
              'x': x is num ? x.toDouble() : 0.0,
              'y': y is num ? y.toDouble() : 0.0,
              'z': z is num ? z.toDouble() : 0.0,
            });
          } catch (e) {
            print('Landmark $i conversion error: $e');
          }
        }
      }
      
      // 目の状態をblendshapesから検出する方法を試みる
      bool eyesOpenFromBlendshapes = true;
      if (faceBlendshapes != null && js_util.getProperty(faceBlendshapes, 'length') > 0) {
        try {
          final firstBlendshapes = js_util.getProperty(faceBlendshapes, 0);
          final categories = js_util.getProperty(firstBlendshapes, 'categories');
          
          // 目を閉じる表情を探す (eyeBlinkLeft, eyeBlinkRight)
          double leftEyeClosedScore = 0.0;
          double rightEyeClosedScore = 0.0;
          
          if (categories != null) {
            final length = js_util.getProperty(categories, 'length') as int? ?? 0;
            for (int i = 0; i < length; i++) {
              final category = js_util.getProperty(categories, i);
              final name = js_util.getProperty(category, 'categoryName') as String?;
              final score = js_util.getProperty(category, 'score') as num?;
              
              if (name == 'eyeBlinkLeft' && score != null) {
                leftEyeClosedScore = score.toDouble();
              } else if (name == 'eyeBlinkRight' && score != null) {
                rightEyeClosedScore = score.toDouble();
              }
            }
          }
          
          // スコアが閾値を超えたら目を閉じていると判断
          final blendshapeThreshold = 0.35; // 0.3から0.35に変更 (判定を少し厳しく)
          final leftEyeClosed = leftEyeClosedScore > blendshapeThreshold;
          final rightEyeClosed = rightEyeClosedScore > blendshapeThreshold;
          eyesOpenFromBlendshapes = !(leftEyeClosed && rightEyeClosed);
          
          print('Blendshapes: Left eye closed: $leftEyeClosedScore, Right eye closed: $rightEyeClosedScore');
        } catch (e) {
          print('Blendshapes 処理エラー: $e');
        }
      }
      
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
        try {
          // 左目の開閉判定
          final leftEyeUpper = landmarks[leftEyeUpperIndex] as Map;
          final leftEyeLower = landmarks[leftEyeLowerIndex] as Map;
          
          // yプロパティの取得
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
          const eyeClosedThreshold = 0.005; // 0.006から0.005に変更 (開いている判定を少し厳しく)
          leftEyeOpen = leftEyeDistance > eyeClosedThreshold;
          rightEyeOpen = rightEyeDistance > eyeClosedThreshold;
          
          print('目の開閉状態 - 左: $leftEyeOpen (距離: ${leftEyeDistance.toStringAsFixed(4)}), 右: $rightEyeOpen (距離: ${rightEyeDistance.toStringAsFixed(4)})');
          
          // ランドマークとblendshapesの両方から判定
          final newEyesOpenState = (leftEyeOpen || rightEyeOpen) && eyesOpenFromBlendshapes;
          print('最終判定: ${newEyesOpenState ? "目を開いている" : "目を閉じている"} (ランドマーク & ブレンドシェイプ結合)');
        
          _debugStatus = 'MP: 顔検出 左目: ${leftEyeOpen ? "開" : "閉"} 右目: ${rightEyeOpen ? "開" : "閉"}';
          
          if (mounted) {
            setState(() {
              // 目の状態更新
              _isEyesOpen = newEyesOpenState;
              
              // 目を閉じた場合は駅通過フラグを立てる
              if (!newEyesOpenState) {
                _wasEyesClosedDuringStation = true;
                print('目を閉じています: スコア継続加算対象');
              }
              
              // まばたき検出
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
        } catch (e) {
          print('目の開閉判定エラー: $e');
          if (mounted) {
            setState(() {
              _debugStatus = 'MP解析エラー: $e';
              _mediaPipeDebugResult = result;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _debugStatus = 'MP: ランドマーク不足 (${landmarks.length})';
            _isEyesOpen = true;
            _mediaPipeDebugResult = result;
          });
        }
      }
    } catch (e, s) {
      print('MediaPipe結果処理エラー: $e\n$s');
      if (mounted) setState(() => _debugStatus = 'MP結果処理エラー: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // 目を閉じている間定期的にスコアを加算するタイマー
  void _startEyesClosedScoreTimer() {
    print('◆◆◆ スコア加算タイマー初期化開始 ◆◆◆');

    // 既存のタイマーを確実にキャンセル
    if (_eyesClosedScoreTimer != null) {
      print('既存のスコア加算タイマーをキャンセルします');
      _eyesClosedScoreTimer?.cancel();
      _eyesClosedScoreTimer = null;
    }
    
    print('スコア加算タイマー作成: 間隔=${EYES_CLOSED_SCORE_INTERVAL}ms');
    
    try {
      _eyesClosedScoreTimer = Timer.periodic(
        Duration(milliseconds: EYES_CLOSED_SCORE_INTERVAL), 
        (timer) {
          print('【スコア加算タイマー発火】: 時刻=${DateTime.now().toIso8601String()}');
          print('現在の状態: ゲーム状態=${_isGameStarted}, ゲームオーバー=${_isGameOver}, 目=${_isEyesOpen ? "開" : "閉"}, スコア=$_score');
          
          if (!_isGameStarted || _isGameOver) {
            print('スコア加算タイマー: ゲーム終了のためタイマー停止');
            timer.cancel();
            return;
          }
          
          // 目を閉じている場合のみスコア加算
          if (!_isEyesOpen) {
            final oldScore = _score;
            setState(() {
              _score += EYES_CLOSED_SCORE_INCREMENT;
            });
            print('スコア加算完了: $oldScore → $_score (+$EYES_CLOSED_SCORE_INCREMENT)');
          } else {
            print('目が開いているためスコア加算なし');
          }
        }
      );
      print('◆◆◆ スコア加算タイマー作成成功 ◆◆◆');
    } catch (e) {
      print('!!! スコア加算タイマー作成エラー: $e !!!');
    }
  }

  String _getEyeStateText(bool isLeft) {
    if (_mediaPipeDebugResult == null) return '検出中...';
    
    try {
      final faceLandmarks = js_util.getProperty(_mediaPipeDebugResult, 'faceLandmarks');
      if (faceLandmarks == null || js_util.getProperty(faceLandmarks, 'length') == 0) {
        return '検出中...';
      }
      
      final firstFaceLandmarks = js_util.getProperty(faceLandmarks, 0);
      final landmarks = js_util.dartify(firstFaceLandmarks) as List<dynamic>;
      
      // 左目と右目のランドマークインデックス
      const int leftEyeUpperIndex = 159;
      const int leftEyeLowerIndex = 145;
      const int rightEyeUpperIndex = 386;
      const int rightEyeLowerIndex = 374;
      
      if (landmarks.length <= math.max(leftEyeUpperIndex, rightEyeUpperIndex)) {
        return '不明';
      }
      
      // 左目か右目かに応じて対応するランドマークを取得
      final upperIndex = isLeft ? leftEyeUpperIndex : rightEyeUpperIndex;
      final lowerIndex = isLeft ? leftEyeLowerIndex : rightEyeLowerIndex;
      
      final eyeUpper = landmarks[upperIndex] as Map;
      final eyeLower = landmarks[lowerIndex] as Map;
      
      final eyeUpperY = eyeUpper['y'] is num ? (eyeUpper['y'] as num).toDouble() : 0.0;
      final eyeLowerY = eyeLower['y'] is num ? (eyeLower['y'] as num).toDouble() : 0.0;
      final eyeDistance = (eyeUpperY - eyeLowerY).abs();
      
      // しきい値
      const eyeClosedThreshold = 0.004;
      final isOpen = eyeDistance > eyeClosedThreshold;
      
      return '${isOpen ? "開" : "閉"} (${eyeDistance.toStringAsFixed(4)})';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  Future<void> _initializeAudio() async {
    _audioPlayer = AudioPlayer();
    await _audioPlayer?.setAsset('assets/sounds/train_sound.mp3');
    await _audioPlayer?.setLoopMode(LoopMode.all);

    // ゲームオーバー・クリアSEの初期化
    _gameOverSoundPlayer = AudioPlayer();
    await _gameOverSoundPlayer?.setAsset('assets/sounds/game_over.mp3'); 
    // ループ再生はしないので LoopMode.off (デフォルト)

    _gameClearSoundPlayer = AudioPlayer();
    await _gameClearSoundPlayer?.setAsset('assets/sounds/game_clear.mp3');
    // ループ再生はしないので LoopMode.off (デフォルト)
  }

  Future<void> _playTrainSound() async {
    print('SE再生試行: isPlayingSound=$_isPlayingSound, audioPlayer is null: ${_audioPlayer == null}');
    if (!_isPlayingSound && _audioPlayer != null) {
      try {
        print('calling _audioPlayer.play()');
        _audioPlayer?.play(); // await を一時的に削除して、処理がブロックされないか確認
        print('_audioPlayer.play() called (no await)');
        // setStateは非同期処理の結果を待たずにすぐに実行される
        if (mounted) {
          setState(() {
            _isPlayingSound = true;
          });
        }
      } catch (e) {
        print('Audio play error: $e');
      }
    } else {
      print('SE再生スキップ: 既に再生中かオーディオプレーヤーがnull');
    }
  }

  Future<void> _stopTrainSound() async {
    print('SE停止試行: 現在の再生状態=${_isPlayingSound}');
    if (_audioPlayer != null) {
      try {
        // 現在の再生状態に関わらず停止を試みる
        await _audioPlayer?.stop();
        print('SE停止成功');
      } catch (e) {
        print('SE停止エラー: $e');
      } finally {
        setState(() {
          _isPlayingSound = false;
        });
      }
    } else {
      print('SE停止: オーディオプレーヤーが未初期化');
    }
  }
}