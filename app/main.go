package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

// version is injected at build time with -ldflags. This is what makes
// "which image is actually running right now?" answerable at runtime.
var version = "dev"

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/healthz", handleHealth)
	http.HandleFunc("/slow", handleSlow)

	log.Printf("listening on :%s version=%s", port, version)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

// handleRoot reports which pod and which version served the request.
// Curl this in a loop during a rollout to watch versions shift.
func handleRoot(w http.ResponseWriter, r *http.Request) {
	host, _ := os.Hostname()
	writeJSON(w, map[string]string{
		"message": "hello from the platform lab",
		"version": version,
		"pod":     host,
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]string{"status": "ok"})
}

// handleSlow burns CPU so the HorizontalPodAutoscaler has something to react to.
func handleSlow(w http.ResponseWriter, r *http.Request) {
	deadline := time.Now().Add(200 * time.Millisecond)
	n := 0
	for time.Now().Before(deadline) {
		n++
	}
	writeJSON(w, map[string]int{"iterations": n})
}

func writeJSON(w http.ResponseWriter, body any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(body); err != nil {
		fmt.Fprintf(os.Stderr, "encode error: %v\n", err)
	}
}
