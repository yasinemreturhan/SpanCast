// Package ws, signal.Hub'ı WebSocket'e bağlar: /ws?role=receiver oda açar,
// /ws?role=sender&pin=…&name=… odaya katılır. Yazımlar tek goroutine'den
// (kanal üzerinden) yapılır; okuma döngüsü kopuşta hub'a haber verir.
package ws

import (
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
	"github.com/yasinemreturhan/DoScreen/server/internal/room"
	"github.com/yasinemreturhan/DoScreen/server/internal/signal"
)

var upgrader = websocket.Upgrader{
	// LAN uygulaması: farklı origin'lerden (cihaz IP'leri) erişim normal.
	CheckOrigin: func(*http.Request) bool { return true },
}

// wsConn: gorilla bağlantısını signal.Conn'a uyarlar. Send'ler kanala yazar;
// tek writer goroutine gorilla'nın "tek eşzamanlı yazar" kuralını korur.
type wsConn struct {
	c    *websocket.Conn
	out  chan signal.Message
	done chan struct{}
}

func newWSConn(c *websocket.Conn) *wsConn {
	w := &wsConn{c: c, out: make(chan signal.Message, 32), done: make(chan struct{})}
	go w.writeLoop()
	return w
}

func (w *wsConn) writeLoop() {
	for {
		select {
		case m := <-w.out:
			if err := w.c.WriteJSON(m); err != nil {
				return
			}
		case <-w.done:
			return
		}
	}
}

func (w *wsConn) Send(m signal.Message) error {
	select {
	case w.out <- m:
		return nil
	case <-w.done:
		return errors.New("bağlantı kapalı")
	}
}

func (w *wsConn) Close() {
	select {
	case <-w.done:
	default:
		close(w.done)
	}
	w.c.Close()
}

// Kaba kuvvet sınırı: IP başına dakikada en fazla bu kadar hatalı PIN denemesi.
const (
	maxPinFails   = 10
	pinFailWindow = time.Minute
)

// Handler: /ws endpoint'i.
type Handler struct {
	hub     *signal.Hub
	limiter *Limiter
}

func NewHandler(hub *signal.Hub) *Handler {
	return &Handler{hub: hub, limiter: NewLimiter(maxPinFails, pinFailWindow)}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	role := r.URL.Query().Get("role")
	if role != "receiver" && role != "sender" {
		http.Error(w, "role receiver|sender olmalı", http.StatusBadRequest)
		return
	}
	c, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	conn := newWSConn(c)

	switch role {
	case "receiver":
		rs := h.hub.OpenRoom(conn)
		for {
			var m signal.Message
			if err := c.ReadJSON(&m); err != nil {
				h.hub.ReceiverGone(rs)
				conn.Close()
				return
			}
			if m.Type == "regen" {
				h.hub.RegeneratePIN(rs)
				continue
			}
			h.hub.FromReceiver(rs, m)
		}

	case "sender":
		name := r.URL.Query().Get("name")
		if name == "" {
			name = "cihaz"
		}
		ip := remoteIP(r)

		// Kimlik doğrulama: PIN ağdan geçmez — salt challenge'a HMAC proof.
		if !h.limiter.Allowed(ip) {
			c.WriteJSON(signal.Message{Type: "error", Reason: "rate-limited"})
			conn.Close()
			return
		}
		salt := signal.NewSalt()
		conn.Send(signal.Message{Type: "challenge", Payload: mustJSON(map[string]string{"salt": salt})})

		var auth signal.Message
		c.SetReadDeadline(time.Now().Add(30 * time.Second))
		if err := c.ReadJSON(&auth); err != nil || auth.Type != "auth" {
			conn.Close()
			return
		}
		c.SetReadDeadline(time.Time{}) // doğrulama sonrası süresiz
		var proof struct {
			Proof string `json:"proof"`
		}
		json.Unmarshal(auth.Payload, &proof)

		ss, err := h.hub.JoinByProof(salt, proof.Proof, name, conn)
		if err != nil {
			reason := "join-failed"
			switch {
			case errors.Is(err, room.ErrNotFound):
				reason = "bad-pin"
				h.limiter.Fail(ip)
			case errors.Is(err, room.ErrExpired):
				reason = "pin-expired"
			case errors.Is(err, room.ErrRoomFull):
				reason = "room-full"
			}
			// Bu noktada kuyrukta mesaj yok ve hub bağlantıyı tutmuyor;
			// doğrudan yazmak yarışsızdır ve kapanmadan önce iletimi garantiler.
			c.WriteJSON(signal.Message{Type: "error", Reason: reason})
			conn.Close()
			return
		}
		conn.Send(signal.Message{Type: "paired", From: ss.ID()})
		for {
			var m signal.Message
			if err := c.ReadJSON(&m); err != nil {
				h.hub.SenderGone(ss)
				conn.Close()
				return
			}
			h.hub.FromSender(ss, m)
		}
	}
}

// remoteIP: RemoteAddr'dan portu ayıklar.
func remoteIP(r *http.Request) string {
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return ip
}

func mustJSON(v any) json.RawMessage {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return b
}
