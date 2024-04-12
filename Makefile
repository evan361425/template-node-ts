SHELL := /usr/bin/env bash -o errexit -o pipefail -o nounset

# TODO: should edit for your project
OWNER=evan361425
PACKAGE?=my-awesome-package

revision?=$(shell git rev-parse HEAD)
version?=$(shell git describe --tags --abbrev=0)
now?=$(shell date -u '+%Y-%m-%dT%H:%M:%SZ')
repo?=$(OWNER)/$(PACKAGE)
token=$(shell cat ~/.npmrc | grep 'npm.pkg.github.com/:_authToken' | cut -d= -f2)

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-23s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: deploy
deploy: build-image lint-image ## Publish docker image
	if ! grep -q "ghcr.io" ~/.docker/config.json; then \
		docker login ghcr.io -u $(OWNER) -p $(token); \
	fi
	docker tag $(PACKAGE):$(version) ghcr.io/$(repo):$(version)
	docker push ghcr.io/$(repo):$(version)

##@ Build
.PHONY: build-image
build-image: ## Build docker image
	docker build -t $(PACKAGE):$(version) \
			--build-arg version=${version} \
			--build-arg revision=${revision} \
			--build-arg builtAt=${now} \
			--build-arg githubToken=${token} \
			-f Dockerfile .

.PHONY: build-ts
build-ts: clean ## Build js files to dist
	npx tsc --project tsconfig.production.json

.PHONY: build-assets
build-assets: build-ts ## Build assets
	node scripts/config-schema.js src/config.ts
	node scripts/config-default.js
	printf '# Makefile possible commands\n\n```shell\n$$ make help\n' > docs/commands.md
	make help | sed -r "s/\x1B\[(36|0|1)m//g" >> docs/commands.md
	printf '```\n' >> docs/commands.md

.PHONY: bump
bump: dep-bumper ## Bump the version
	@current=$$(echo '$(version)' | cut -c 2-); \
	read -p "Enter new version(origin version $$current): " target; \
	if [[ ! $$target =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]]; then \
		echo "Version must be in x.x.x format"; \
		exit 1; \
	fi; \
	if [[ $$(echo -e "$$target\n$$current" | sort -V | head -n1) == $$target ]]; then \
		echo "Version must be above $$current"; \
		exit 1; \
	fi; \
	make build-assets; \
	npm version --no-commit-hooks --no-git-tag-version $$target; \
	bumper --latestVersion=v$$target

##@ Dev

# TODO: should edit for your project if you have any private dependencies
.PHONY: install
install: ## Install all dependencies
	printf "@private:registry=https://npm.pkg.github.com\n//npm.pkg.github.com/:_authToken=${token}" > .npmrc
	npm install --ignore-scripts

.PHONY: install-prod
install-prod: install ## Install production dependencies only
	npm prune --omit=dev --ignore-scripts

.PHONY: format
format: ## Format by prettier
	npx prettier --write 'src/**/*.ts' 'test/**/*.ts' 'test_integration/*.ts'

.PHONY: lint
lint: ## Lint by eslint
	npx eslint 'src/**/*.ts' 'test/**/*.ts' 'test_integration/*.ts'
	npx prettier --check 'src/**/*.ts' 'test/**/*.ts' 'test_integration/*.ts'

.PHONY: lint-image
lint-image: ## Lint image by trivy
	docker run --rm -i \
		-v /var/.trivy:/root/.cache/trivy \
		-v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy image \
			--image-config-scanners misconfig \
			--image-config-scanners secret \
			--skip-dirs node_modules \
			--exit-code 1 \
			--severity HIGH,CRITICAL \
			--ignore-unfixed \
			--no-progress \
			$(PACKAGE):$(version)

.PHONY: test
test: ## Run tests by Node.js test runner
	node --import tsx --test --test-timeout 60000 test/**/*.spec.ts

.PHONY: test-only
test-only: ## Run tests with only statement
	node --import tsx --test-only --test --test-timeout 60000 test/**/*.spec.ts

.PHONY: test-integration
test-integration: mock ## Run tests with dependencies
	# Should add exit flag https://github.com/nodejs/node/issues/49925
	node --import tsx --test --test-timeout 60000 test/**/*.spec.ts test_integration/*.spec.ts

.PHONY: test-ci
test-ci: clean mock ## Run tests for CI
	mkdir -p coverage
	npx tsc # compile files
	if ! node --test --experimental-test-coverage --test-timeout 60000 --test-reporter=spec \
		dist/test/**/*.spec.js dist/test_integration/*.spec.js; then \
		node --test dist/test/**/*.spec.js dist/test_integration/*.spec.js; \
	fi

.PHONY: test-coverage
test-coverage: clean mock ## Run tests with coverage and re-run without coverage if failed (to show error message)
	mkdir -p coverage
	npx tsc # compile files
	if ! node --test --experimental-test-coverage --test-timeout 60000 \
		--test-reporter=lcov --test-reporter-destination=coverage/lcov.info \
		dist/test/**/*.spec.js dist/test_integration/*.spec.js; then \
		node --test dist/test/**/*.spec.js dist/test_integration/*.spec.js; \
	fi
	lcov --remove coverage/lcov.info -o coverage/lcov.filtered.info \
		'test/*' 'test_integration/*' 'src/third-party/*' | grep -v 'Excluding dist'
	genhtml coverage/lcov.filtered.info -o coverage/html > /dev/null
	open coverage/html/index.html

# TODO: should edit for your project if needed (e.g. mock server)
.PHONY: mock
mock: ## Mock dependencies for testing
	echo "TODO: you should add your dependencies here"

.PHONY: clean
clean: ## Clean all build files
	rm -rf dist coverage

.PHONY: clean-mock
clean-mock: ## Clean mock servers
	docker stop mock-redis || true

##@ Dep

.PHONY: dep-bumper
dep-bumper: ## Check bumper installed
	@command -v bumper >/dev/null || npm install -g @evan361425/version-bumper
