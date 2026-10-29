package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	redisLib "github.com/redis/go-redis/v9"
	"github.com/quickeats/pkg/config"
	"github.com/quickeats/pkg/events"
	"github.com/quickeats/pkg/idempotency"
	"github.com/quickeats/pkg/outbox"
	httpAdapter "github.com/quickeats/services/order/internal/adapter/http"
	pgRepo "github.com/quickeats/services/order/internal/adapter/postgres"
	"github.com/quickeats/services/order/internal/app"
)

func main() {
	cfg := config.Load()

	pool, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil { slog.Error("db failed", "error", err); os.Exit(1) }
	defer pool.Close()
	pool.Ping(context.Background())

	rdb := redisLib.NewClient(&redisLib.Options{Addr: cfg.RedisURL})
	defer rdb.Close()

	// Event publisher
	publisher, err := events.NewKafkaPublisher(events.ParseBrokers(cfg.KafkaBrokers))
	if err != nil { slog.Error("kafka publisher failed", "error", err); os.Exit(1) }
	defer publisher.Close()

	// Event consumer
	consumer, err := events.NewKafkaConsumer(events.ParseBrokers(cfg.KafkaBrokers))
	if err != nil { slog.Error("kafka consumer failed", "error", err); os.Exit(1) }
	defer consumer.Close()

	// Repos + clients
	orderRepo := pgRepo.NewOrderRepo(pool)
	idempotencyChecker := idempotency.NewChecker(rdb)
	catalogClient := httpAdapter.NewCatalogClient(cfg.CatalogServiceURL)
	paymentClient := httpAdapter.NewPaymentClient(cfg.PaymentServiceURL)

	// Use cases
	placeOrderUC := app.NewPlaceOrderUseCase(pool, orderRepo, idempotencyChecker)
	orderStatusUC := app.NewOrderStatusUseCase(pool, catalogClient, paymentClient)
	earningsUC := app.NewEarningsUseCase(pool)

	// Saga orchestrator
	saga := app.NewSagaOrchestrator(pool, orderRepo, catalogClient, paymentClient)

	// Subscribe to events. Delivery is at-least-once, so each handler is wrapped to
	// skip events this service has already handled.
	once := func(h events.Handler) events.Handler { return events.Deduplicate(idempotencyChecker, "order-svc", h) }
	consumer.Subscribe("order.order.placed", "order-svc", once(saga.HandleOrderPlaced))
	consumer.Subscribe("catalog.stock.reserved", "order-svc", once(saga.HandleStockReserved))
	consumer.Subscribe("catalog.stock.insufficient", "order-svc", once(saga.HandleStockInsufficient))
	consumer.Subscribe("payment.payment.completed", "order-svc", once(saga.HandlePaymentCompleted))
	consumer.Subscribe("payment.payment.failed", "order-svc", once(saga.HandlePaymentFailed))

	// Cancel orders left unpaid past the payment timeout, releasing their stock.
	go saga.RunPaymentTimeouts(context.Background(), time.Minute)

	// Outbox relay
	relay := outbox.NewRelay(pool, publisher, 2*time.Second)
	go relay.Start(context.Background())

	// HTTP
	handler := httpAdapter.NewOrderHandler(placeOrderUC, orderStatusUC, earningsUC, orderRepo, catalogClient, paymentClient)
	router := httpAdapter.NewRouter(handler, cfg.JWTSecret)

	srv := &http.Server{Addr: fmt.Sprintf(":%s", cfg.Port), Handler: router, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second}

	go func() {
		slog.Info("order service starting", "port", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed { slog.Error("server error", "error", err); os.Exit(1) }
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	relay.Stop()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
