package domain

import (
	"errors"
	"strings"
	"testing"
)

func TestValidatePasswordAccepts(t *testing.T) {
	for _, pw := range []string{
		"Canteen#Dev2026",
		"Kottu&Tea49",
		"Mango juice 4 me!",        // spaces inside are fine
		"Ünïcode-Pässwörd7",        // non-ASCII letters count
		strings.Repeat("Ab1!", 18), // exactly 72 bytes
	} {
		if err := ValidatePassword(pw, "nimal.perera@ruh.ac.lk", "Nimal Perera"); err != nil {
			t.Errorf("ValidatePassword(%q) = %v, want ok", pw, err)
		}
	}
}

func TestValidatePasswordRejects(t *testing.T) {
	for _, tc := range []struct{ pw, want string }{
		{"Ab1!xyz", "at least 8"},
		{strings.Repeat("Ab1!", 18) + "x", "at most 72"},
		{" Kottu&Tea49", "start or end with a space"},
		{"kottu&tea49", "uppercase"},
		{"KOTTU&TEA49", "lowercase"},
		{"Kottu&Teaxy", "number"},
		{"KottuTea4913", "symbol"},
		{"Kottu&Teaaa49", "repeated or 4 sequential"},
		{"Kottu&Tea1234", "repeated or 4 sequential"},
		{"Kottu&Tea9876", "repeated or 4 sequential"},
		{"Password1!", "too common"},
		{"P@ssw0rd!!9", "too common"},
		{"Qwerty@2024", "too common"},
		{"Welcome@123x", "too common"},
		{"Dr@g0n!x9", "too common"},
		{"Nimal.Perera#5", "email"},
		{"Perera#Rocks5", "name"},
	} {
		err := ValidatePassword(tc.pw, "nimal.perera@ruh.ac.lk", "Nimal Perera")
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("ValidatePassword(%q) = %v, want error containing %q", tc.pw, err, tc.want)
			continue
		}
		if !errors.Is(err, ErrWeakPassword) {
			t.Errorf("ValidatePassword(%q): errors.Is(err, ErrWeakPassword) = false", tc.pw)
		}
	}
}

func TestValidatePasswordShortNamesAreIgnored(t *testing.T) {
	// A two-letter name part or email would block too many passwords to be useful.
	if err := ValidatePassword("Kottu&Tea49", "te@x.lk", "Al Te"); err != nil {
		t.Errorf("got %v, want ok", err)
	}
}
