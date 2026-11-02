FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY pkg/ ./pkg/
COPY services/notification/ ./services/notification/
WORKDIR /app/services/notification
RUN CGO_ENABLED=0 go build -o /server ./cmd/server

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
COPY --from=builder /server /server
USER 65532:65532
EXPOSE 8085 8086
CMD ["/server"]
