import 'package:flutter/material.dart';

class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  // ゲーム状態を管理する変数を追加
  bool _isGameOver = false;
  int _score = 0;
  // 電車の進行状況を管理する変数（0.0〜1.0の範囲）
  double _progress = 0.0;
  // アニメーションコントローラー
  late AnimationController _animationController;
  late Animation<double> _animation;
  // 目をつぶっているかどうかを示す変数を追加
  bool _isEyesClosed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    // ゲーム開始時にスコアをリセット
    _score = 0;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ゲームオーバー時の処理
  void _gameOver() {
    setState(() {
      _isGameOver = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // デバッグメッセージを削除
    // print('build: _isGameStarted=$_isGameStarted, _isGameOver=$_isGameOver');

    return Scaffold(
      body: Stack(
        children: [
          // ... (existing code)

          // 電車内装のアニメーション
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: _animation.value,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '電車内装',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 電車の進行状況ゲージ
          if (!_isEyesClosed) // 目をつぶっている間は隠す
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Container(
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.grey[300],
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progress,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [Colors.blue, Colors.lightBlue],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ゲームオーバー表示
          if (_isGameOver)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'ゲームオーバー',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'スコア: $_score',
                    style: TextStyle(fontSize: 24),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text('タイトルに戻る'),
                  ),
                ],
              ),
            ),

          ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('ゲームのルール'),
                  content: const SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('1. ゲーム時間は30秒です'),
                        SizedBox(height: 8),
                        Text('2. 目を閉じると10点獲得できます'),
                        SizedBox(height: 8),
                        Text('3. 連続で3回以上目を閉じるとゲームオーバーです'),
                        SizedBox(height: 8),
                        Text('4. 駅は5秒ごとに変わります'),
                        SizedBox(height: 8),
                        Text('5. カメラに顔が映っていることを確認してください'),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('閉じる'),
                    ),
                  ],
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'ルール',
              style: TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }

  // 目をつぶっている状態を更新するメソッドを追加
  void updateEyeState(bool isClosed) {
    setState(() {
      _isEyesClosed = isClosed;
    });
  }
} 