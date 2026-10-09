package main

import "net/http"

func main() {
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {})
	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {})
	_ = http.ListenAndServe(":8080", nil)
}
