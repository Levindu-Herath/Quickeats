package app

import (
	"context"
	"fmt"
	"strings"

	"github.com/quickeats/services/identity/internal/domain"
	"github.com/quickeats/services/identity/internal/port"
	"golang.org/x/crypto/bcrypt"
)

// OrgSummary is the public view of an organisation.
type OrgSummary struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Slug         string   `json:"slug"`
	EmailDomains []string `json:"emailDomains"`
}

func summarize(o *domain.Organisation) OrgSummary {
	return OrgSummary{ID: o.ID, Name: o.Name, Slug: o.Slug, EmailDomains: o.EmailDomains()}
}

// Profile is what the settings screens show.
type Profile struct {
	ID           string      `json:"id"`
	Email        string      `json:"email"`
	DisplayName  string      `json:"displayName"`
	Role         string      `json:"role"`
	ShopID       *string     `json:"shopId,omitempty"`
	Organisation *OrgSummary `json:"organisation,omitempty"`
	// Organisations a merchant's shop serves (shop accounts only).
	ShopOrganisations []OrgSummary `json:"shopOrganisations,omitempty"`
}

type ProfileUseCase struct {
	userRepo port.UserRepository
	orgRepo  port.OrganisationRepository
	shops    port.ShopDirectory
}

func NewProfileUseCase(userRepo port.UserRepository, orgRepo port.OrganisationRepository, shops port.ShopDirectory) *ProfileUseCase {
	return &ProfileUseCase{userRepo: userRepo, orgRepo: orgRepo, shops: shops}
}

func (uc *ProfileUseCase) Get(ctx context.Context, userID string) (*Profile, error) {
	user, err := uc.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, domain.ErrInvalidCredentials
	}

	p := &Profile{ID: user.ID, Email: user.Email, DisplayName: user.DisplayName, Role: string(user.Role), ShopID: user.ShopID}
	if user.OrganisationID != "" {
		if org, err := uc.orgRepo.GetByID(ctx, user.OrganisationID); err == nil && org != nil {
			s := summarize(org)
			p.Organisation = &s
		}
	}
	if user.ShopID != nil {
		ids, err := uc.shops.ShopOrganisations(ctx, *user.ShopID)
		if err != nil {
			return nil, fmt.Errorf("load shop organisations: %w", err)
		}
		p.ShopOrganisations = []OrgSummary{}
		for _, id := range ids {
			if org, err := uc.orgRepo.GetByID(ctx, id); err == nil && org != nil {
				p.ShopOrganisations = append(p.ShopOrganisations, summarize(org))
			}
		}
	}
	return p, nil
}

func (uc *ProfileUseCase) UpdateDisplayName(ctx context.Context, userID, displayName string) (*Profile, error) {
	name := strings.TrimSpace(displayName)
	if name == "" || len(name) > 100 {
		return nil, fmt.Errorf("%w: display name must be 1-100 characters", domain.ErrInvalidProfile)
	}
	if err := uc.userRepo.UpdateDisplayName(ctx, userID, name); err != nil {
		return nil, err
	}
	return uc.Get(ctx, userID)
}

func (uc *ProfileUseCase) ChangePassword(ctx context.Context, userID, current, next string) error {
	user, err := uc.userRepo.GetByID(ctx, userID)
	if err != nil || user == nil {
		return domain.ErrInvalidCredentials
	}
	if bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(current)) != nil {
		return domain.ErrWrongPassword
	}
	if err := domain.ValidatePassword(next, user.Email, user.DisplayName); err != nil {
		return err
	}
	if next == current {
		return &domain.WeakPasswordError{Reason: "new password must be different from the current one"}
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(next), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash password: %w", err)
	}
	return uc.userRepo.UpdatePasswordHash(ctx, userID, string(hash))
}

// SetShopOrganisations replaces the organisation codes a merchant's shop serves.
func (uc *ProfileUseCase) SetShopOrganisations(ctx context.Context, userID string, slugs []string) (*Profile, error) {
	user, err := uc.userRepo.GetByID(ctx, userID)
	if err != nil || user == nil {
		return nil, domain.ErrInvalidCredentials
	}
	if user.ShopID == nil {
		return nil, domain.ErrNoShop
	}

	orgs, err := resolveOrgs(ctx, uc.orgRepo, slugs)
	if err != nil {
		return nil, err
	}
	if err := uc.shops.SetShopOrganisations(ctx, *user.ShopID, orgIDs(orgs)); err != nil {
		return nil, fmt.Errorf("update shop organisations: %w", err)
	}
	// Keep the merchant's own organisation one their shop still serves.
	if !containsID(orgs, user.OrganisationID) {
		if err := uc.userRepo.UpdateOrganisation(ctx, userID, orgs[0].ID); err != nil {
			return nil, err
		}
	}
	return uc.Get(ctx, userID)
}

func containsID(orgs []*domain.Organisation, id string) bool {
	for _, o := range orgs {
		if o.ID == id {
			return true
		}
	}
	return false
}
