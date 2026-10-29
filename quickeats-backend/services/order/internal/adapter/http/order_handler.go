package http

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/quickeats/pkg/httputil"
	"github.com/quickeats/pkg/middleware"
	"github.com/quickeats/services/order/internal/app"
	"github.com/quickeats/services/order/internal/domain"
	"github.com/quickeats/services/order/internal/port"
)

type OrderHandler struct {
	placeOrderUC  *app.PlaceOrderUseCase
	orderStatusUC *app.OrderStatusUseCase
	orderRepo     port.OrderRepository
	earningsUC    *app.EarningsUseCase
	catalog       port.CatalogClient
	payment       port.PaymentClient
}

func NewOrderHandler(placeOrderUC *app.PlaceOrderUseCase, orderStatusUC *app.OrderStatusUseCase, earningsUC *app.EarningsUseCase, orderRepo port.OrderRepository, catalog port.CatalogClient, payment port.PaymentClient) *OrderHandler {
	return &OrderHandler{placeOrderUC: placeOrderUC, orderStatusUC: orderStatusUC, earningsUC: earningsUC, orderRepo: orderRepo, catalog: catalog, payment: payment}
}

type PlaceOrderHTTPRequest struct {
	ShopID         string       `json:"shopId"`
	IdempotencyKey string       `json:"idempotencyKey"`
	PaymentMethod  string       `json:"paymentMethod"`
	Items          []OrderItemDTO `json:"items"`
}

type OrderItemDTO struct {
	MenuItemID string `json:"menuItemId"`
	ItemName   string `json:"itemName"`
	Quantity   int    `json:"quantity"`
	UnitPrice  int64  `json:"unitPrice"`
}

type UpdateStatusRequest struct {
	Status string `json:"status"`
}

type RejectRequest struct {
	Reason string `json:"reason"`
}

type CancelRequest struct {
	Reason string `json:"reason,omitempty"`
}

func (h *OrderHandler) PlaceOrder(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	var req PlaceOrderHTTPRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		httputil.RespondError(w, err)
		return
	}

	if req.IdempotencyKey == "" || req.ShopID == "" || len(req.Items) == 0 {
		httputil.RespondError(w, httputil.ErrValidation("idempotencyKey, shopId, and items are required", nil))
		return
	}

	// Customers may only order from open shops that serve their organisation.
	access, err := h.catalog.ShopAccess(r.Context(), req.ShopID, claims.OrganisationID)
	if err != nil {
		httputil.RespondError(w, httputil.ErrServiceUnavailable("could not check the shop, try again"))
		return
	}
	if !access.Exists || !access.Visible {
		httputil.RespondError(w, httputil.ErrNotFound("shop"))
		return
	}
	if !access.IsOpen {
		httputil.RespondError(w, httputil.ErrBusinessRule("SHOP_CLOSED", "this shop is closed right now"))
		return
	}

	// Card is the only payment method.
	if req.PaymentMethod == "" {
		req.PaymentMethod = "card"
	}
	if req.PaymentMethod != "card" {
		httputil.RespondError(w, httputil.ErrBusinessRule("UNSUPPORTED_PAYMENT_METHOD", "pay with a card"))
		return
	}

	var items []domain.OrderItem
	var total int64
	for _, dto := range req.Items {
		items = append(items, domain.OrderItem{
			MenuItemID: dto.MenuItemID, ItemName: dto.ItemName,
			Quantity: dto.Quantity, UnitPrice: dto.UnitPrice,
		})
		total += int64(dto.Quantity) * dto.UnitPrice
	}

	// Refuse up front when the card can't pay, so the customer gets a clear answer
	// instead of an order that is cancelled a moment later. If the payment service
	// can't be asked, carry on: the saga still declines the charge and cancels.
	if check, err := h.payment.CheckCard(r.Context(), claims.UserID, total); err != nil {
		slog.Warn("card check unavailable, placing order anyway", "error", err)
	} else if !check.HasCard {
		httputil.RespondError(w, httputil.ErrBusinessRule("NO_CARD", "add a card to place your order"))
		return
	} else if !check.Sufficient {
		httputil.RespondError(w, httputil.ErrBusinessRule("INSUFFICIENT_FUNDS", "your card doesn't have enough balance for this order"))
		return
	}

	order, err := h.placeOrderUC.Execute(r.Context(), app.PlaceOrderRequest{
		CustomerID:     claims.UserID,
		ShopID:         req.ShopID,
		IdempotencyKey: req.IdempotencyKey,
		PaymentMethod:  req.PaymentMethod,
		Items:          items,
	})
	if err != nil {
		if err == domain.ErrDuplicateOrder {
			httputil.RespondError(w, httputil.ErrConflict("order with this idempotency key already exists"))
		} else {
			httputil.RespondError(w, err)
		}
		return
	}

	httputil.RespondJSON(w, http.StatusCreated, order)
}

func (h *OrderHandler) GetOrder(w http.ResponseWriter, r *http.Request) {
	order, err := h.orderRepo.GetByID(r.Context(), chi.URLParam(r, "id"))
	if err != nil || order == nil {
		httputil.RespondError(w, httputil.ErrNotFound("order"))
		return
	}
	httputil.RespondJSON(w, http.StatusOK, order)
}

