package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/quickeats/services/order/internal/domain"
)

type OrderRepo struct{ db *pgxpool.Pool }

func NewOrderRepo(db *pgxpool.Pool) *OrderRepo { return &OrderRepo{db: db} }

func (r *OrderRepo) Create(ctx context.Context, order *domain.Order) error {
	// Used by saga for direct creates; PlaceOrderUseCase uses its own tx
	return nil
}

func (r *OrderRepo) GetByID(ctx context.Context, id string) (*domain.Order, error) {
	var o domain.Order
	err := r.db.QueryRow(ctx,
		`SELECT id,idempotency_key,customer_id,shop_id,status,pickup_code,cancellation_deadline,total_amount,currency,payment_method,COALESCE(reject_reason,''),cancel_reason,created_at,updated_at
		 FROM orders WHERE id=$1`, id,
	).Scan(&o.ID, &o.IdempotencyKey, &o.CustomerID, &o.ShopID, &o.Status, &o.PickupCode,
		&o.CancellationDeadline, &o.TotalAmount, &o.Currency, &o.PaymentMethod, &o.RejectReason, &o.CancelReason, &o.CreatedAt, &o.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) { return nil, nil }
	if err != nil { return nil, fmt.Errorf("get order: %w", err) }

	// Load items
	rows, err := r.db.Query(ctx,
		`SELECT id,order_id,menu_item_id,item_name,quantity,unit_price,subtotal FROM order_items WHERE order_id=$1`, id)
	if err != nil { return nil, err }
	defer rows.Close()
	for rows.Next() {
		var item domain.OrderItem
		rows.Scan(&item.ID, &item.OrderID, &item.MenuItemID, &item.ItemName, &item.Quantity, &item.UnitPrice, &item.Subtotal)
		o.Items = append(o.Items, item)
	}
	return &o, nil
}

func (r *OrderRepo) GetByIdempotencyKey(ctx context.Context, key string) (*domain.Order, error) {
	var id string
	err := r.db.QueryRow(ctx, `SELECT id FROM orders WHERE idempotency_key=$1`, key).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) { return nil, nil }
	if err != nil { return nil, err }
	return r.GetByID(ctx, id)
}

func (r *OrderRepo) UpdateStatus(ctx context.Context, id string, status domain.OrderStatus) error {
	_, err := r.db.Exec(ctx, `UPDATE orders SET status=$1, updated_at=now() WHERE id=$2`, status, id)
	return err
}

func (r *OrderRepo) SetPickupCode(ctx context.Context, id, code string) error {
	_, err := r.db.Exec(ctx, `UPDATE orders SET pickup_code=$1 WHERE id=$2`, code, id)
	return err
}

func (r *OrderRepo) SetRejectReason(ctx context.Context, id, reason string) error {
	_, err := r.db.Exec(ctx, `UPDATE orders SET reject_reason=$1 WHERE id=$2`, reason, id)
	return err
}

func (r *OrderRepo) ListByShop(ctx context.Context, shopID string, limit int, cursor string) ([]*domain.Order, error) {
	query := `SELECT id,idempotency_key,customer_id,shop_id,status,pickup_code,cancellation_deadline,total_amount,currency,payment_method,COALESCE(reject_reason,''),cancel_reason,created_at,updated_at
		FROM orders WHERE shop_id=$1 ORDER BY created_at DESC LIMIT $2`
	rows, err := r.db.Query(ctx, query, shopID, limit)
	if err != nil { return nil, err }
	defer rows.Close()
	orders, err := scanOrders(rows)
	if err != nil { return nil, err }
	return orders, r.loadItems(ctx, orders)
}

func (r *OrderRepo) ListByCustomer(ctx context.Context, customerID string, limit int, cursor string) ([]*domain.Order, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id,idempotency_key,customer_id,shop_id,status,pickup_code,cancellation_deadline,total_amount,currency,payment_method,COALESCE(reject_reason,''),cancel_reason,created_at,updated_at
		 FROM orders WHERE customer_id=$1 ORDER BY created_at DESC LIMIT $2`, customerID, limit)
	if err != nil { return nil, err }
	defer rows.Close()
	orders, err := scanOrders(rows)
	if err != nil { return nil, err }
	return orders, r.loadItems(ctx, orders)
}

// loadItems fills in each order's line items with one query for the whole list.
func (r *OrderRepo) loadItems(ctx context.Context, orders []*domain.Order) error {
	if len(orders) == 0 { return nil }
	byID := make(map[string]*domain.Order, len(orders))
	ids := make([]string, len(orders))
	for i, o := range orders {
		byID[o.ID] = o
		ids[i] = o.ID
	}
	rows, err := r.db.Query(ctx,
		`SELECT id,order_id,menu_item_id,item_name,quantity,unit_price,subtotal FROM order_items WHERE order_id = ANY($1)`, ids)
	if err != nil { return fmt.Errorf("load order items: %w", err) }
	defer rows.Close()
	for rows.Next() {
		var item domain.OrderItem
		if err := rows.Scan(&item.ID, &item.OrderID, &item.MenuItemID, &item.ItemName, &item.Quantity, &item.UnitPrice, &item.Subtotal); err != nil {
			return err
		}
		if o := byID[item.OrderID]; o != nil { o.Items = append(o.Items, item) }
	}
	return rows.Err()
}

func (r *OrderRepo) FindTimedOutOrders(ctx context.Context, status domain.OrderStatus, olderThanMinutes int) ([]*domain.Order, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id,idempotency_key,customer_id,shop_id,status,pickup_code,cancellation_deadline,total_amount,currency,payment_method,COALESCE(reject_reason,''),cancel_reason,created_at,updated_at
		 FROM orders WHERE status=$1 AND created_at < now() - ($2 || ' minutes')::interval`, status, fmt.Sprintf("%d", olderThanMinutes))
	if err != nil { return nil, err }
	defer rows.Close()
	return scanOrders(rows)
}

func scanOrders(rows pgx.Rows) ([]*domain.Order, error) {
	var orders []*domain.Order
	for rows.Next() {
		var o domain.Order
		if err := rows.Scan(&o.ID, &o.IdempotencyKey, &o.CustomerID, &o.ShopID, &o.Status, &o.PickupCode,
			&o.CancellationDeadline, &o.TotalAmount, &o.Currency, &o.PaymentMethod, &o.RejectReason, &o.CancelReason, &o.CreatedAt, &o.UpdatedAt); err != nil {
			return nil, err
		}
		orders = append(orders, &o)
	}
	return orders, nil
}
