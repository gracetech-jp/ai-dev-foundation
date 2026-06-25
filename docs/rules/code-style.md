# コードスタイルガイドライン

## 共通
- インデント：TAB
- 文字コード：UTF-8
- 改行コード：LF（Windowsでも必ずLF）
- ファイル末尾：改行あり
- 1ファイル300行を超えたら分割を検討する
- マジックナンバーは定数として定義する
- コメントは「何をしているか」ではなく「なぜそうしているか」を書く

## 命名規則
| 対象 | 規則 | 例 |
|---|---|---|
| 変数・関数 | camelCase | getUserById |
| クラス・型 | PascalCase | UserRepository |
| 定数 | UPPER_SNAKE_CASE | MAX_RETRY_COUNT |
| ファイル名 | kebab-case | user-service.ts |
| DBカラム | snake_case | created_at |

## TypeScript
- `any`型の使用禁止（やむを得ない場合は理由をコメント）
- 関数の引数・戻り値には必ず型を付ける
- `as`キャストは最小限に抑える
- ESモジュール（import/export）を使用し、CommonJS（require）は使わない
