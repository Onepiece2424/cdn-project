# # S3 + CloudFront CDN — Terraform

AWS S3 と CloudFront を使用して静的コンテンツを配信する CDN 環境を Terraform で構築します。

---

## 概要

| 項目 | 内容 |
|------|------|
| プロバイダー | AWS |
| Terraform バージョン | >= 1.3 |
| 主なリソース | S3, CloudFront, IAM |
| 対応リージョン | ap-northeast-1（デフォルト） |

### アーキテクチャ

```
ユーザー
  │
  ▼
CloudFront Distribution（CDN / HTTPS）
  │  ※ OAC (Origin Access Control) で署名
  ▼
S3 Bucket（静的ファイル置き場・パブリックアクセスブロック）
```

---

## 前提条件

- [Terraform](https://developer.hashicorp.com/terraform/install) v1.3 以上
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) 設定済み
- AWS IAM ユーザーに以下の権限があること
  - `s3:*`
  - `cloudfront:*`
  - `iam:*`（バケットポリシー設定に必要）

---

## ディレクトリ構成

```
.
├── main.tf            # メインリソース定義（S3, CloudFront, OAC, バケットポリシー）
├── variables.tf       # 変数定義
├── outputs.tf         # 出力値（CloudFront URL など）
├── terraform.tfvars   # 変数の実値（Git 管理外推奨）
└── README.md
```

---

## 使い方

### 1. リポジトリのクローン

```bash
git clone https://github.com/your-org/your-repo.git
cd your-repo
```

### 2. 変数の設定

`terraform.tfvars` を作成して値を設定します。

```hcl
project_name = "my-cdn"
aws_region   = "ap-northeast-1"
```

### 3. 初期化・デプロイ

```bash
# プロバイダーの初期化
terraform init

# 変更内容の確認
terraform plan

# リソースの作成（CloudFront の作成に 5〜15 分かかります）
terraform apply
```

### 4. 静的ファイルのアップロード

```bash
# S3 バケット名を取得
BUCKET=$(terraform output -raw s3_bucket_name)

# ファイルをアップロード
aws s3 sync ./dist s3://$BUCKET
```

### 5. CloudFront キャッシュの無効化

ファイルを更新した際にキャッシュをクリアします。

```bash
DIST_ID=$(terraform output -raw cloudfront_distribution_id)

aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*"
```

---

## 変数一覧

| 変数名 | 型 | デフォルト値 | 説明 |
|--------|-----|-------------|------|
| `project_name` | string | `"my-cdn"` | リソース名のプレフィックス |
| `aws_region` | string | `"ap-northeast-1"` | デプロイ先のAWSリージョン |

---

## 出力値一覧

| 出力名 | 説明 |
|--------|------|
| `cloudfront_url` | コンテンツ配信用の CloudFront URL |
| `s3_bucket_name` | 静的ファイルの格納先 S3 バケット名 |
| `cloudfront_distribution_id` | キャッシュ無効化などに使用するディストリビューション ID |

---

## カスタムドメインの設定（オプション）

独自ドメインを使う場合は以下の手順が必要です。

1. **ACM 証明書の発行**（リージョンは必ず `us-east-1` を指定）
2. `variables.tf` に以下を追加

```hcl
variable "domain_name"          { default = "cdn.example.com" }
variable "acm_certificate_arn"  { default = "arn:aws:acm:us-east-1:..." }
```

1. `main.tf` の `viewer_certificate` ブロックを更新
2. Route 53 に Alias レコードを追加（CloudFront ドメインへ向ける）

---

## セキュリティについて

- **S3 への直接アクセスは禁止** — パブリックアクセスブロックを有効化し、CloudFront 経由のみ許可
- **OAC（Origin Access Control）を使用** — 旧来の OAI より推奨される方式
- **HTTPS 強制** — HTTP アクセスは自動的に HTTPS へリダイレクト
- `terraform.tfvars` に機密情報を含む場合は `.gitignore` に追加すること

---

## リソースの削除

```bash
# S3 バケットを空にする（バケットが空でないと削除できない）
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

# リソースを削除
terraform destroy
```

---

## ライセンス

MIT
