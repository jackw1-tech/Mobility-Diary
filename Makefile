FLUTTER ?= flutter

.PHONY: test test-services test-backend test-mobile test-web test-web-e2e test-har-model

test: test-backend test-mobile test-web test-web-e2e

test-services:
	cd back-end/infra && docker compose up -d db redis minio
	cd back-end/infra && docker compose up minio-init

test-backend: test-services
	cd back-end/ninja && ../.venv/bin/pytest -q

test-mobile:
	cd mobile/diary && $(FLUTTER) analyze
	cd mobile/diary && $(FLUTTER) test

test-web:
	cd web && npm test
	cd web && npm run build

test-web-e2e:
	cd web && npm run test:e2e

test-har-model:
	cd back-end/ninja && ../.venv/bin/python manage.py smoke_har_model
