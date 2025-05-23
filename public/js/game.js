async gameOver() {
    this.isGameOver = true;
    this.gameState = 'gameOver';
    this.score = 0; // スコアを0に設定

    // ゲームオーバー時のLINE通知を送信
    try {
        const response = await fetch('/api/line-notify', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                userId: this.userId,
                score: 0,
                isGameOver: true
            })
        });

        if (!response.ok) {
            console.error('LINE通知の送信に失敗しました');
        }
    } catch (error) {
        console.error('LINE通知の送信中にエラーが発生しました:', error);
    }

    // ゲームオーバー画面を表示
    this.showGameOverScreen();
} 