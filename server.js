// LINE Botの設定
const lineConfig = {
    channelAccessToken: process.env.CHANNEL_ACCESS_TOKEN,
    channelSecret: process.env.CHANNEL_SECRET
};

const lineClient = new line.Client(lineConfig);

app.post('/api/line-notify', async (req, res) => {
    try {
        const { userId, score, isGameOver } = req.body;
        
        // ユーザー情報を取得
        const userDoc = await db.collection('users').doc(userId).get();
        if (!userDoc.exists) {
            return res.status(404).json({ error: 'ユーザーが見つかりません' });
        }

        const userData = userDoc.data();
        const lineUserId = userData.lineUserId;

        if (!lineUserId) {
            return res.status(400).json({ error: 'LINEユーザーIDが設定されていません' });
        }

        // メッセージの作成
        let message;
        if (isGameOver) {
            message = {
                type: 'text',
                text: `ゲームオーバー！\n残念ながら、福工大前で降りることができませんでした。\nスコア: 0点\n\nもう一度チャレンジしてみましょう！`
            };
        } else {
            message = {
                type: 'text',
                text: `おめでとうございます！\n福工大前で無事に降りることができました！\nスコア: ${score}点`
            };
        }

        // LINE Messaging APIを使用してメッセージを送信
        await lineClient.pushMessage(lineUserId, message);

        res.json({ success: true });
    } catch (error) {
        console.error('LINE通知エラー:', error);
        res.status(500).json({ error: 'LINE通知の送信に失敗しました' });
    }
}); 