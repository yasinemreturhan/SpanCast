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

		var authMsg signal.Message
		c.SetReadDeadline(time.Now().Add(30 * time.Second))
		if err := c.ReadJSON(&authMsg); err != nil {
			conn.Close()
			return
		}
		c.SetReadDeadline(time.Time{})

		var ss *signal.SenderSession

		switch authMsg.Type {
		case "trust":
			// Güvenilir cihaz — PIN doğrulaması atlanır, jeton kontrol edilir.
			var body struct {
				Token string `json:"token"`
			}
			json.Unmarshal(authMsg.Payload, &body)
			var err error
			ss, err = h.hub.JoinByToken(body.Token, name, conn)
			if err != nil {
				reason := "bad-token"
				if errors.Is(err, room.ErrRoomFull) {
					reason = "room-full"
				}
				c.WriteJSON(signal.Message{Type: "error", Reason: reason})
				conn.Close()
				return
			}
			conn.Send(signal.Message{Type: "paired", From: ss.ID()})

		case "auth":
			// Normal PIN challenge-response akışı.
			var proof struct {
				Proof string `json:"proof"`
			}
			json.Unmarshal(authMsg.Payload, &proof)
			var err error
			ss, err = h.hub.JoinByProof(salt, proof.Proof, name, conn)
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
				c.WriteJSON(signal.Message{Type: "error", Reason: reason})
				conn.Close()
				return
			}
			// Başarılı PIN doğrulaması sonrası güven jetonu üret.
			pairedPayload := json.RawMessage(`null`)
			if tok, err := h.hub.IssueToken(ss); err == nil {
				pairedPayload = mustJSON(map[string]string{"token": tok})
			}
			conn.Send(signal.Message{Type: "paired", From: ss.ID(), Payload: pairedPayload})

		default:
			conn.Close()
			return
		}

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
