# S3、CloudFrontを用いたCDNサービス

AWS S3、CloudFront を使用して静的コンテンツを配信する CDN 環境を Terraform で構築しました。
セキュリティ・監視・自動デプロイまでを一貫して実装しています。

---

## 工夫した点

### セキュリティ：S3への直接アクセスを禁止

S3バケットへのパブリックアクセスを完全にブロックし、
CloudFront経由のみコンテンツを配信できる構成にしました。

- **OAC（Origin Access Control）** を使用し、CloudFrontからS3への
  リクエストを署名付きで行うことで、なりすましアクセスを防止
- **バケットポリシー** で CloudFront のみを明示的に許可することで、
  S3 URL での直接アクセスを遮断
- 旧来の OAI（Origin Access Identity）ではなく、AWS推奨の OAC を採用

### セキュリティ：WAF（Web Application Firewall）の導入

CloudFront に AWS WAF をアタッチし、不正リクエストや攻撃を防御する構成にしました。

- **AWS マネージドルール（AWSManagedRulesCommonRuleSet）** を適用し、
  一般的な Web 攻撃（SQLインジェクション・XSS など）をブロック
- **地理的制限（Geo Match）** により、日本（JP）からのリクエストのみを対象にルールを適用
- **カスタムルール** でクエリパラメータに特定文字列を含むリクエストをブロックし、
  WAF の動作確認も実施
- WAF は CloudFront 用のため、`us-east-1` リージョンに作成

### リダイレクト設定

- **HTTP → HTTPS リダイレクト** を設定し、常に暗号化通信を強制
- **403 / 404 エラー → index.html リダイレクト** を設定し、
  S3に存在しないパスへのアクセスをフロントエンド側で処理できるよう対応
  （パブリックアクセスブロック有効時は 403、無効時は 404 が返るケースがあるため両方に対応）

### 監視：CloudFront アクセスログの収集

全リクエストのログを S3 に保存し、不正アクセスの検知やアクセス解析を可能にしました。

- ログ保存専用の S3 バケットを分離して作成
- `cloudfront/` プレフィックスでログを整理
- ログの肥大化を防ぐため、**S3 ライフサイクルポリシー**で90日後に自動削除

### 監視：CloudWatch アラートの設定

異常を自動検知し、メール通知を受け取れる監視体制を構築しました。

- **4xx エラー率**が 10% を超えた場合にアラート通知
- **5xx エラー率**が 1% を超えた場合にアラート通知（サーバーエラーは低めの閾値で即検知）
- **リクエスト数**が5分間で 1000 件を超えた場合に DDoS の可能性としてアラート通知
- SNS トピック経由でメール通知を実現

### 可用性：S3 バージョニングの有効化

ファイルの誤上書き・誤削除時にロールバックできる構成にしました。

- S3 バージョニングを有効化し、全バージョンを保持
- 旧バージョンは **S3 ライフサイクルポリシー**で 90 日後に自動削除してコストを最適化

### CI/CD：GitHub Actions による自動デプロイ

main ブランチへの push を起点に、S3 へのアップロードから CloudFront のキャッシュ削除まで自動化しました。

- `dist/` 配下の変更を検知して自動デプロイ
- `index.html` は `no-cache` で、JS/CSS は `max-age=31536000`（1年）でキャッシュを最適化
- `--delete` オプションで S3 に不要なファイルが残らないよう管理
- GitHub Secrets で AWS 認証情報を安全に管理

### インフラ管理：tfstate のリモート管理

`terraform.tfstate` をS3バケットでリモート管理することで、
チーム開発での状態ファイルの競合や紛失を防止しています。

### IaC：Terraform による再現性の確保

全リソースをコードで管理することで、環境の再作成や
設定変更を安全かつ一貫して行えるようにしました。

---

## プレビュー

![webページ①](images/webページ①.png)
![webページ②](images/webページ②.png)

---

## 概要

