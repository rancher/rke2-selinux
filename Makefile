COMMIT ?= $(shell git rev-parse HEAD)
DOCKER_BUILDKIT ?= 1

build:
	DOCKER_BUILDKIT=${DOCKER_BUILDKIT} \
	docker build \
		--build-arg TAG=${TAG} \
		--build-arg COMMIT=${COMMIT} \
		-o ./dist .
