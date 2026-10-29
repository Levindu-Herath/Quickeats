package domain

import (
	"errors"
	"fmt"
	"strings"
)

var (
	ErrUserAlreadyExists   = errors.New("user with this email already exists")
	ErrInvalidCredentials  = errors.New("invalid email or password")
	ErrOrgNotFound         = errors.New("organisation not found")
	ErrOrgSlugTaken        = errors.New("organisation code is already in use")
	ErrVerificationFailed  = errors.New("organisation verification failed")
	ErrInvalidEmail        = errors.New("invalid email address")
	ErrWeakPassword        = errors.New("password is too weak")
	ErrWrongPassword       = errors.New("current password is incorrect")
	ErrNoShop              = errors.New("this account has no shop")
	ErrNoOrganisations     = errors.New("add at least one organisation code")
	ErrInvalidOrganisation = errors.New("invalid organisation")
	ErrInvalidProfile      = errors.New("invalid profile")
	ErrNoValidEmails       = errors.New("no valid emails to import")
	ErrTooManyEmails       = errors.New("too many emails in one import")
	ErrEmployeeNotFound    = errors.New("email is not on the employee list")
)

// NotOnEmployeeListError rejects a customer whose email is on the right domain but
// missing from the organisation's employee list.
type NotOnEmployeeListError struct{ OrgName string }

func (e *NotOnEmployeeListError) Error() string {
	return "this email is not on " + e.OrgName + "'s employee list. Ask your organisation to add it"
}

// OrgInUseError stops an organisation with accounts from being deleted.
type OrgInUseError struct{ Accounts int }

func (e *OrgInUseError) Error() string {
	if e.Accounts == 0 {
		return "this organisation still has accounts, so it can't be deleted"
	}
	if e.Accounts == 1 {
		return "this organisation has 1 account, so it can't be deleted"
	}
	return fmt.Sprintf("this organisation has %d accounts, so it can't be deleted", e.Accounts)
}

// EmailNotAllowedError says which email domains the organisation accepts.
type EmailNotAllowedError struct {
	OrgName string
	Domains []string
}

func (e *EmailNotAllowedError) Error() string {
	return e.OrgName + " only accepts emails ending in @" + strings.Join(e.Domains, ", @")
}

// UnknownOrgError names the organisation code that does not exist.
type UnknownOrgError struct{ Slug string }

func (e *UnknownOrgError) Error() string {
	return "organisation code \"" + e.Slug + "\" does not exist"
}
