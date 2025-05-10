import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui;

class EyeDetectionScreen extends StatefulWidget {
  const EyeDetectionScreen({super.key});

  @override
  State<EyeDetectionScreen> createState() => _EyeDetectionScreenState();
}

class _EyeDetectionScreenState extends State<EyeDetectionScreen> {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      minFaceSize: 0.1,
      enableContours: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  bool _isCameraInitialized = false;
  bool _isEyesClosed = false;
  int _score = 0;
  Timer? _scoreTimer;
  final List<String> _stations = [
    '新宿駅',
    '渋谷駅',
    '池袋駅',
    '東京駅',
    '上野駅',
    '品川駅',
  ];
  String _currentStation = '新宿駅';
  int _stationIndex = 0;
  Face? _detectedFace;
  Size? _screenSize;
  bool _isProcessing = false;
  int _closedFramesCount = 0;
  static const int _requiredClosedFrames = 3;  // 連続フレーム数を5から3に減らす
  static const double _eyeThreshold = 0.035;    // 目の閾値を0.02から0.03に上げる

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _startStationTimer();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        print('カメラが見つかりません');
        return;
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      print('選択されたカメラ: ${frontCamera.name}');

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      print('カメラの初期化を開始します...');
      await _cameraController!.initialize();
      print('カメラの初期化が完了しました');

      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
      _startImageStream();
    } catch (e) {
      print('カメラの初期化エラー: $e');
      if (e is CameraException) {
        print('カメラエラーの詳細: ${e.code} - ${e.description}');
      }
    }
  }

  void _startStationTimer() {
    Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() {
        _stationIndex = (_stationIndex + 1) % _stations.length;
        _currentStation = _stations[_stationIndex];
      });
    });
  }

  void _startImageStream() {
    _cameraController!.startImageStream((CameraImage image) async {
      if (_isProcessing) return;
      _isProcessing = true;

      try {
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
        final InputImageRotation imageRotation = InputImageRotation.rotation270deg;
        final InputImageFormat inputImageFormat = InputImageFormat.yuv420;

        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: imageSize,
            rotation: imageRotation,
            format: inputImageFormat,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );

        final faces = await _faceDetector.processImage(inputImage);
        
        if (faces.isNotEmpty) {
          final face = faces.first;
          
          // 目の判定をさらに厳密に
          final bool isEyesClosed = face.leftEyeOpenProbability != null && 
                                  face.rightEyeOpenProbability != null &&
                                  face.leftEyeOpenProbability! < _eyeThreshold && 
                                  face.rightEyeOpenProbability! < _eyeThreshold &&
                                  face.leftEyeOpenProbability! > 0.0 && 
                                  face.rightEyeOpenProbability! > 0.0;
          
          // 連続フレームでの判定
          if (isEyesClosed) {
            _closedFramesCount++;
            if (_closedFramesCount >= _requiredClosedFrames && !_isEyesClosed) {
              setState(() {
                _isEyesClosed = true;
                _startScoreTimer();
              });
            }
          } else {
            _closedFramesCount = 0;
            if (_isEyesClosed) {
              setState(() {
                _isEyesClosed = false;
                _stopScoreTimer();
              });
            }
          }
          
          setState(() {
            _detectedFace = face;
          });
        } else {
          _closedFramesCount = 0;
          setState(() {
            _detectedFace = null;
          });
        }
      } catch (e) {
        print('画像処理エラー: $e');
      } finally {
        _isProcessing = false;
      }
    });
  }

  void _startScoreTimer() {
    _scoreTimer?.cancel();
    _scoreTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _score += 10;
      });
    });
  }

  void _stopScoreTimer() {
    _scoreTimer?.cancel();
    _scoreTimer = null;
  }

  @override
  void dispose() {
    _stopScoreTimer();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Widget _buildFaceOverlay() {
    if (_detectedFace == null || _screenSize == null) {
      return const SizedBox.shrink();
    }

    final face = _detectedFace!;
    final screenSize = _screenSize!;
    
    // カメラのプレビューサイズと実際の画面サイズの比率を計算
    final scale = screenSize.width / _cameraController!.value.previewSize!.height;
    final offset = Offset(
      screenSize.width - (_cameraController!.value.previewSize!.width * scale),
      0,
    );

    return CustomPaint(
      painter: FacePainter(
        face: face,
        scale: scale,
        offset: offset,
        isEyesClosed: _isEyesClosed,
      ),
      size: screenSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('カメラを初期化中...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('寝過ごしゲーム'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade900,
              Colors.blue.shade700,
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _screenSize = Size(constraints.maxWidth, constraints.maxHeight);
                        return Stack(
                          children: [
                            Transform.scale(
                              scale: 1.0,
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 1 / _cameraController!.value.aspectRatio,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _currentStation,
                            style: const TextStyle(
                              fontSize: 32,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'スコア: $_score',
                            style: const TextStyle(
                              fontSize: 24,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _isEyesClosed ? '目を閉じています' : '目を開けています',
                            style: TextStyle(
                              fontSize: 18,
                              color: _isEyesClosed ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _detectedFace == null ? '顔が検出されていません' : '顔を検出中',
                            style: TextStyle(
                              fontSize: 18,
                              color: _detectedFace == null ? Colors.red : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  final Face face;
  final double scale;
  final Offset offset;
  final bool isEyesClosed;

  FacePainter({
    required this.face,
    required this.scale,
    required this.offset,
    required this.isEyesClosed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // デバッグ用の描画を削除
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.face != face || oldDelegate.isEyesClosed != isEyesClosed;
  }
} 