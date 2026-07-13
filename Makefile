GO ?= $(HOME)/toolchains/go/bin/go

.PHONY: build test vet webtest smoke

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
