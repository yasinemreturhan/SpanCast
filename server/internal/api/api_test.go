package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/yasinemreturhan/DoScreen/server/internal/discovery"
)

type fakePeers struct{ list []discovery.Peer }

func (f fakePeers) Peers() []discovery.Peer { return f.list }

func newAPI(peers []discovery.Peer) http.Handler {
	return New("test-cihaz", "0.2-test", fakePeers{peers})
}

func get(t *testing.T, h http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", path, nil))
	return rec
}

func TestHealthz(t *testing.T) {
	rec := get(t, newAPI(nil), "/healthz")
	if rec.Code != 200 || strings.TrimSpace(rec.Body.String()) != "ok" {
		t.Fatalf("healthz: %d %q", rec.Code, rec.Body.String())
	}
}

func TestInfo(t *testing.T) {
	rec := get(t, newAPI(nil), "/api/info")
	var got struct {
		Name    string   `json:"name"`
		Version string   `json:"version"`
		Caps    []string `json:"caps"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Name != "test-cihaz" || got.Version != "0.2-test" || len(got.Caps) == 0 {
		t.Fatalf("info alanları eksik: %+v", got)
	}
}

func TestPeersEmpty(t *testing.T) {
	rec := get(t, newAPI(nil), "/api/peers")
	if strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Fatalf("boş liste [] olmalı, geldi: %q", rec.Body.String())
	}
}

func TestPeersListed(t *testing.T) {
	rec := get(t, newAPI([]discovery.Peer{{Name: "tv", Addr: "10.0.0.5", Port: 8788}}), "/api/peers")
	var got []discovery.Peer
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Name != "tv" {
		t.Fatalf("peer listesi yanlış: %+v", got)
	}
}

func TestQRPng(t *testing.T) {
	rec := get(t, newAPI(nil), "/api/qr?data=ushare://pair?pin=123456")
	if rec.Code != 200 {
		t.Fatalf("qr status: %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "image/png" {
		t.Fatalf("content-type: %q", ct)
	}
	pngMagic := []byte{0x89, 'P', 'N', 'G'}
	if !bytes.HasPrefix(rec.Body.Bytes(), pngMagic) {
		t.Fatal("PNG imzası yok")
	}
}

func TestQRTooLong(t *testing.T) {
	rec := get(t, newAPI(nil), "/api/qr?data="+strings.Repeat("a", 600))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("400 bekleniyordu: %d", rec.Code)
	}
}

func TestQRMissingData(t *testing.T) {
	rec := get(t, newAPI(nil), "/api/qr")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("400 bekleniyordu: %d", rec.Code)
	}
}
