FROM dhi.io/golang:1.23.4-dev@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa AS build
WORKDIR /src
COPY . .
RUN go build -o /app ./cmd/app

FROM dhi.io/static:20250419@sha256:f3a87dc858c61b3f731ab2f86349ef10953b15918f167dbf9581543255364e32
COPY --from=build /app /app
ENTRYPOINT ["/app"]
