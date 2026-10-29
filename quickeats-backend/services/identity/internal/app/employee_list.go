package app

import (
	"context"

	"github.com/google/uuid"
	"github.com/quickeats/services/identity/internal/domain"
	"github.com/quickeats/services/identity/internal/port"
)

// ImportResult tells the admin what an employee list import changed.
type ImportResult struct {
	Added    int                    `json:"added"`
	Removed  int                    `json:"removed"`
	Total    int                    `json:"total"`
	Rejected []domain.RejectedEmail `json:"rejected"`
}

// EmployeeListUseCase manages the employee emails an organisation lets sign up.
type EmployeeListUseCase struct {
	orgRepo   port.OrganisationRepository
	employees port.EmployeeListRepository
}

func NewEmployeeListUseCase(orgRepo port.OrganisationRepository, employees port.EmployeeListRepository) *EmployeeListUseCase {
	return &EmployeeListUseCase{orgRepo: orgRepo, employees: employees}
}

func (uc *EmployeeListUseCase) List(ctx context.Context, orgID string) ([]domain.EmployeeEmail, error) {
	if _, err := uc.org(ctx, orgID); err != nil {
		return nil, err
	}
	return uc.employees.List(ctx, orgID)
}

// Import adds emails to the list, or with replace makes the list exactly the valid
// emails given. Emails off the organisation's domains are rejected and reported back.
func (uc *EmployeeListUseCase) Import(ctx context.Context, orgID string, emails []string, replace bool) (*ImportResult, error) {
	if len(emails) > domain.MaxEmployeeImport {
		return nil, domain.ErrTooManyEmails
	}
	org, err := uc.org(ctx, orgID)
	if err != nil {
		return nil, err
	}

	valid, rejected := domain.NormalizeEmployeeEmails(emails, org.EmailDomains())
	if len(valid) == 0 {
		// Never let a bad file wipe or no-op the list silently.
		return &ImportResult{Rejected: rejected}, domain.ErrNoValidEmails
	}

	res := &ImportResult{Rejected: rejected}
	if replace {
		res.Added, res.Removed, err = uc.employees.Replace(ctx, orgID, valid)
	} else {
		res.Added, err = uc.employees.Add(ctx, orgID, valid)
	}
	if err != nil {
		return nil, err
	}
	counts, err := uc.employees.Counts(ctx)
	if err != nil {
		return nil, err
	}
	res.Total = counts[orgID]
	return res, nil
}

func (uc *EmployeeListUseCase) Remove(ctx context.Context, orgID, email string) error {
	if _, err := uc.org(ctx, orgID); err != nil {
		return err
	}
	removed, err := uc.employees.Remove(ctx, orgID, domain.NormalizeEmail(email))
	if err != nil {
		return err
	}
	if !removed {
		return domain.ErrEmployeeNotFound
	}
	return nil
}

// Clear empties the list; the organisation then accepts any email on its domains again.
func (uc *EmployeeListUseCase) Clear(ctx context.Context, orgID string) (int, error) {
	if _, err := uc.org(ctx, orgID); err != nil {
		return 0, err
	}
	return uc.employees.Clear(ctx, orgID)
}

func (uc *EmployeeListUseCase) org(ctx context.Context, id string) (*domain.Organisation, error) {
	if _, err := uuid.Parse(id); err != nil {
		return nil, domain.ErrOrgNotFound
	}
	org, err := uc.orgRepo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if org == nil {
		return nil, domain.ErrOrgNotFound
	}
	return org, nil
}

// checkEmployeeList enforces the organisation's employee list, if it keeps one.
func checkEmployeeList(ctx context.Context, employees port.EmployeeListRepository, org *domain.Organisation, email string) error {
	hasList, listed, err := employees.Check(ctx, org.ID, domain.NormalizeEmail(email))
	if err != nil {
		return err
	}
	if hasList && !listed {
		return &domain.NotOnEmployeeListError{OrgName: org.Name}
	}
	return nil
}
