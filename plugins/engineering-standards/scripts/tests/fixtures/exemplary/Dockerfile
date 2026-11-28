FROM dhi.io/golang:1.27.4-dev@sha256:c5c02f15e0fd96999d48d70545b7c76b7080caebc9367680812d5244ac316bee AS build
WORKDIR /src
COPY . .
RUN go build -o /app ./cmd/app

FROM dhi.io/static:20250101@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
COPY --from=build /app /app
ENTRYPOINT ["/app"]
