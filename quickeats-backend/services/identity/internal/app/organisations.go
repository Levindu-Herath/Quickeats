package app

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"github.com/google/uuid"
	"github.com/quickeats/services/identity/internal/domain"
	"github.com/quickeats/services/identity/internal/port"
	"golang.org/x/crypto/bcrypt"
)

// OrgInput is what an admin submits to create or edit an organisation.
type OrgInput struct {
	Name         string
	Slug         string
	EmailDomains []string
}

// AdminOrg is an organisation as listed on the admin dashboard.
type AdminOrg struct {
	OrgSummary
	MemberCount int `json:"memberCount"`
	// EmployeeCount is the size of the employee list; 0 means customers are checked by domain only.
	EmployeeCount int    `json:"employeeCount"`
	CreatedAt     string `json:"createdAt"`
}

type OrganisationsUseCase struct {
	orgRepo   port.OrganisationRepository
	employees port.EmployeeListRepository
}

func NewOrganisationsUseCase(orgRepo port.OrganisationRepository, employees port.EmployeeListRepository) *OrganisationsUseCase {
	return &OrganisationsUseCase{orgRepo: orgRepo, employees: employees}
}

func validateOrgInput(in OrgInput) (OrgInput, error) {
	name := strings.TrimSpace(in.Name)
	if name == "" || len(name) > 255 {
		return in, fmt.Errorf("%w: name is required", domain.ErrInvalidOrganisation)
	}
	slug, err := domain.NormalizeSlug(in.Slug)
	if err != nil {
		return in, fmt.Errorf("%w: %s", domain.ErrInvalidOrganisation, err.Error())
	}
	domains, err := domain.NormalizeDomains(in.EmailDomains)
	if err != nil {
		return in, fmt.Errorf("%w: %s", domain.ErrInvalidOrganisation, err.Error())
	}
	return OrgInput{Name: name, Slug: slug, EmailDomains: domains}, nil
}

func (uc *OrganisationsUseCase) Create(ctx context.Context, in OrgInput) (*OrgSummary, error) {
	in, err := validateOrgInput(in)
	if err != nil {
		return nil, err
	}
	org := domain.NewEmailDomainOrganisation(in.Name, in.Slug, in.EmailDomains)
	if err := uc.orgRepo.Create(ctx, org); err != nil {
		return nil, err
	}
	s := summarize(org)
	return &s, nil
}

func (uc *OrganisationsUseCase) Update(ctx context.Context, id string, in OrgInput) (*OrgSummary, error) {
	in, err := validateOrgInput(in)
	if err != nil {
		return nil, err
	}
	org, err := uc.orgRepo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if org == nil {
		return nil, domain.ErrOrgNotFound
	}
	// Existing members keep their accounts; the new domains apply to future sign-ups.
	org.Name, org.Slug = in.Name, in.Slug
	org.VerifyMethod = domain.VerifyEmailDomain
	org.VerifyConfig = map[string]interface{}{"domains": in.EmailDomains}
	if err := uc.orgRepo.Update(ctx, org); err != nil {
		return nil, err
	}
	s := summarize(org)
	return &s, nil
}

func (uc *OrganisationsUseCase) List(ctx context.Context) ([]AdminOrg, error) {
	orgs, err := uc.orgRepo.List(ctx)
	if err != nil {
		return nil, err
	}
	counts, err := uc.orgRepo.MemberCounts(ctx)
	if err != nil {
		return nil, err
	}
	listed, err := uc.employees.Counts(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]AdminOrg, 0, len(orgs))
	for _, o := range orgs {
		out = append(out, AdminOrg{
			OrgSummary:    summarize(o),
			MemberCount:   counts[o.ID],
			EmployeeCount: listed[o.ID],
			CreatedAt:     o.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		})
	}
	return out, nil
}

// Delete removes an organisation that nobody has registered with yet; its employee
// list goes with it. Shops that also serve it simply stop listing it.
func (uc *OrganisationsUseCase) Delete(ctx context.Context, id string) error {
	if _, err := uuid.Parse(id); err != nil {
		return domain.ErrOrgNotFound
	}
	counts, err := uc.orgRepo.MemberCounts(ctx)
	if err != nil {
		return err
	}
	if n := counts[id]; n > 0 {
		return &domain.OrgInUseError{Accounts: n}
	}
	return uc.orgRepo.Delete(ctx, id)
}

// Lookup is the public check the apps use while a user types an organisation code.
func (uc *OrganisationsUseCase) Lookup(ctx context.Context, slug string) (*OrgSummary, error) {
	org, err := findOrg(ctx, uc.orgRepo, slug)
	if err != nil {
		return nil, err
	}
	s := summarize(org)
	return &s, nil
}

// EnsureAdmin creates the platform admin account on start-up if it does not exist yet.
// Credentials come from the environment, so no default admin password ships in the repo.
func EnsureAdmin(ctx context.Context, userRepo port.UserRepository, email, password string) error {
	email = strings.TrimSpace(email)
	if email == "" || password == "" {
		slog.Warn("ADMIN_EMAIL/ADMIN_PASSWORD not set; no admin account created")
		return nil
	}
	existing, err := userRepo.GetByEmail(ctx, email)
	if err != nil {
		return err
	}
	if existing != nil {
		if existing.Role != domain.RoleAdmin {
			slog.Warn("ADMIN_EMAIL belongs to a non-admin account; not changing it", "email", email)
		}
		return nil
	}
	if err := domain.ValidatePassword(password, email, "Administrator"); err != nil {
		return fmt.Errorf("ADMIN_PASSWORD is too weak: %w", err)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	admin := domain.NewUser("", email, string(hash), "Administrator", domain.RoleAdmin)
	admin.Verified = true
	if err := userRepo.Create(ctx, admin); err != nil {
		return err
	}
	slog.Info("admin account created", "email", email)
	return nil
}
