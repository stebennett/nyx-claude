FROM dhi.io/golang:1.27.4-dev@sha256:c096bb340b7b9a205cb704c75d5ca877392f8aed70c818ae255b10bee1822b60 AS build
WORKDIR /src
COPY . .
RUN go build -o /app ./cmd/app

FROM dhi.io/static:20250101@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
COPY --from=build /app /app
ENTRYPOINT ["/app"]
