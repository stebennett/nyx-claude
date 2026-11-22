FROM dhi.io/golang:1.23.4-dev@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa AS build
WORKDIR /src
COPY . .
RUN go build -o /app ./cmd/app

FROM dhi.io/static:20250419@sha256:1295ce0b300e0972ee6034f75f2161a629c12d760526f2e029528416dec2f96e
COPY --from=build /app /app
ENTRYPOINT ["/app"]
