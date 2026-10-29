package domain

import (
	"reflect"
	"testing"
)

func TestNormalizeEmployeeEmails(t *testing.T) {
	domains := []string{"eng.ruh.ac.lk", "*.cmb.ac.lk"}
	raw := []string{
		"Levindu@ENG.ruh.ac.lk", // lower-cased
		" kamal@eng.ruh.ac.lk ", // trimmed
		"levindu@eng.ruh.ac.lk", // duplicate after normalising
		"nimal@sci.cmb.ac.lk",   // wildcard domain
		"someone@gmail.com",     // wrong domain
		"student@ruh.ac.lk",     // parent of the allowed domain
		"not-an-email",          // invalid
		"",                      // blank lines are skipped
	}

	valid, rejected := NormalizeEmployeeEmails(raw, domains)

	wantValid := []string{"levindu@eng.ruh.ac.lk", "kamal@eng.ruh.ac.lk", "nimal@sci.cmb.ac.lk"}
	if !reflect.DeepEqual(valid, wantValid) {
		t.Errorf("valid = %v, want %v", valid, wantValid)
	}
	wantRejected := []string{"someone@gmail.com", "student@ruh.ac.lk", "not-an-email"}
	if len(rejected) != len(wantRejected) {
		t.Fatalf("rejected = %v, want values %v", rejected, wantRejected)
	}
	for i, r := range rejected {
		if r.Value != wantRejected[i] || r.Reason == "" {
			t.Errorf("rejected[%d] = %+v, want value %q with a reason", i, r, wantRejected[i])
		}
	}
}
