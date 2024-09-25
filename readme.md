# Cloud RunとCloud SQLの接続
## 1. VPCとCloud SQLの設定

### VPCを設定する
VPCネットワークの作成:

```
gcloud compute networks create my-vpc --subnet-mode=custom
```

サブネットの作成:
```
gcloud compute networks subnets create my-subnet \
    --network=my-vpc \
    --region=us-central1 \
    --range=10.0.0.0/24

```

Cloud SQL用のCloud SQLインスタンスを作成:
```
gcloud sql instances create my-postgres --database-version=POSTGRES_13 --tier=db-f1-micro --region=us-central1
```

Cloud SQLのユーザーとデータベースを作成:
```
gcloud sql users create myuser --instance=my-postgres --password=my-password
gcloud sql databases create mydatabase --instance=my-postgres

```

Cloud SQL Studioからアクセス

テーブルの作成
```
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    age INT NOT NULL
);
```

データの挿入
```
INSERT INTO users (name, age) VALUES 
('Alice', 30),
('Bob', 25),
('Charlie', 35);

```

**インスタンスにプライベートIPを割り当てはGUI経由で行っておく**

### Cloud SQLの接続情報を環境変数として設定
環境変数に以下の情報を設定します。

DB_USER: myuser
DB_PASSWORD: my-password
DB_NAME: mydatabase
DB_HOST: Cloud SQLインスタンスのプライベートIP（Cloud Consoleから取得）

## 2. Go APIの作成
プロジェクトのディレクトリ構造
```
my-api/
├── main.go
├── go.mod
└── Dockerfile
```

go.modファイルの作成

```
go mod init cloud-run-postgres
```

依存関係の追加
```
go get github.com/jinzhu/gorm

go get github.com/jinzhu/gorm/dialects/postgres 
```

main.goの作成
```
package main

import (
    "database/sql"
    "fmt"
    "log"
    "net/http"
    "os"

    "github.com/jinzhu/gorm"
    _ "github.com/jinzhu/gorm/dialects/postgres"
)

type User struct {
    ID   uint   `json:"id"`
    Name string `json:"name"`
    Age  int    `json:"age"`
}

var db *gorm.DB

func initDB() {
    var err error
    dbUser := os.Getenv("DB_USER")
    dbPassword := os.Getenv("DB_PASSWORD")
    dbName := os.Getenv("DB_NAME")
    dbHost := os.Getenv("DB_HOST")

    dbURI := fmt.Sprintf("host=%s user=%s dbname=%s password=%s sslmode=disable", dbHost, dbUser, dbName, dbPassword)
    db, err = gorm.Open("postgres", dbURI)
    if err != nil {
        log.Fatal(err)
    }

    db.AutoMigrate(&User{})
}

func getUsers(w http.ResponseWriter, r *http.Request) {
    var users []User
    db.Find(&users)
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(users)
}

func main() {
    initDB()
    defer db.Close()

    http.HandleFunc("/users", getUsers)
    log.Fatal(http.ListenAndServe(":8080", nil))
}

```

Dockerfileの作成
```
# ベースイメージ
FROM golang:1.21 as builder

# 作業ディレクトリを設定
WORKDIR /app

# Goモジュールをコピー
COPY go.mod ./
COPY go.sum ./
RUN go mod download

# アプリケーションのソースをコピー
COPY . .

# ビルド
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# 実行用イメージ
FROM gcr.io/distroless/base

# ビルドしたバイナリをコピー
COPY --from=builder /app/main /main

# ポートを開放
EXPOSE 8080

# エントリポイント
CMD ["/main"]

```

### 3. Dockerイメージのビルドとプッシュ
```
# プロジェクトのルートディレクトリに移動

# Dockerイメージをビルド
docker build -t my-api .

# Artifact Registryにログイン
gcloud auth configure-docker us-central1-docker.pkg.dev

# Artifact Registry APIを有効化
gcloud services enable artifactregistry.googleapis.com

# repositoryの作成
gcloud artifacts repositories create my-repo --repository-format=docker --location=us-central1 --description="My Docker repository"

# DockerイメージをArtifact Registryにプッシュ
docker tag my-api us-central1-docker.pkg.dev/<project-id>/my-repo/my-api:latest
docker push us-central1-docker.pkg.dev/<project-id>/my-repo/my-api:latest

```

### 4. Cloud Runにデプロイ
サーバレスVPCコネクタの作成
```
gcloud compute networks vpc-access connectors create my-vpc-connector --region us-central1 --range 10.8.0.0/28 --network my-vpc

```

cloud runのデプロイ
```
gcloud run deploy my-api \
    --image us-central1-docker.pkg.dev/<project-id>/my-repo/my-api:latest \
    --platform managed \
    --region us-central1 \
    --set-env-vars DB_USER=myuser,DB_PASSWORD=my-password,DB_NAME=mydatabase,DB_HOST=<cloud-sql-private-ip> \
    --vpc-connector my-vpc-connector \
    --allow-unauthenticated

```

gcloud run deploy my-api --image us-central1-docker.pkg.dev/careful-isotope-423019-e1/my-repo/my-api:latest --platform managed --region us-central1 --set-env-vars DB_USER=myuser,DB_PASSWORD=my-password,DB_NAME=mydatabase,DB_HOST=careful-isotope-423019-e1:us-central1:my-postgres --vpc-connector my-vpc-connector --allow-unauthenticated

### 5. 動作確認
デプロイが完了したら、Cloud RunのURLに/usersエンドポイントを追加して、APIにアクセスします。例えば、https://<your-cloud-run-url>/usersでユーザーリストが取得できるはずです。