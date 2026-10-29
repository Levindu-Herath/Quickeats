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
	"github.com/quickeats/pkg/config"
	"github.com/quickeats/services/identity/internal/adapter/gateway"
	httpAdapter "github.com/quickeats/services/identity/internal/adapter/http"
	"github.com/quickeats/services/identity/internal/adapter/jwt"
	pgRepo "github.com/quickeats/services/identity/internal/adapter/postgres"
	"github.com/quickeats/services/identity/internal/app"
)

func main() {
	cfg := config.Load()

	// Database
	pool, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	if err := pool.Ping(context.Background()); err != nil {
		slog.Error("failed to ping database", "error", err)
		os.Exit(1)
	}
	slog.Info("connected to database")

	// Repositories
	userRepo := pgRepo.NewUserRepo(pool)
	orgRepo := pgRepo.NewOrgRepo(pool)
	employeeRepo := pgRepo.NewEmployeeListRepo(pool)

	// Token issuer
	tokenIssuer := jwt.NewIssuer(cfg.JWTSecret, cfg.JWTExpiry, cfg.JWTRefreshExpiry)

	// Platform admin for the dashboard, from ADMIN_EMAIL / ADMIN_PASSWORD
	if err := app.EnsureAdmin(context.Background(), userRepo, os.Getenv("ADMIN_EMAIL"), os.Getenv("ADMIN_PASSWORD")); err != nil {
		slog.Error("failed to create admin account", "error", err)
		os.Exit(1)
	}

	// Use cases
	catalog := gateway.NewCatalogClient(cfg.CatalogServiceURL)
	registerUC := app.NewRegisterUseCase(userRepo, orgRepo, employeeRepo)
	registerShopUC := app.NewRegisterShopUseCase(userRepo, orgRepo, catalog)
	loginUC := app.NewLoginUseCase(userRepo, tokenIssuer)
	profileUC := app.NewProfileUseCase(userRepo, orgRepo, catalog)
	orgsUC := app.NewOrganisationsUseCase(orgRepo, employeeRepo)
	employeesUC := app.NewEmployeeListUseCase(orgRepo, employeeRepo)

	// HTTP handlers
	authHandler := httpAdapter.NewAuthHandler(registerUC, registerShopUC, loginUC, tokenIssuer, userRepo)
	orgHandler := httpAdapter.NewOrgHandler(orgsUC, employeesUC)
	profileHandler := httpAdapter.NewProfileHandler(profileUC)

	// Router
	router := httpAdapter.NewRouter(authHandler, orgHandler, profileHandler, cfg.JWTSecret)

	// Server
	srv := &http.Server{
		Addr:         fmt.Sprintf(":%s", cfg.Port),
		Handler:      router,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	// Graceful shutdown
	go func() {
		slog.Info("identity service starting", "port", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	slog.Info("shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