func (h *OrderHandler) ListByCustomer(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	params := httputil.ParsePagination(r)
	orders, err := h.orderRepo.ListByCustomer(r.Context(), claims.UserID, params.Limit, params.Cursor)
	if err != nil {
		httputil.RespondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusOK, orders)
}

func (h *OrderHandler) ListByShop(w http.ResponseWriter, r *http.Request) {
	shopID := chi.URLParam(r, "shopId")
	params := httputil.ParsePagination(r)
	orders, err := h.orderRepo.ListByShop(r.Context(), shopID, params.Limit, params.Cursor)
	if err != nil {
		httputil.RespondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusOK, orders)
}

func (h *OrderHandler) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req UpdateStatusRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		httputil.RespondError(w, err)
		return
	}

	order, err := h.orderRepo.GetByID(r.Context(), id)
	if err != nil || order == nil {
		httputil.RespondError(w, httputil.ErrNotFound("order"))
		return
	}

	oldStatus := order.Status
	if err := order.TransitionTo(domain.OrderStatus(req.Status)); err != nil {
		httputil.RespondError(w, httputil.ErrBusinessRule("INVALID_STATUS_TRANSITION", err.Error()))
		return
	}

	if err := h.orderStatusUC.UpdateStatus(r.Context(), order, oldStatus); err != nil {
		respondStatusError(w, err)
		return
	}

	httputil.RespondJSON(w, http.StatusOK, order)
}

// CancelOrder lets the customer cancel their order until the shop accepts it.
func (h *OrderHandler) CancelOrder(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	id := chi.URLParam(r, "id")
	order, err := h.orderRepo.GetByID(r.Context(), id)
	if err != nil || order == nil || order.CustomerID != claims.UserID {
		httputil.RespondError(w, httputil.ErrNotFound("order"))
		return
	}

	oldStatus := order.Status
	if err := order.TransitionTo(domain.StatusCancelled); err != nil {
		httputil.RespondError(w, httputil.ErrBusinessRule("CANNOT_CANCEL", "the shop has already accepted this order, it can no longer be cancelled"))
		return
	}

	// Cancel also releases the reserved stock and refunds the card.
	if err := h.orderStatusUC.Cancel(r.Context(), order, oldStatus, "cancelled_by_customer"); err != nil {
		respondStatusError(w, err)
		return
	}
	order.CancelReason = "cancelled_by_customer"
	httputil.RespondJSON(w, http.StatusOK, order)
}

func (h *OrderHandler) RejectOrder(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req RejectRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		httputil.RespondError(w, err)
		return
	}

	order, err := h.orderRepo.GetByID(r.Context(), id)
	if err != nil || order == nil {
		httputil.RespondError(w, httputil.ErrNotFound("order"))
		return
	}

	oldStatus := order.Status
	if err := order.TransitionTo(domain.StatusRejected); err != nil {
		httputil.RespondError(w, httputil.ErrBusinessRule("CANNOT_REJECT", "only orders waiting for acceptance can be rejected"))
		return
	}

	if err := h.orderStatusUC.Reject(r.Context(), order, oldStatus, req.Reason); err != nil {
		respondStatusError(w, err)
		return
	}
	order.RejectReason = req.Reason
	httputil.RespondJSON(w, http.StatusOK, order)
}

// ShopEarnings returns a day's earnings for the shop: ?date=2026-10-29&tzOffset=330
// (minutes ahead of UTC, so the day is the shop's local day). Both are optional;
// the default is today in UTC. Staff only see their own shop.
func (h *OrderHandler) ShopEarnings(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetClaims(r.Context())
	shopID := chi.URLParam(r, "shopId")
	if claims.Role != "admin" && claims.ShopID != shopID {
		httputil.RespondError(w, httputil.ErrNotFound("shop"))
		return
	}

	offset := 0
	if v := r.URL.Query().Get("tzOffset"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			httputil.RespondError(w, httputil.ErrValidation("tzOffset must be a whole number of minutes", map[string]string{"field": "tzOffset"}))
			return
		}
		offset = n
	}
	day, err := app.ParseEarningsDay(r.URL.Query().Get("date"), offset, time.Now())
	if err != nil {
		httputil.RespondError(w, httputil.ErrValidation(err.Error(), nil))
		return
	}

	earnings, err := h.earningsUC.Get(r.Context(), shopID, day)
	if err != nil {
		slog.Error("shop earnings failed", "shop_id", shopID, "error", err)
		httputil.RespondError(w, httputil.ErrInternal("could not load earnings"))
		return
	}
	httputil.RespondJSON(w, http.StatusOK, earnings)
}

// respondStatusError reports a lost race (another request changed the order first)
// as a conflict, and anything else as is.
func respondStatusError(w http.ResponseWriter, err error) {
	if errors.Is(err, domain.ErrStatusChanged) {
		httputil.RespondError(w, httputil.ErrConflict(err.Error()))
		return
	}
	httputil.RespondError(w, err)
}
