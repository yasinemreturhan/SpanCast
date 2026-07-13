GO ?= $(HOME)/toolchains/go/bin/go
VERSION ?= dev

.PHONY: build test vet webtest smoke dist

# Çapraz derleme: tek Go kod tabanından tüm masaüstü platformları.
dist:
	cd server && GOOS=windows GOARCH=amd64 $(GO) build -ldflags="-s -w" -o ../dist/ushare-windows-amd64.exe .
	cd server && GOOS=linux   GOARCH=amd64 $(GO) build -ldflags="-s -w" -o ../dist/ushare-linux-amd64 .
	cd server && GOOS=linux   GOARCH=arm64 $(GO) build -ldflags="-s -w" -o ../dist/ushare-linux-arm64 .
	cd server && GOOS=darwin  GOARCH=arm64 $(GO) build -ldflags="-s -w" -o ../dist/ushare-darwin-arm64 .
	cd server && GOOS=darwin  GOARCH=amd64 $(GO) build -ldflags="-s -w" -o ../dist/ushare-darwin-amd64 .

build:
	cd server && $(GO) build -o ../bin/ushare .

test:
	cd server && $(GO) test ./...

vet:
	cd server && $(GO) vet ./...

webtest:
	node --test server/web/js/

smoke: build
	./bin/ushare -port 8788 & sleep 2; \
	curl -sf http://localhost:8788/healthz && echo " healthz OK"; \
	kill %1
