package domain

import (
	"strings"
	"time"
)

// MaxEmployeeImport caps how many emails one import may carry.
const MaxEmployeeImport = 10000

// EmployeeEmail is one entry on an organisation's employee list.
type EmployeeEmail struct {
	Email   string    `json:"email"`
	AddedAt time.Time `json:"addedAt"`
	// Registered is true once a customer account exists for this email in the organisation.
	Registered bool `json:"registered"`
}

// RejectedEmail is an imported value that cannot go on the employee list, and why.
type RejectedEmail struct {
	Value  string `json:"value"`
	Reason string `json:"reason"`
}

// NormalizeEmail is the form employee list emails are stored and compared in.
func NormalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

// NormalizeEmployeeEmails cleans an imported employee list: lower-cases each address,
// drops duplicates, and rejects anything that is not a valid email on one of the
// organisation's domains ("levindu@eng.ruh.ac.lk" for eng.ruh.ac.lk).
func NormalizeEmployeeEmails(raw []string, domains []string) ([]string, []RejectedEmail) {
	seen := map[string]bool{}
	valid := []string{}
	rejected := []RejectedEmail{}
	for _, r := range raw {
		email := NormalizeEmail(r)
		if email == "" || seen[email] {
			continue
		}
		seen[email] = true

		d, err := EmailDomain(email)
		if err != nil {
			rejected = append(rejected, RejectedEmail{Value: strings.TrimSpace(r), Reason: "not a valid email"})
			continue
		}
		if !matchesAnyDomain(d, domains) {
			rejected = append(rejected, RejectedEmail{
				Value: strings.TrimSpace(r), Reason: "not on @" + strings.Join(domains, ", @"),
			})
			continue
		}
		valid = append(valid, email)
	}
	return valid, rejected
}

func matchesAnyDomain(emailDomain string, patterns []string) bool {
	for _, p := range patterns {
		if DomainMatches(emailDomain, p) {
			return true
		}
	}
	return false
}
