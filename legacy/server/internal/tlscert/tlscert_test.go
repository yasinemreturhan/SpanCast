package tlscert

import (
	"crypto/tls"
	"io"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
)

func TestCreateAndPersist(t *testing.T) {
	dir := t.TempDir()

	c1, err := LoadOrCreate(dir)
	if err != nil {
		t.Fatal(err)
	}
	c2, err := LoadOrCreate(dir) // ikinci çağrı diskten okumalı
	if err != nil {
		t.Fatal(err)
	}
	if c1.Fingerprint != c2.Fingerprint {
		t.Fatalf("kalıcılık bozuk: %s != %s", c1.Fingerprint, c2.Fingerprint)
	}
}

func TestFingerprintFormat(t *testing.T) {
	c, err := LoadOrCreate(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	// SHA-256 → 64 hex karakter
	if !regexp.MustCompile(`^[0-9a-f]{64}$`).MatchString(c.Fingerprint) {
		t.Fatalf("parmak izi formatı yanlış: %q", c.Fingerprint)
	}
}

func TestDifferentDirsDifferentCerts(t *testing.T) {
	a, _ := LoadOrCreate(t.TempDir())
	b, _ := LoadOrCreate(t.TempDir())
	if a.Fingerprint == b.Fingerprint {
		t.Fatal("farklı dizinlerde aynı sertifika üretilmemeli")
	}
}

func TestServesHTTPS(t *testing.T) {
	c, err := LoadOrCreate(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("guvenli"))
	}))
	srv.TLS = &tls.Config{Certificates: []tls.Certificate{c.Cert}}
	srv.StartTLS()
	defer srv.Close()

	// İstemci: CA doğrulaması yerine parmak izi sabitleme (ürün istemcisinin
	// yapacağı gibi).
	client := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{
		InsecureSkipVerify: true,
		VerifyConnection: func(cs tls.ConnectionState) error {
			return VerifyFingerprint(cs.PeerCertificates[0], c.Fingerprint)
		},
	}}}
	resp, err := client.Get(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "guvenli" {
		t.Fatalf("beklenmeyen gövde: %q", body)
	}
}

func TestVerifyFingerprintRejectsWrong(t *testing.T) {
	c, _ := LoadOrCreate(t.TempDir())
	leaf, err := Leaf(c.Cert)
	if err != nil {
		t.Fatal(err)
	}
	if err := VerifyFingerprint(leaf, "deadbeef"); err == nil {
		t.Fatal("yanlış parmak izi reddedilmeliydi")
	}
	if err := VerifyFingerprint(leaf, c.Fingerprint); err != nil {
		t.Fatalf("doğru parmak izi kabul edilmeliydi: %v", err)
	}
}
