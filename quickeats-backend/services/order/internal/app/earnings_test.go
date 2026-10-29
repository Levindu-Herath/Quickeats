package app

import (
	"testing"
	"time"

	"github.com/quickeats/services/order/internal/domain"
)

func TestParseEarningsDay(t *testing.T) {
	// 20:00 UTC on the 28th is 01:30 on the 29th in Sri Lanka (UTC+5:30).
	now := time.Date(2026, 10, 28, 20, 0, 0, 0, time.UTC)
	day, err := ParseEarningsDay("", 330, now)
	if err != nil || day.Format("2006-01-02") != "2026-10-29" {
		t.Fatalf("today = %v, %v; want 2026-10-29", day, err)
	}
	if want := time.Date(2026, 10, 28, 18, 30, 0, 0, time.UTC); !day.Equal(want) {
		t.Errorf("local midnight = %v, want %v", day.UTC(), want)
	}
	for _, bad := range []struct {
		date   string
		offset int
	}{{"29-10-2026", 330}, {"2026-13-01", 330}, {"2026-10-29", 900}} {
		if _, err := ParseEarningsDay(bad.date, bad.offset, now); err == nil {
			t.Errorf("ParseEarningsDay(%q, %d) accepted", bad.date, bad.offset)
		}
	}
}

func TestBuildShopEarnings(t *testing.T) {
	loc := time.FixedZone("", 330*60)
	day := time.Date(2026, 10, 29, 0, 0, 0, 0, loc)
	at := func(d, h int) time.Time { return time.Date(2026, 10, d, h, 15, 0, 0, loc) }

	orders := []earningRow{
		{ID: "a", Status: domain.StatusPickedUp, TotalAmount: 45000, CreatedAt: at(29, 9)},
		{ID: "b", Status: domain.StatusAccepted, TotalAmount: 12000, CreatedAt: at(29, 9)},
		{ID: "c", Status: domain.StatusConfirmed, TotalAmount: 33333, CreatedAt: at(29, 13)},
		{ID: "d", Status: domain.StatusRejected, TotalAmount: 9000, RejectReason: "Item is out of stock", CreatedAt: at(29, 14)},
		{ID: "e", Status: domain.StatusCancelled, TotalAmount: 5000, CreatedAt: at(29, 15)},
		{ID: "f", Status: domain.StatusPendingPayment, TotalAmount: 7000, CreatedAt: at(29, 16)},
		{ID: "y", Status: domain.StatusPickedUp, TotalAmount: 20000, CreatedAt: at(28, 12)},
		{ID: "z", Status: domain.StatusRejected, TotalAmount: 20000, CreatedAt: at(28, 12)},
	}
	items := []itemRow{
		{OrderID: "a", ItemName: "Chicken Rice", Quantity: 1, Subtotal: 45000},
		{OrderID: "b", ItemName: "Fish Bun", Quantity: 1, Subtotal: 12000},
		{OrderID: "c", ItemName: "Fish Bun", Quantity: 2, Subtotal: 24000},
		{OrderID: "c", ItemName: "Tea", Quantity: 1, Subtotal: 9333},
		{OrderID: "d", ItemName: "Kottu", Quantity: 3, Subtotal: 9000},
	}

	e := BuildShopEarnings(day, orders, items)

	gross := int64(45000 + 12000 + 33333)
	net := shopNet(45000) + shopNet(12000) + shopNet(33333)
	if e.GrossSales != gross || e.NetEarnings != net || e.PlatformFee != gross-net {
		t.Errorf("gross/net/fee = %d/%d/%d, want %d/%d/%d", e.GrossSales, e.NetEarnings, e.PlatformFee, gross, net, gross-net)
	}
	if e.PendingEarnings != shopNet(12000)+shopNet(33333) {
		t.Errorf("pending = %d", e.PendingEarnings)
	}
	if e.PaidOrders != 3 || e.CompletedOrders != 1 || e.InProgressOrders != 2 || e.RejectedOrders != 1 || e.CancelledOrders != 1 {
		t.Errorf("counts paid/completed/inProgress/rejected/cancelled = %d/%d/%d/%d/%d, want 3/1/2/1/1",
			e.PaidOrders, e.CompletedOrders, e.InProgressOrders, e.RejectedOrders, e.CancelledOrders)
	}
	if e.RejectedSales != 9000 || e.AverageOrder != gross/3 || e.ItemsSold != 5 {
		t.Errorf("rejectedSales/average/itemsSold = %d/%d/%d", e.RejectedSales, e.AverageOrder, e.ItemsSold)
	}
	if len(e.TopItems) != 3 || e.TopItems[0].ItemName != "Fish Bun" || e.TopItems[0].Quantity != 3 || e.TopItems[0].Sales != 36000 {
		t.Errorf("top items = %+v; want Fish Bun x3 first, rejected Kottu left out", e.TopItems)
	}
	if e.Hourly[9].Orders != 2 || e.Hourly[9].Sales != 57000 || e.Hourly[13].Orders != 1 || e.Hourly[14].Orders != 0 {
		t.Errorf("hourly 9/13/14 = %+v %+v %+v", e.Hourly[9], e.Hourly[13], e.Hourly[14])
	}
	// The day's list leaves out the unpaid order and the other day's orders, newest first.
	if len(e.Orders) != 5 || e.Orders[0].ID != "e" || e.Orders[4].ID != "a" && e.Orders[4].ID != "b" {
		t.Errorf("orders = %+v", e.Orders)
	}
	for _, o := range e.Orders {
		if (o.ID == "d" || o.ID == "e") && o.NetAmount != 0 {
			t.Errorf("order %s didn't earn but has net %d", o.ID, o.NetAmount)
		}
	}
	if len(e.Week) != 7 || e.Week[6].Date != "2026-10-29" || e.Week[6].NetEarnings != net || e.Week[6].Orders != 3 ||
		e.Week[5].Date != "2026-10-28" || e.Week[5].NetEarnings != shopNet(20000) || e.Week[5].Orders != 1 || e.Week[0].Date != "2026-10-23" {
		t.Errorf("week = %+v", e.Week)
	}
}

func TestBuildShopEarningsUsesLocalDay(t *testing.T) {
	// 19:00 UTC on the 28th is 00:30 on the 29th in Sri Lanka: it belongs to the 29th.
	day := time.Date(2026, 10, 29, 0, 0, 0, 0, time.FixedZone("", 330*60))
	orders := []earningRow{{ID: "a", Status: domain.StatusPickedUp, TotalAmount: 10000, CreatedAt: time.Date(2026, 10, 28, 19, 0, 0, 0, time.UTC)}}
	e := BuildShopEarnings(day, orders, nil)
	if e.PaidOrders != 1 || e.Hourly[0].Orders != 1 {
		t.Errorf("paid=%d hour0=%d, want the order counted at 00:xx on the 29th", e.PaidOrders, e.Hourly[0].Orders)
	}
}

func TestBuildShopEarningsEmptyDay(t *testing.T) {
	e := BuildShopEarnings(time.Date(2026, 10, 29, 0, 0, 0, 0, time.UTC), nil, nil)
	if e.NetEarnings != 0 || e.AverageOrder != 0 || len(e.Hourly) != 24 || len(e.Week) != 7 || e.TopItems == nil || e.Orders == nil {
		t.Errorf("empty day = %+v", e)
	}
}
