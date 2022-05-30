include make/config.mk

TEST?=./...
.DEFAULT_GOAL := ci
PACT_CLI="docker run --rm -v ${PWD}:${PWD} -e PACT_BROKER_BASE_URL -e PACT_BROKER_USERNAME -e PACT_BROKER_PASSWORD -e PACT_BROKER_TOKEN pactfoundation/pact-cli:latest"

ci:: deps clean bin test pact #goveralls

# Run the ci target from a developer machine with the environment variables
# set as if it was on Travis CI.
# Use this for quick feedback when playing around with your workflows.
fake_ci:
	@CI=true \
	APP_SHA=`git rev-parse --short HEAD`+`date +%s` \
	APP_BRANCH=`git rev-parse --abbrev-ref HEAD` \
	make ci

# same as above, but just for pact
fake_pact:
	@CI=true \
	APP_SHA=`git rev-parse --short HEAD`+`date +%s` \
	APP_BRANCH=`git rev-parse --abbrev-ref HEAD` \
	make pact

docker:
	@echo "--- 🛠 Starting docker"
	docker-compose up -d

bin:
	go build -o build/pact-go

clean:
	mkdir -p ./examples/pacts
	rm -rf build output dist examples/pacts

deps: download_plugins
	@echo "--- 🐿  Fetching build dependencies "
	cd /tmp; \
	go install github.com/axw/gocov/gocov@latest; \
	go install github.com/mattn/goveralls@latest; \
	go install golang.org/x/tools/cmd/cover@latest; \
	go install github.com/modocache/gover@latest; \
	go install github.com/mitchellh/gox@latest; \
	cd -

download_plugins:
	@if [ ! -d ~/.pact/plugins/protobuf-0.1.7 ]; then\
		@echo "--- 🐿  Installing plugins"; \
		mkdir -p ~/.pact/plugins/protobuf-0.1.7; \
		wget https://github.com/pactflow/pact-protobuf-plugin/releases/download/v-0.1.7/pact-plugin.json -O ~/.pact/plugins/protobuf-0.1.7/pact-plugin.json; \
		wget https://github.com/pactflow/pact-protobuf-plugin/releases/download/v-0.1.7/pact-protobuf-plugin-linux-x86_64.gz -O ~/.pact/plugins/protobuf-0.1.7/pact-protobuf-plugin-linux-x86_64.gz; \
		gunzip -N ~/.pact/plugins/protobuf-0.1.7/pact-protobuf-plugin-linux-x86_64.gz; \
		chmod +x ~/.pact/plugins/protobuf-0.1.7/pact-protobuf-plugin; \
	fi

goveralls:
	goveralls -service="travis-ci" -coverprofile=coverage.txt -repotoken $(COVERALLS_TOKEN)

cli:
	@if [ ! -d pact/bin ]; then\
		echo "--- 🐿 Installing Pact CLI dependencies"; \
		curl -fsSL https://raw.githubusercontent.com/pact-foundation/pact-ruby-standalone/master/install.sh | bash -x; \
  fi

install: bin
	echo "--- 🐿 Installing Pact FFI dependencies"
	./build/pact-go	 -l DEBUG install --libDir /tmp

pact: clean install #docker
	@echo "--- 🔨 Running Pact examples"
	go test -v -tags=consumer -count=1 github.com/pact-foundation/pact-go/v2/examples/...
	make publish
	go test -v -timeout=30s -tags=provider -count=1 github.com/pact-foundation/pact-go/v2/examples/...

publish:
	@echo "-- 📃 Publishing pacts"
	@"${PACT_CLI}" publish ${PWD}/examples/pacts --consumer-app-version ${APP_SHA} --tag ${APP_BRANCH} --tag prod

release:
	echo "--- 🚀 Releasing it"
	"$(CURDIR)/scripts/release.sh"

test: deps install
	@echo "--- ✅ Running tests"
	@if [ -f coverage.txt ]; then rm coverage.txt; fi;
	@echo "mode: count" > coverage.txt
	@for d in $$(go list ./... | grep -v vendor | grep -v examples); \
		do \
			go test -v -race -coverprofile=profile.out -covermode=atomic $$d; \
			if [ $$? != 0 ]; then \
				exit 1; \
			fi; \
			if [ -f profile.out ]; then \
					cat profile.out | tail -n +2 >> coverage.txt; \
					rm profile.out; \
			fi; \
	done; \
	go tool cover -func coverage.txt


testrace:
	go test -race $(TEST) $(TESTARGS)

updatedeps:
	go get -d -v -p 2 ./...

.PHONY: install bin default dev test pact updatedeps clean release
