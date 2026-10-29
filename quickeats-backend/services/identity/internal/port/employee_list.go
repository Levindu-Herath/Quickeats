package port

import (
	"context"

	"github.com/quickeats/services/identity/internal/domain"
)

// EmployeeListRepository stores each organisation's optional list of employee emails.
// Emails passed in are already normalised (domain.NormalizeEmail).
type EmployeeListRepository interface {
	List(ctx context.Context, orgID string) ([]domain.EmployeeEmail, error)
	// Counts returns the list size of every organisation that has one, by organisation ID.
	Counts(ctx context.Context) (map[string]int, error)
	// Check reports whether the organisation keeps a list and, if so, whether email is on it.
	Check(ctx context.Context, orgID, email string) (hasList, listed bool, err error)
	// Add puts emails on the list, skipping ones already there, and returns how many were new.
	Add(ctx context.Context, orgID string, emails []string) (added int, err error)
	// Replace makes the list exactly emails.
	Replace(ctx context.Context, orgID string, emails []string) (added, removed int, err error)
	// Remove takes one email off the list; false if it was not there.
	Remove(ctx context.Context, orgID, email string) (bool, error)
	// Clear empties the list, so the organisation goes back to checking domains only.
	Clear(ctx context.Context, orgID string) (removed int, err error)
}
