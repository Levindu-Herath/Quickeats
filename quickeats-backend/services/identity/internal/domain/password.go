package domain

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

const (
	MinPasswordLength = 8
	// bcrypt only uses the first 72 bytes, so longer passwords would be silently cut.
	MaxPasswordBytes = 72
)

// WeakPasswordError says which password rule failed. errors.Is(err, ErrWeakPassword) holds.
type WeakPasswordError struct{ Reason string }

func (e *WeakPasswordError) Error() string        { return e.Reason }
func (e *WeakPasswordError) Is(target error) bool { return target == ErrWeakPassword }

// commonPasswordWords are the letters of passwords attackers try first. A password
// built from one of these ("Password1!", "P@ssw0rd!9", "Qwerty@2024") is refused
// even though it has every kind of character.
var commonPasswordWords = map[string]bool{
	"password": true, "passw": true, "pass": true, "qwerty": true, "qwertyuiop": true, "asdf": true,
	"asdfgh": true, "zxcvbn": true, "letmein": true, "welcome": true, "admin": true, "administrator": true,
	"iloveyou": true, "monkey": true, "dragon": true, "football": true, "sunshine": true, "princess": true,
	"login": true, "master": true, "hello": true, "freedom": true, "whatever": true, "trustno": true,
	"abc": true, "abcd": true, "test": true, "user": true, "secret": true, "changeme": true,
	"quickeats": true, "food": true, "canteen": true,
}

// ValidatePassword checks a new password against the password policy. email and
// displayName are the account's own, which the password must not contain.
func ValidatePassword(password, email, displayName string) error {
	weak := func(reason string) error { return &WeakPasswordError{Reason: reason} }

	if utf8.RuneCountInString(password) < MinPasswordLength {
		return weak("password must be at least 8 characters")
	}
	if len(password) > MaxPasswordBytes {
		return weak("password must be at most 72 characters")
	}
	if strings.TrimSpace(password) != password {
		return weak("password can't start or end with a space")
	}

	var lower, upper, digit, symbol bool
	for _, r := range password {
		switch {
		case unicode.IsLower(r):
			lower = true
		case unicode.IsUpper(r):
			upper = true
		case unicode.IsDigit(r):
			digit = true
		case !unicode.IsSpace(r):
			symbol = true
		}
	}
	switch {
	case !upper:
		return weak("password needs an uppercase letter")
	case !lower:
		return weak("password needs a lowercase letter")
	case !digit:
		return weak("password needs a number")
	case !symbol:
		return weak("password needs a symbol, like ! @ # $")
	}

	if hasRun(password) {
		return weak("password can't have 3 repeated or 4 sequential characters, like aaa or 1234")
	}

	lowered := strings.ToLower(password)
	if isCommon(lowered) {
		return weak("password is too common")
	}

	local, _, _ := strings.Cut(strings.ToLower(strings.TrimSpace(email)), "@")
	if len(local) >= 3 && strings.Contains(lowered, local) {
		return weak("password can't contain your email address")
	}
	for _, part := range strings.Fields(strings.ToLower(displayName)) {
		if utf8.RuneCountInString(part) >= 3 && strings.Contains(lowered, part) {
			return weak("password can't contain your name")
		}
	}
	return nil
}

// leet undoes the usual letter swaps, so "p@ssw0rd" reads as "password".
var leet = strings.NewReplacer("@", "a", "4", "a", "0", "o", "1", "i", "!", "i", "3", "e", "$", "s", "5", "s", "7", "t")

// isCommon reports whether a lowercased password is a common word with a few
// characters added: its letters, read as is or with swaps undone, are one of
// commonPasswordWords, or contain a long one (5+ letters) plus at most two more.
func isCommon(lowered string) bool {
	for _, candidate := range []string{lettersOf(lowered), lettersOf(leet.Replace(lowered))} {
		if commonPasswordWords[candidate] {
			return true
		}
		for word := range commonPasswordWords {
			if len(word) >= 5 && strings.Contains(candidate, word) && len(candidate)-len(word) <= 2 {
				return true
			}
		}
	}
	return false
}

func lettersOf(s string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) {
			return r
		}
		return -1
	}, s)
}

// hasRun reports 3 identical characters in a row ("aaa") or 4 consecutive ones
// going up or down ("1234", "dcba"), ignoring case.
func hasRun(password string) bool {
	rs := []rune(strings.ToLower(password))
	same, up, down := 1, 1, 1
	for i := 1; i < len(rs); i++ {
		same, up, down = next(same, rs[i] == rs[i-1]), next(up, rs[i] == rs[i-1]+1), next(down, rs[i] == rs[i-1]-1)
		if same >= 3 || up >= 4 || down >= 4 {
			return true
		}
	}
	return false
}

func next(run int, continues bool) int {
	if continues {
		return run + 1
	}
	return 1
}
