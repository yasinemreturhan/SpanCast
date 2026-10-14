package room

import (
	"errors"
	"regexp"
	"testing"
	"time"
)

func newTestManager(now *time.Time) *Manager {
	m := NewManager()
	if now != nil {
		m.now = func() time.Time { return *now }
	}
	return m
}

func TestPinFormat(t *testing.T) {
	m := newTestManager(nil)
	r := m.CreateRoom()
	if !regexp.MustCompile(`^\d{6}$`).MatchString(r.PIN()) {
		t.Fatalf("PIN 6 haneli olmalı, geldi: %q", r.PIN())
	}
}

func TestJoinOK(t *testing.T) {
	m := newTestManager(nil)
	r := m.CreateRoom()
	got, err := m.Join(r.PIN())
	if err != nil {
		t.Fatalf("Join hata verdi: %v", err)
	}
	if got != r {
		t.Fatal("Join yanlış odayı döndürdü")
	}
}

func TestJoinWrongPin(t *testing.T) {
	m := newTestManager(nil)
	m.CreateRoom()
	if _, err := m.Join("000000"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("ErrNotFound bekleniyordu, geldi: %v", err)
	}
}

func TestJoinExpired(t *testing.T) {
	now := time.Now()
	m := newTestManager(&now)
	r := m.CreateRoom()
	now = now.Add(PinTTL + time.Second) // hiç sender katılmadan TTL geçti
	if _, err := m.Join(r.PIN()); !errors.Is(err, ErrExpired) {
		t.Fatalf("ErrExpired bekleniyordu, geldi: %v", err)
	}
}

func TestJoinNotExpiredWhenActive(t *testing.T) {
	now := time.Now()
	m := newTestManager(&now)
	r := m.CreateRoom()
	if _, err := r.AddSender("laptop"); err != nil {
		t.Fatal(err)
	}
	now = now.Add(PinTTL + time.Minute) // oda aktif: PIN yaşamaya devam eder
	if _, err := m.Join(r.PIN()); err != nil {
		t.Fatalf("aktif odada Join hata vermemeli: %v", err)
	}
}

func TestMaxSenders(t *testing.T) {
	m := newTestManager(nil)
	r := m.CreateRoom()
	for i := 0; i < MaxSenders; i++ {
		if _, err := r.AddSender("s"); err != nil {
			t.Fatalf("%d. sender eklenemedi: %v", i+1, err)
		}
	}
	if _, err := r.AddSender("fazla"); !errors.Is(err, ErrRoomFull) {
		t.Fatalf("ErrRoomFull bekleniyordu, geldi: %v", err)
	}
}

func TestSenderLeaveFreesSlot(t *testing.T) {
	m := newTestManager(nil)
	r := m.CreateRoom()
	ids := make([]string, MaxSenders)
	for i := range ids {
		s, _ := r.AddSender("s")
		ids[i] = s.ID
	}
	r.RemoveSender(ids[0])
	if _, err := r.AddSender("yeni"); err != nil {
		t.Fatalf("slot boşaldıktan sonra eklenebilmeli: %v", err)
	}
}

func TestRegenerateInvalidatesOldPin(t *testing.T) {
	m := newTestManager(nil)
	r := m.CreateRoom()
	old := r.PIN()
	fresh := m.Regenerate(r)
	if fresh == old {
		t.Fatal("yeni PIN eskisiyle aynı olmamalı")
	}
	if _, err := m.Join(old); !errors.Is(err, ErrNotFound) {
		t.Fatalf("eski PIN geçersiz olmalı, geldi: %v", err)
	}
	if _, err := m.Join(fresh); err != nil {
		t.Fatalf("yeni PIN çalışmalı: %v", err)
	}
}

func TestCloseRemovesRoom(t *testing.T) {
	m := newTestManager(nil)
	r := m.CreateRoom()
	m.Close(r)
	if _, err := m.Join(r.PIN()); !errors.Is(err, ErrNotFound) {
		t.Fatalf("kapanan odaya Join edilememeli, geldi: %v", err)
	}
}
