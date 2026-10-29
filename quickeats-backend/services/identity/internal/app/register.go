package app

import (
	"context"
	"fmt"
	"strings"

	"github.com/quickeats/services/identity/internal/domain"
	"github.com/quickeats/services/identity/internal/port"
	"golang.org/x/crypto/bcrypt"
)

type RegisterRequest struct {
	OrganisationSlug string `json:"organisationSlug"`
	Email            string `json:"email"`
	Password         string `json:"password"`
	DisplayName      string `json:"displayName"`
	InviteCode       string `json:"inviteCode,omitempty"`
}

type RegisterUseCase struct {
	userRepo port.UserRepository
	orgRepo  port.OrganisationRepository
}

func NewRegisterUseCase(userRepo port.UserRepository, orgRepo port.OrganisationRepository) *RegisterUseCase {
	return &RegisterUseCase{userRepo: userRepo, orgRepo: orgRepo}
}

// Execute signs up a customer. The organisation code must exist and the email must be
// on one of the organisation's email domains, which is what ties a customer to it.
func (uc *RegisterUseCase) Execute(ctx context.Context, req RegisterRequest) (*domain.User, error) {
	org, err := findOrg(ctx, uc.orgRepo, req.OrganisationSlug)
	if err != nil {
		return nil, err
	}
	if err := verifyMember(org, req); err != nil {
		return nil, err
	}

	user, err := newAccount(ctx, uc.userRepo, req.Email, req.Password, req.DisplayName, org.ID, domain.RoleCustomer)
	if err != nil {
		return nil, err
	}
	if err := uc.userRepo.Create(ctx, user); err != nil {
		return nil, err
	}
	return user, nil
}

// findOrg looks up an organisation by its code, case-insensitively.
func findOrg(ctx context.Context, orgRepo port.OrganisationRepository, slug string) (*domain.Organisation, error) {
	s := strings.ToLower(strings.TrimSpace(slug))
	org, err := orgRepo.GetBySlug(ctx, s)
	if err != nil {
		return nil, err
	}
	if org == nil {
		return nil, &domain.UnknownOrgError{Slug: s}
	}
	return org, nil
}

// verifyMember checks a customer is eligible for the organisation.
func verifyMember(org *domain.Organisation, req RegisterRequest) error {
	if _, err := domain.EmailDomain(req.Email); err != nil {
		return domain.ErrInvalidEmail
	}

	if org.VerifyMethod == domain.VerifyInviteCode {
		codes, _ := org.VerifyConfig["codes"].([]interface{})
		for _, c := range codes {
			if c == req.InviteCode {
				return nil
			}
		}
		return domain.ErrVerificationFailed
	}

	verifier, err := domain.ResolveVerifier(org.VerifyMethod)
	if err != nil {
		return fmt.Errorf("resolve verifier: %w", err)
	}
	if err := verifier.Verify(req.Email, org.VerifyConfig); err != nil {
		return &domain.EmailNotAllowedError{OrgName: org.Name, Domains: org.EmailDomains()}
	}
	return nil
}

// newAccount runs the checks every sign-up shares (valid unused email, strong
// password) and builds the user with a hashed password.
func newAccount(ctx context.Context, userRepo port.UserRepository, email, password, displayName, orgID string, role domain.Role) (*domain.User, error) {
	email = strings.TrimSpace(email)
	if _, err := domain.EmailDomain(email); err != nil {
		return nil, domain.ErrInvalidEmail
	}
	if err := domain.ValidatePassword(password, email, displayName); err != nil {
		return nil, err
	}

	exists, err := userRepo.ExistsByEmail(ctx, email)
	if err != nil {
		return nil, err
	}
	if exists {
		return nil, domain.ErrUserAlreadyExists
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash password: %w", err)
	}

	user := domain.NewUser(orgID, email, string(hash), strings.TrimSpace(displayName), role)
	user.Verified = true // eligibility was checked by the caller
	return user, nil
}
