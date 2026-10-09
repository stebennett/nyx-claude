FROM dhi.io/golang:1.23.4-dev@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa AS build
WORKDIR /src
COPY . .
RUN go build -o /app ./cmd/app

FROM dhi.io/static:20250101@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
COPY --from=build /app /app
ENTRYPOINT ["/app"]
