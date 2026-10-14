// Package tlscert: cihaz başına kalıcı self-signed TLS sertifikası üretir ve
// SHA-256 parmak izini sunar. Parmak izi, eşleşme QR'ına gömülerek istemcinin
// sertifika sabitlemesi (pinning) yapmasına imkân verir — CA'sız LAN güveni.
package tlscert

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"time"
)

const (
	certFile = "ushare-cert.pem"
	keyFile  = "ushare-key.pem"
	validFor = 10 * 365 * 24 * time.Hour
)

// Identity: yüklü sertifika + hex SHA-256 parmak izi.
type Identity struct {
	Cert        tls.Certificate
	Fingerprint string
}

// LoadOrCreate, dir altında sertifika varsa yükler, yoksa üretip kaydeder.
func LoadOrCreate(dir string) (*Identity, error) {
	cp, kp := filepath.Join(dir, certFile), filepath.Join(dir, keyFile)

	if _, err := os.Stat(cp); err == nil {
		cert, err := tls.LoadX509KeyPair(cp, kp)
		if err != nil {
			return nil, fmt.Errorf("sertifika yüklenemedi: %w", err)
		}
		return identityFrom(cert)
	}

	cert, err := generate()
	if err != nil {
		return nil, err
	}
	if err := save(cert, cp, kp); err != nil {
		return nil, err
	}
	return identityFrom(cert)
}

func identityFrom(cert tls.Certificate) (*Identity, error) {
	leaf, err := Leaf(cert)
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(leaf.Raw)
	return &Identity{Cert: cert, Fingerprint: hex.EncodeToString(sum[:])}, nil
}

// Leaf, tls.Certificate'in yaprak (ilk) sertifikasını çözer.
func Leaf(cert tls.Certificate) (*x509.Certificate, error) {
	if len(cert.Certificate) == 0 {
		return nil, errors.New("sertifika zinciri boş")
	}
	return x509.ParseCertificate(cert.Certificate[0])
}

// VerifyFingerprint, sertifikanın SHA-256 özetini beklenen hex değerle
// sabit zamanlı karşılaştırır.
func VerifyFingerprint(cert *x509.Certificate, wantHex string) error {
	sum := sha256.Sum256(cert.Raw)
	got := hex.EncodeToString(sum[:])
	if subtle.ConstantTimeCompare([]byte(got), []byte(wantHex)) != 1 {
		return fmt.Errorf("sertifika parmak izi uyuşmuyor")
	}
	return nil
}

func generate() (tls.Certificate, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return tls.Certificate{}, err
	}

	host, _ := os.Hostname()
	tmpl := x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "UniversalShare " + host},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(validFor),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{host, "localhost"},
		IPAddresses:  localIPs(),
	}

	der, err := x509.CreateCertificate(rand.Reader, &tmpl, &tmpl, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, err
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}, nil
}

// localIPs: loopback dahil mevcut IPv4 adresleri (SAN olarak eklenir).
func localIPs() []net.IP {
	ips := []net.IP{net.IPv4(127, 0, 0, 1)}
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return ips
	}
	for _, a := range addrs {
		if ipn, ok := a.(*net.IPNet); ok && !ipn.IP.IsLoopback() && ipn.IP.To4() != nil {
			ips = append(ips, ipn.IP.To4())
		}
	}
	return ips
}

func save(cert tls.Certificate, certPath, keyPath string) error {
	if err := os.MkdirAll(filepath.Dir(certPath), 0o700); err != nil {
		return err
	}
	certOut, err := os.OpenFile(certPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	defer certOut.Close()
	if err := pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: cert.Certificate[0]}); err != nil {
		return err
	}

	keyDER, err := x509.MarshalECPrivateKey(cert.PrivateKey.(*ecdsa.PrivateKey))
	if err != nil {
		return err
	}
	keyOut, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	defer keyOut.Close()
	return pem.Encode(keyOut, &pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
}
