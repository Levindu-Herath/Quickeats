package app

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/quickeats/services/order/internal/domain"
)

// ShopSharePercent matches the payment service's commission split: the shop receives
// 95% of each payment and the platform keeps the rest.
const ShopSharePercent = 95

func shopNet(amount int64) int64 { return amount * ShopSharePercent / 100 }

// ShopEarnings summarises one day of a shop's orders, in the shop's local time.
// Amounts are in cents. Only paid orders that weren't cancelled or rejected earn.
type ShopEarnings struct {
	Date             string         `json:"date"`
	Currency         string         `json:"currency"`
	GrossSales       int64          `json:"grossSales"`
	PlatformFee      int64          `json:"platformFee"`
	NetEarnings      int64          `json:"netEarnings"`
	PendingEarnings  int64          `json:"pendingEarnings"` // part of NetEarnings from orders not picked up yet
	PaidOrders       int            `json:"paidOrders"`
	CompletedOrders  int            `json:"completedOrders"`
	InProgressOrders int            `json:"inProgressOrders"`
	RejectedOrders   int            `json:"rejectedOrders"`
	CancelledOrders  int            `json:"cancelledOrders"`
	RejectedSales    int64          `json:"rejectedSales"`
	AverageOrder     int64          `json:"averageOrder"`
	ItemsSold        int            `json:"itemsSold"`
	TopItems         []ItemSales    `json:"topItems"`
	Hourly           []HourSales    `json:"hourly"` // 24 entries, local hours 0-23
	Week             []DaySales     `json:"week"`   // the 7 days ending on Date, oldest first
	Orders           []EarningOrder `json:"orders"` // the day's orders, newest first
}

type ItemSales struct {
	ItemName string `json:"itemName"`
	Quantity int    `json:"quantity"`
	Sales    int64  `json:"sales"`
}

type HourSales struct {
	Hour   int   `json:"hour"`
	Orders int   `json:"orders"`
	Sales  int64 `json:"sales"`
}

type DaySales struct {
	Date        string `json:"date"`
	Orders      int    `json:"orders"`
	NetEarnings int64  `json:"netEarnings"`
}

type EarningOrder struct {
	ID           string             `json:"id"`
	Status       domain.OrderStatus `json:"status"`
	PickupCode   string             `json:"pickupCode,omitempty"`
	TotalAmount  int64              `json:"totalAmount"`
	NetAmount    int64              `json:"netAmount"` // 0 when the order didn't earn
	ItemCount    int                `json:"itemCount"`
	RejectReason string             `json:"rejectReason,omitempty"`
	CreatedAt    time.Time          `json:"createdAt"`
}

// earningRow and itemRow are what BuildShopEarnings needs from the database.
type earningRow struct {
	ID           string
	Status       domain.OrderStatus
	PickupCode   string
	TotalAmount  int64
	RejectReason string
	CreatedAt    time.Time
}

type itemRow struct {
	OrderID  string
	ItemName string
	Quantity int
	Subtotal int64
}

// earns reports whether an order in this status was paid and kept by the shop.
func earns(s domain.OrderStatus) bool {
	switch s {
	case domain.StatusConfirmed, domain.StatusAccepted, domain.StatusPreparing, domain.StatusReady, domain.StatusPickedUp:
		return true
	}
	return false
}

type EarningsUseCase struct{ db *pgxpool.Pool }

func NewEarningsUseCase(db *pgxpool.Pool) *EarningsUseCase { return &EarningsUseCase{db: db} }

// ParseEarningsDay returns local midnight of date ("2006-01-02") in a zone utcOffsetMinutes
// ahead of UTC (330 for Sri Lanka). An empty date means today in that zone.
func ParseEarningsDay(date string, utcOffsetMinutes int, now time.Time) (time.Time, error) {
	if utcOffsetMinutes < -14*60 || utcOffsetMinutes > 14*60 {
		return time.Time{}, fmt.Errorf("tzOffset must be between -840 and 840 minutes")
	}
	loc := time.FixedZone("", utcOffsetMinutes*60)
	if date == "" {
		y, m, d := now.In(loc).Date()
		return time.Date(y, m, d, 0, 0, 0, 0, loc), nil
	}
	day, err := time.ParseInLocation("2006-01-02", date, loc)
	if err != nil {
		return time.Time{}, fmt.Errorf("date must look like 2026-01-31")
	}
	return day, nil
}

