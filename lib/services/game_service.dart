import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;

/// ゲームサービス
/// LINEボットとFlutterゲーム（STAGE3）の連携を管理します
class GameService {
  // Firebaseエンドポイント
  static const String _lineWebhookEndpoint = 'https://asia-northeast1-nesugoshipanic.cloudfunctions.net/app/webhook';
  
  // ゲームID
  String? _gameId;
  // LINE ユーザーID
  String? _lineUserId;
  // 認証状態
  bool _isAuthenticated = false;
  // エラーメッセージ
  String _errorMessage = '';
  // ローディング状態
  bool _isLoading = false;
  // フリープレイモード
  bool _isFreePlay = false;

  // ゲッター
  String? get gameId => _gameId;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get isFreePlay => _isFreePlay;

  /// 初期化処理
  Future<bool> initialize() async {
    _isLoading = true;
    
    try {
      // URLからゲームIDを取得
      final gameId = _getGameIdFromUrl();
      if (gameId == null || gameId.isEmpty) {
        _errorMessage = 'ゲームIDが見つかりません。URLを確認してください。';
        _isLoading = false;
        return false;
      }
      
      _gameId = gameId;
      print('GameID: $_gameId を取得しました');
      
      // Firestoreでゲーム状態を確認
      final isValid = await _verifyGameStatus();
      
      _isAuthenticated = isValid;
      _isLoading = false;
      
      return isValid;
    } catch (e) {
      _errorMessage = '初期化エラー: $e';
      _isLoading = false;
      print(_errorMessage);
      return false;
    }
  }

  /// フリープレイモードを設定
  void setFreePlayMode() {
    _isFreePlay = true;
    _isAuthenticated = true;
    _gameId = 'FREEPLAY';
    print('フリープレイモードが有効になりました');
  }

  /// URLからIDパラメータを取得
  String? _getGameIdFromUrl() {
    try {
      final uri = Uri.parse(html.window.location.href);
      return uri.queryParameters['id'];
    } catch (e) {
      print('URLパラメータ取得エラー: $e');
      // デバッグ用にIDをハードコード（開発時のみ）
      return 'DEBUG123';
    }
  }

  /// ゲーム状態をFirestoreで確認
  Future<bool> _verifyGameStatus() async {
    if (_isFreePlay) return true; // フリープレイモードでは検証をスキップ
    if (_gameId == null) return false;
    
    try {
      // gameIdsコレクションから対象ドキュメントを取得
      final docSnapshot = await FirebaseFirestore.instance
          .collection('gameIds')
          .doc(_gameId)
          .get();
      
      if (!docSnapshot.exists) {
        _errorMessage = '無効なゲームIDです';
        return false;
      }
      
      final data = docSnapshot.data();
      if (data == null) {
        _errorMessage = 'ゲームデータが見つかりません';
        return false;
      }
      
      final String status = data['status'] as String;
      final bool stage3Completed = data['stage3Completed'] == true;
      final userId = data['lineUserId'] as String?;
      
      if (stage3Completed) {
        _errorMessage = 'このゲームは既にクリア済みです';
        return false;
      }

      // STAGE2をクリア済みかチェック (status = 2)
      if (status != "stage2") {
        _errorMessage = status == "stage1"
            ? 'STAGE1から順にプレイしてください' 
            : (status == "active" 
            ? 'STAGE2をクリアしてください' 
            : 'このゲームは既にクリア済みです');
        return false;
      }
      
      // LINEユーザーIDを保存
      _lineUserId = userId;
      
      return true;
    } catch (e) {
      _errorMessage = 'Firestore接続エラー: $e';
      print(_errorMessage);
      return false;
    }
  }

  /// ゲームクリア時の処理
  Future<bool> completeGame(int score) async {
    // フリープレイモードでは何もしない
    if (_isFreePlay) {
      print('フリープレイモード: ゲームクリア処理をスキップ');
      return true;
    }
    
    if (!_isAuthenticated || _gameId == null || _lineUserId == null) {
      _errorMessage = '認証されていないため結果を送信できません';
      print('認証エラー: isAuthenticated=$_isAuthenticated, gameId=$_gameId, lineUserId=$_lineUserId');
      return false;
    }
    
    _isLoading = true;
    
    try {
      print('Firestoreの更新を開始: gameId=$_gameId, score=$score');
      // 1. Firestoreのstatusを更新 (2→3)
      await FirebaseFirestore.instance
          .collection('gameIds')
          .doc(_gameId)
          .update({
            'status': "stage3",
            'stage3Score': score,
            'updatedAt': FieldValue.serverTimestamp()
          });
      print('Firestoreの更新が完了しました');
      
      // 2. LINEボットに通知
      print('LINEボットへの通知を開始: gameId=$_gameId, score=$score');
      final response = await http.post(
        Uri.parse('https://asia-northeast1-nesugoshipanic.cloudfunctions.net/app/api/stage3-completed'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'gameId': _gameId,
          'score': score
        }),
      );
      
      print('LINEボットからの応答: statusCode=${response.statusCode}, body=${response.body}');
      
      if (response.statusCode != 200) {
        print('LINE通知エラー: ${response.body}');
        _errorMessage = 'LINEボットへの通知に失敗しました (ステータスコード: ${response.statusCode})';
        _isLoading = false;
        return false;
      }
      
      print('ゲームクリア情報をLINEボットに送信しました');
      _isLoading = false;
      return true;
    } catch (e, stackTrace) {
      _errorMessage = 'ゲームクリア処理エラー: $e';
      print('エラー詳細: $e');
      print('スタックトレース: $stackTrace');
      _isLoading = false;
      return false;
    }
  }

  /// エラーメッセージをクリア
  void clearError() {
    _errorMessage = '';
  }
} 