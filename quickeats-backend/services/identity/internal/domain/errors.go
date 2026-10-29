package domain

import (
	"errors"
	"strings"
)

var (
	ErrUserAlreadyExists  = errors.New("user with this email already exists")
	ErrInvalidCredentials = errors.New("invalid email or password")
	ErrOrgNotFound        = errors.New("organisation not found")
	ErrOrgSlugTaken       = errors.New("organisation code is already in use")
	ErrVerificationFailed = errors.New("organisation verification failed")
	ErrInvalidEmail       = errors.New("invalid email address")
	ErrWeakPassword       = errors.New("password is too weak")
	ErrWrongPassword      = errors.New("current password is incorrect")
	ErrNoShop             = errors.New("this account has no shop")
	ErrNoOrganisations    = errors.New("add at least one organisation code")
	ErrInvalidOrganisation = errors.New("invalid organisation")
	ErrInvalidProfile      = errors.New("invalid profile")
)

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
