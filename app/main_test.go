package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandleHealth(t *testing.T) {
	rec := httptest.NewRecorder()
	handleHealth(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", rec.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("bad json: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("want status ok, got %q", body["status"])
	}
}

func TestHandleRootReportsVersion(t *testing.T) {
	rec := httptest.NewRecorder()
	handleRoot(rec, httptest.NewRequest(http.MethodGet, "/", nil))

	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("bad json: %v", err)
	}
	if body["version"] == "" {
		t.Error("version must never be empty")
	}
	if body["pod"] == "" {
		t.Error("pod must never be empty")
	}
}
