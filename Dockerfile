# Stage 1: build a static binary. Nothing from this stage ships.
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY app/go.mod ./
COPY app/*.go ./

# VERSION is passed in by CI as the git SHA, so the running pod can report
# exactly which commit it came from.
ARG VERSION=dev

# CGO off + static linking is what lets the final stage be `scratch`.
RUN CGO_ENABLED=0 GOOS=linux go build \
      -ldflags="-s -w -X main.version=${VERSION}" \
      -o /out/app .

# Stage 2: the shipped image. No shell, no package manager, no OS.
# Nothing to exploit because there is nothing in here but the binary.
FROM scratch
COPY --from=build /out/app /app

# Run as a non-root UID. scratch has no /etc/passwd, so this is a bare numeric ID.
USER 65532:65532

EXPOSE 8080
ENTRYPOINT ["/app"]