// Get loads the shop's orders for day (local midnight, from ParseEarningsDay) and the
// six days before it, and summarises them.
func (uc *EarningsUseCase) Get(ctx context.Context, shopID string, day time.Time) (*ShopEarnings, error) {
	dayEnd := day.AddDate(0, 0, 1)
	weekStart := day.AddDate(0, 0, -6)

	rows, err := uc.db.Query(ctx,
		`SELECT id, status, COALESCE(pickup_code,''), total_amount, COALESCE(reject_reason,''), created_at
		 FROM orders WHERE shop_id=$1 AND created_at >= $2 AND created_at < $3`, shopID, weekStart, dayEnd)
	if err != nil {
		return nil, fmt.Errorf("load orders: %w", err)
	}
	var orders []earningRow
	for rows.Next() {
		var o earningRow
		if err := rows.Scan(&o.ID, &o.Status, &o.PickupCode, &o.TotalAmount, &o.RejectReason, &o.CreatedAt); err != nil {
			rows.Close()
			return nil, fmt.Errorf("scan order: %w", err)
		}
		orders = append(orders, o)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("load orders: %w", err)
	}

	rows, err = uc.db.Query(ctx,
		`SELECT i.order_id, i.item_name, i.quantity, i.subtotal
		 FROM order_items i JOIN orders o ON o.id = i.order_id
		 WHERE o.shop_id=$1 AND o.created_at >= $2 AND o.created_at < $3`, shopID, day, dayEnd)
	if err != nil {
		return nil, fmt.Errorf("load items: %w", err)
	}
	defer rows.Close()
	var items []itemRow
	for rows.Next() {
		var it itemRow
		if err := rows.Scan(&it.OrderID, &it.ItemName, &it.Quantity, &it.Subtotal); err != nil {
			return nil, fmt.Errorf("scan item: %w", err)
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("load items: %w", err)
	}

	return BuildShopEarnings(day, orders, items), nil
}

// BuildShopEarnings summarises orders (covering day and the six days before it) and the
// items of day's orders. day is local midnight; its zone decides which day an order is in.
func BuildShopEarnings(day time.Time, orders []earningRow, items []itemRow) *ShopEarnings {
	loc := day.Location()
	const layout = "2006-01-02"
	e := &ShopEarnings{
		Date: day.Format(layout), Currency: "LKR",
		TopItems: []ItemSales{}, Hourly: make([]HourSales, 24), Orders: []EarningOrder{},
	}
	for h := range e.Hourly {
		e.Hourly[h].Hour = h
	}
	weekIndex := map[string]int{}
	for i := 0; i < 7; i++ {
		d := day.AddDate(0, 0, i-6).Format(layout)
		weekIndex[d] = i
		e.Week = append(e.Week, DaySales{Date: d})
	}

	itemsByOrder := map[string][]itemRow{}
	for _, it := range items {
		itemsByOrder[it.OrderID] = append(itemsByOrder[it.OrderID], it)
	}

	sort.Slice(orders, func(i, j int) bool { return orders[i].CreatedAt.After(orders[j].CreatedAt) })
	topItems := map[string]*ItemSales{}
	for _, o := range orders {
		local := o.CreatedAt.In(loc)
		earned := earns(o.Status)
		net := int64(0)
		if earned {
			net = shopNet(o.TotalAmount)
			if i, ok := weekIndex[local.Format(layout)]; ok {
				e.Week[i].Orders++
				e.Week[i].NetEarnings += net
			}
		}
		if local.Format(layout) != e.Date || o.Status == domain.StatusPendingPayment {
			continue
		}

		count := 0
		for _, it := range itemsByOrder[o.ID] {
			count += it.Quantity
		}
		e.Orders = append(e.Orders, EarningOrder{
			ID: o.ID, Status: o.Status, PickupCode: o.PickupCode, TotalAmount: o.TotalAmount,
			NetAmount: net, ItemCount: count, RejectReason: o.RejectReason, CreatedAt: o.CreatedAt,
		})

		switch {
		case o.Status == domain.StatusRejected:
			e.RejectedOrders++
			e.RejectedSales += o.TotalAmount
		case !earned:
			e.CancelledOrders++
		}
		if !earned {
			continue
		}

		e.PaidOrders++
		e.GrossSales += o.TotalAmount
		e.NetEarnings += net
		if o.Status == domain.StatusPickedUp {
			e.CompletedOrders++
		} else {
			e.InProgressOrders++
			e.PendingEarnings += net
		}
		e.Hourly[local.Hour()].Orders++
		e.Hourly[local.Hour()].Sales += o.TotalAmount
		e.ItemsSold += count
		for _, it := range itemsByOrder[o.ID] {
			s := topItems[it.ItemName]
			if s == nil {
				s = &ItemSales{ItemName: it.ItemName}
				topItems[it.ItemName] = s
			}
			s.Quantity += it.Quantity
			s.Sales += it.Subtotal
		}
	}

	e.PlatformFee = e.GrossSales - e.NetEarnings
	if e.PaidOrders > 0 {
		e.AverageOrder = e.GrossSales / int64(e.PaidOrders)
	}
	for _, s := range topItems {
		e.TopItems = append(e.TopItems, *s)
	}
	sort.Slice(e.TopItems, func(i, j int) bool {
		a, b := e.TopItems[i], e.TopItems[j]
		if a.Quantity != b.Quantity {
			return a.Quantity > b.Quantity
		}
		if a.Sales != b.Sales {
			return a.Sales > b.Sales
		}
		return a.ItemName < b.ItemName
	})
	if len(e.TopItems) > 5 {
		e.TopItems = e.TopItems[:5]
	}
	return e
}
