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