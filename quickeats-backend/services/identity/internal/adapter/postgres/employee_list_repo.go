package postgres

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/quickeats/services/identity/internal/domain"
)

type EmployeeListRepo struct {
	db *pgxpool.Pool
}

func NewEmployeeListRepo(db *pgxpool.Pool) *EmployeeListRepo {
	return &EmployeeListRepo{db: db}
}

func (r *EmployeeListRepo) List(ctx context.Context, orgID string) ([]domain.EmployeeEmail, error) {
	rows, err := r.db.Query(ctx,
		`SELECT e.email, e.created_at,
		        EXISTS(SELECT 1 FROM users u WHERE lower(u.email) = e.email AND u.organisation_id = e.organisation_id)
		 FROM organisation_employee_emails e
		 WHERE e.organisation_id = $1
		 ORDER BY e.email`, orgID)
	if err != nil {
		return nil, fmt.Errorf("list employee emails: %w", err)
	}
	defer rows.Close()

	list := []domain.EmployeeEmail{}
	for rows.Next() {
		var e domain.EmployeeEmail
		if err := rows.Scan(&e.Email, &e.AddedAt, &e.Registered); err != nil {
			return nil, err
		}
		list = append(list, e)
	}
	return list, rows.Err()
}

func (r *EmployeeListRepo) Counts(ctx context.Context) (map[string]int, error) {
	rows, err := r.db.Query(ctx,
		`SELECT organisation_id::text, count(*) FROM organisation_employee_emails GROUP BY organisation_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	counts := map[string]int{}
	for rows.Next() {
		var id string
		var n int
		if err := rows.Scan(&id, &n); err != nil {
			return nil, err
		}
		counts[id] = n
	}
	return counts, rows.Err()
}

func (r *EmployeeListRepo) Check(ctx context.Context, orgID, email string) (bool, bool, error) {
	var hasList, listed bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM organisation_employee_emails WHERE organisation_id = $1),
		        EXISTS(SELECT 1 FROM organisation_employee_emails WHERE organisation_id = $1 AND email = $2)`,
		orgID, email).Scan(&hasList, &listed)
	if err != nil {
		return false, false, fmt.Errorf("check employee list: %w", err)
	}
	return hasList, listed, nil
}

func (r *EmployeeListRepo) Add(ctx context.Context, orgID string, emails []string) (int, error) {
	return insertEmails(ctx, r.db, orgID, emails)
}

func (r *EmployeeListRepo) Replace(ctx context.Context, orgID string, emails []string) (int, int, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return 0, 0, err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx,
		`DELETE FROM organisation_employee_emails WHERE organisation_id = $1 AND NOT (email = ANY($2::text[]))`,
		orgID, emails)
	if err != nil {
		return 0, 0, fmt.Errorf("replace employee emails: %w", err)
	}
	added, err := insertEmails(ctx, tx, orgID, emails)
	if err != nil {
		return 0, 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, 0, err
	}
	return added, int(tag.RowsAffected()), nil
}

func (r *EmployeeListRepo) Remove(ctx context.Context, orgID, email string) (bool, error) {
	tag, err := r.db.Exec(ctx,
		`DELETE FROM organisation_employee_emails WHERE organisation_id = $1 AND email = $2`, orgID, email)
	if err != nil {
		return false, fmt.Errorf("remove employee email: %w", err)
	}
	return tag.RowsAffected() > 0, nil
}

func (r *EmployeeListRepo) Clear(ctx context.Context, orgID string) (int, error) {
	tag, err := r.db.Exec(ctx, `DELETE FROM organisation_employee_emails WHERE organisation_id = $1`, orgID)
	if err != nil {
		return 0, fmt.Errorf("clear employee emails: %w", err)
	}
	return int(tag.RowsAffected()), nil
}

// execer is what insertEmails needs from either the pool or a transaction.
type execer interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

func insertEmails(ctx context.Context, db execer, orgID string, emails []string) (int, error) {
	if len(emails) == 0 {
		return 0, nil
	}
	tag, err := db.Exec(ctx,
		`INSERT INTO organisation_employee_emails (organisation_id, email)
		 SELECT $1, unnest($2::text[])
		 ON CONFLICT DO NOTHING`, orgID, emails)
	if err != nil {
		return 0, fmt.Errorf("insert employee emails: %w", err)
	}
	return int(tag.RowsAffected()), nil
}
