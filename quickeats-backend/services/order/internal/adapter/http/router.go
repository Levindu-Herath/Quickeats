package http

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	chiMiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/quickeats/pkg/middleware"
)

func NewRouter(handler *OrderHandler, jwtSecret string) *chi.Mux {
	r := chi.NewRouter()
	r.Use(chiMiddleware.Recoverer)
	r.Use(middleware.RequestID)
	r.Use(middleware.Logging)

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "order"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		r.Use(middleware.Auth(jwtSecret))

		// Customer routes
		r.Post("/orders", handler.PlaceOrder)
		r.Get("/orders", handler.ListByCustomer)
		r.Get("/orders/{id}", handler.GetOrder)
		r.Post("/orders/{id}/cancel", handler.CancelOrder)

		// Shop staff routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.RequireRole("shop_staff", "shop_owner", "admin"))
			r.Get("/shops/{shopId}/orders", handler.ListByShop)
			r.Get("/shops/{shopId}/earnings", handler.ShopEarnings)
			r.Patch("/orders/{id}/status", handler.UpdateStatus)
			r.Post("/orders/{id}/reject", handler.RejectOrder)
		})
	})

	return r
}
