# セキュリティガイドライン（共通）

本ファイルは全サービス共通の原則のみを扱う。**秘密情報管理の具体的な仕組み**（設定ライブラリ・設定ファイルの場所）、**アップロード許可形式**、**脆弱性スキャンツール名**など、スタック・サービス固有の具体は各サービスの `SERVICE.md` に定義する。

## 秘密情報の管理
- APIキー・パスワード・トークンをコードに直書き禁止
- 環境変数は`.env`で管理し、`.env.example`にキー名のみ記載する
- `.env`は必ず`.gitignore`に追加する
- シークレットのローテーションは定期的に実施する
- 環境変数のスキーマ検証（必須キーの未設定・型不一致をアプリ起動時に検出）を行う。具体的な仕組みは `SERVICE.md` に定義する

## 入力バリデーション
- ユーザー入力は必ずバリデーション・サニタイズを行う
- SQLはパラメータバインドを使用し、文字列結合禁止
- ファイルアップロードは拡張子・MIMEタイプ・サイズを検証する（許可形式・上限は `SERVICE.md` に定義）

## 出力
- ログに個人情報・秘密情報を出力しない
- エラーメッセージに内部実装の詳細を含めない（本番環境）
- レスポンスに不要なフィールドを含めない

## 依存パッケージ
- 依存パッケージの脆弱性チェックを定期的に実施する（使用するツールは `SERVICE.md` に定義）
- 重大な脆弱性は即時対応する
- 不要なパッケージは削除する

## AIエージェントのガードレール
- 破壊的操作・秘密ファイル読み取りは、プロンプト任せにせず `.claude/settings.json` の `permissions.deny` と
  PreToolUse フック `.claude/scripts/guard-dangerous.sh` で機械的に遮断する（プロジェクト単位で配布済み）。
- **組織全体で強制したい制御は managed-settings（管理者スコープ）で設定する**。プロジェクトの `settings.json` には
  置けない管理者専用キー（`disableBypassPermissionsMode`＝`--dangerously-skip-permissions` の抑止、
  `allowManagedPermissionRulesOnly` / `allowManagedHooksOnly` / `allowManagedMcpServersOnly`）は、
  IT管理者が managed-settings に定義する。プロジェクト設定に書いても無効、または自リポのフック/権限を壊すため注意。
  （出典: Claude Code 公式 settings ドキュメント）
