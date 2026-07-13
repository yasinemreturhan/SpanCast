// Package ws, signal.Hub'ı WebSocket'e bağlar: /ws?role=receiver oda açar,
// /ws?role=sender&pin=…&name=… odaya katılır. Yazımlar tek goroutine'den
// (kanal üzerinden) yapılır; okuma döngüsü kopuşta hub'a haber verir.
package ws

import (
	"errors"
	"net/http"

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

// Handler: /ws endpoint'i.
type Handler struct {
	hub *signal.Hub
}

func NewHandler(hub *signal.Hub) *Handler { return &Handler{hub: hub} }

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
			h.hub.FromReceiver(rs, m)
		}

	case "sender":
		pin := r.URL.Query().Get("pin")
		name := r.URL.Query().Get("name")
		if name == "" {
			name = "cihaz"
		}
		ss, err := h.hub.JoinRoom(pin, name, conn)
		if err != nil {
			reason := "join-failed"
			switch {
			case errors.Is(err, room.ErrNotFound):
				reason = "bad-pin"
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
