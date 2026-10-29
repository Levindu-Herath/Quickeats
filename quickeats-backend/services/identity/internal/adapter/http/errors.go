package http

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/quickeats/pkg/httputil"
	"github.com/quickeats/services/identity/internal/domain"
)

// respondError maps domain errors to the API error envelope with messages the apps
// can show to users as-is.
func respondError(w http.ResponseWriter, err error) {
	var notAllowed *domain.EmailNotAllowedError
	var unknownOrg *domain.UnknownOrgError
	var notListed *domain.NotOnEmployeeListError
	var inUse *domain.OrgInUseError

	switch {
	case errors.As(err, &notAllowed):
		httputil.RespondError(w, &httputil.AppError{
			Code: "EMAIL_NOT_ALLOWED", Message: notAllowed.Error(), Status: http.StatusUnprocessableEntity,
			Details: map[string]interface{}{"emailDomains": notAllowed.Domains},
		})
	case errors.As(err, &notListed):
		httputil.RespondError(w, &httputil.AppError{
			Code: "EMAIL_NOT_ON_EMPLOYEE_LIST", Message: notListed.Error(), Status: http.StatusUnprocessableEntity,
		})
	case errors.As(err, &inUse):
		httputil.RespondError(w, httputil.ErrConflict(inUse.Error()))
	case errors.Is(err, domain.ErrEmployeeNotFound):
		httputil.RespondError(w, httputil.ErrNotFound("employee email"))
	case errors.Is(err, domain.ErrTooManyEmails):
		httputil.RespondError(w, httputil.ErrValidation(fmt.Sprintf("import at most %d emails at a time", domain.MaxEmployeeImport), nil))
	case errors.As(err, &unknownOrg):
		httputil.RespondError(w, &httputil.AppError{Code: "ORGANISATION_NOT_FOUND", Message: unknownOrg.Error(), Status: http.StatusNotFound})
	case errors.Is(err, domain.ErrOrgNotFound):
		httputil.RespondError(w, httputil.ErrNotFound("organisation"))
	case errors.Is(err, domain.ErrUserAlreadyExists):
		httputil.RespondError(w, httputil.ErrConflict("an account with this email already exists"))
	case errors.Is(err, domain.ErrOrgSlugTaken):
		httputil.RespondError(w, httputil.ErrConflict(err.Error()))
	case errors.Is(err, domain.ErrVerificationFailed):
		httputil.RespondError(w, httputil.ErrBusinessRule("VERIFICATION_FAILED", "this email is not allowed for the organisation"))
	case errors.Is(err, domain.ErrWrongPassword):
		httputil.RespondError(w, httputil.ErrBusinessRule("WRONG_PASSWORD", err.Error()))
	case errors.Is(err, domain.ErrNoShop):
		httputil.RespondError(w, httputil.ErrForbidden(err.Error()))
	case errors.Is(err, domain.ErrInvalidCredentials):
		httputil.RespondError(w, httputil.ErrUnauthenticated(err.Error()))
	case errors.Is(err, domain.ErrInvalidEmail), errors.Is(err, domain.ErrWeakPassword), errors.Is(err, domain.ErrNoOrganisations):
		httputil.RespondError(w, httputil.ErrValidation(err.Error(), nil))
	case errors.Is(err, domain.ErrInvalidOrganisation):
		httputil.RespondError(w, httputil.ErrValidation(detail(err, domain.ErrInvalidOrganisation), nil))
	case errors.Is(err, domain.ErrInvalidProfile):
		httputil.RespondError(w, httputil.ErrValidation(detail(err, domain.ErrInvalidProfile), nil))
	default:
		httputil.RespondError(w, err)
	}
}

// detail strips the sentinel prefix from a wrapped error: "invalid organisation: name is required" -> "name is required".
func detail(err, sentinel error) string {
	return strings.TrimPrefix(err.Error(), sentinel.Error()+": ")
}
