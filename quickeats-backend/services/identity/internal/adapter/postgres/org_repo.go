package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/quickeats/services/identity/internal/domain"
)

type OrgRepo struct {
	db *pgxpool.Pool
}

func NewOrgRepo(db *pgxpool.Pool) *OrgRepo {
	return &OrgRepo{db: db}
}

func (r *OrgRepo) Create(ctx context.Context, org *domain.Organisation) error {
	configJSON, _ := json.Marshal(org.VerifyConfig)
	_, err := r.db.Exec(ctx,
		`INSERT INTO organisations (id, name, slug, verify_method, verify_config, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		org.ID, org.Name, org.Slug, org.VerifyMethod, configJSON, org.CreatedAt, org.UpdatedAt,
	)
	if isUniqueViolation(err) {
		return domain.ErrOrgSlugTaken
	}
	if err != nil {
		return fmt.Errorf("insert organisation: %w", err)
	}
	return nil
}

func (r *OrgRepo) Update(ctx context.Context, org *domain.Organisation) error {
	configJSON, _ := json.Marshal(org.VerifyConfig)
	tag, err := r.db.Exec(ctx,
		`UPDATE organisations SET name=$1, slug=$2, verify_method=$3, verify_config=$4, updated_at=now() WHERE id=$5`,
		org.Name, org.Slug, org.VerifyMethod, configJSON, org.ID,
	)
	if isUniqueViolation(err) {
		return domain.ErrOrgSlugTaken
	}
	if err != nil {
		return fmt.Errorf("update organisation: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrOrgNotFound
	}
	return nil
}

// Delete removes an organisation and its employee list. Accounts still pointing at it
// make the delete fail, which is reported as OrgInUseError.
func (r *OrgRepo) Delete(ctx context.Context, id string) error {
	tag, err := r.db.Exec(ctx, `DELETE FROM organisations WHERE id = $1`, id)
	if isForeignKeyViolation(err) {
		return &domain.OrgInUseError{}
	}
	if err != nil {
		return fmt.Errorf("delete organisation: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrOrgNotFound
	}
	return nil
}

func isForeignKeyViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23503"
}

func (r *OrgRepo) MemberCounts(ctx context.Context) (map[string]int, error) {
	rows, err := r.db.Query(ctx,
		`SELECT organisation_id::text, count(*) FROM users WHERE organisation_id IS NOT NULL GROUP BY organisation_id`)
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

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

func (r *OrgRepo) GetByID(ctx context.Context, id string) (*domain.Organisation, error) {
	row := r.db.QueryRow(ctx,
		`SELECT id, name, slug, verify_method, verify_config, created_at, updated_at
		 FROM organisations WHERE id = $1`, id)
	return scanOrg(row)
}

func (r *OrgRepo) GetBySlug(ctx context.Context, slug string) (*domain.Organisation, error) {
	row := r.db.QueryRow(ctx,
		`SELECT id, name, slug, verify_method, verify_config, created_at, updated_at
		 FROM organisations WHERE slug = $1`, slug)
	return scanOrg(row)
}

func (r *OrgRepo) List(ctx context.Context) ([]*domain.Organisation, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, name, slug, verify_method, verify_config, created_at, updated_at FROM organisations ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orgs []*domain.Organisation
	for rows.Next() {
		org, err := scanOrgRows(rows)
		if err != nil {
			return nil, err
		}
		orgs = append(orgs, org)
	}
	return orgs, nil
}

func scanOrg(row pgx.Row) (*domain.Organisation, error) {
	var o domain.Organisation
	var configJSON []byte
	err := row.Scan(&o.ID, &o.Name, &o.Slug, &o.VerifyMethod, &configJSON, &o.CreatedAt, &o.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("scan organisation: %w", err)
	}
	json.Unmarshal(configJSON, &o.VerifyConfig)
	return &o, nil
}

func scanOrgRows(rows pgx.Rows) (*domain.Organisation, error) {
	var o domain.Organisation
	var configJSON []byte
	err := rows.Scan(&o.ID, &o.Name, &o.Slug, &o.VerifyMethod, &configJSON, &o.CreatedAt, &o.UpdatedAt)
	if err != nil {
		return nil, err
	}
	json.Unmarshal(configJSON, &o.VerifyConfig)
	return &o, nil
}