| 項目 | 内容 |
|------|------|
| プロバイダー | AWS |
| Terraform バージョン | >= 1.15 |
| 主なリソース | S3, CloudFront, WAF, CloudWatch, SNS, IAM |
| 対応リージョン | ap-northeast-1（デフォルト） |

### アーキテクチャ

![インフラ構成図](images/インフラ構成図.png)

```
ユーザー
  │
  ▼
WAF（不正リクエストをブロック）
  │
  ▼
CloudFront Distribution（CDN / HTTPS）
  │  ※ OAC (Origin Access Control) で署名
  │  ※ アクセスログを S3 に保存
  ▼
S3 Bucket（静的ファイル置き場・パブリックアクセスブロック）

CloudWatch（エラー率・リクエスト数を監視）
  │
  ▼
SNS → メール通知
```

---

## 使用技術

| カテゴリ | 技術・サービス |
|---------|--------------|
| クラウド | AWS |
| CDN | CloudFront |
| ストレージ | S3 |
| セキュリティ | WAF（AWS Managed Rules）, OAC, Bucket Policy |
| 監視 | CloudWatch Alarms, SNS |
| IaC | Terraform |
| CI/CD | GitHub Actions |

---

## 前提条件

- [Terraform](https://developer.hashicorp.com/terraform/install) v1.15 以上
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) 設定済み
- AWS IAM ユーザーに以下の権限があること
  - `s3:*`
  - `cloudfront:*`
  - `iam:*`（バケットポリシー設定に必要）
  - `wafv2:*`
  - `cloudwatch:*`
  - `sns:*`

---

## ディレクトリ構成

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml     # GitHub Actions（自動デプロイ）
├── dist/
│   └── index.html         # 静的コンテンツ
├── images/                # README 用画像
├── main.tf                # メインリソース定義
├── variables.tf           # 変数定義
├── outputs.tf             # 出力値（CloudFront URL など）
├── terraform.tf           # プロバイダーの設定（AWS）
└── README.md
```

---

## 使い方

### 1. リポジトリのクローン

```bash
git clone https://github.com/Onepiece2424/cdn-project.git
cd cdn-project
```

### 2. 変数の設定

`variables.tf` を確認して値を設定します。

```hcl
project_name = "cdn-project"
```

### 3. 初期化・デプロイ

```bash
# プロバイダーの初期化
terraform init

# 変更内容の確認
terraform plan

# リソースの作成（CloudFront の作成に数分かかります）
terraform apply
```

### 4. 静的ファイルのアップロード

```bash
# ファイルをS3にアップロード
aws s3 sync ./dist s3://$(terraform output -raw s3_bucket_name)
```

### 5. CloudFront キャッシュの無効化

ファイルを更新した際にキャッシュをクリアします。

```bash
DIST_ID=$(terraform output -raw cloudfront_distribution_id)

aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*"
```

> main ブランチへ push した場合は GitHub Actions が自動で上記を実行します。

---

## 変数一覧

| 変数名 | 型 | デフォルト値 | 説明 |
|--------|-----|-------------|------|
| `project_name` | string | `"cdn-project"` | プロジェクトの名前 |

---

## 出力値一覧

| 出力名 | 説明 |
|--------|------|
| `cloudfront_url` | コンテンツ配信用の CloudFront URL |
| `s3_bucket_name` | 静的ファイルの格納先 S3 バケット名 |

---

## セキュリティについて

- **S3 への直接アクセスは禁止** — パブリックアクセスブロックを有効化し、CloudFront 経由のみ許可
- **OAC（Origin Access Control）を使用** — 旧来の OAI より推奨される方式
- **HTTPS 強制** — HTTP アクセスは自動的に HTTPS へリダイレクト
- **WAF** — AWS マネージドルールで一般的な Web 攻撃をブロック

---

## リソースの削除

```bash
# S3 バケットを空にする（バケットが空でないと削除できない）
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

# リソースを削除
terraform destroy
```
