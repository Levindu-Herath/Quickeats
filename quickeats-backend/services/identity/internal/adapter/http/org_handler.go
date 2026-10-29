package http

import (
	"errors"
	"net/http"
	"net/url"

	"github.com/go-chi/chi/v5"
	"github.com/quickeats/pkg/httputil"
	"github.com/quickeats/services/identity/internal/app"
	"github.com/quickeats/services/identity/internal/domain"
)

// OrgHandler serves organisation management for admins and the public code lookup.
type OrgHandler struct {
	orgsUC      *app.OrganisationsUseCase
	employeesUC *app.EmployeeListUseCase
}

func NewOrgHandler(orgsUC *app.OrganisationsUseCase, employeesUC *app.EmployeeListUseCase) *OrgHandler {
	return &OrgHandler{orgsUC: orgsUC, employeesUC: employeesUC}
}

func (h *OrgHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req OrgRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		httputil.RespondError(w, err)
		return
	}
	org, err := h.orgsUC.Create(r.Context(), app.OrgInput{Name: req.Name, Slug: req.Slug, EmailDomains: req.EmailDomains})
	if err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusCreated, org)
}

func (h *OrgHandler) Update(w http.ResponseWriter, r *http.Request) {
	var req OrgRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		httputil.RespondError(w, err)
		return
	}
	org, err := h.orgsUC.Update(r.Context(), chi.URLParam(r, "id"), app.OrgInput{Name: req.Name, Slug: req.Slug, EmailDomains: req.EmailDomains})
	if err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusOK, org)
}

func (h *OrgHandler) List(w http.ResponseWriter, r *http.Request) {
	orgs, err := h.orgsUC.List(r.Context())
	if err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusOK, orgs)
}

// Lookup lets the sign-up screens check a code and show which emails it accepts.
func (h *OrgHandler) Lookup(w http.ResponseWriter, r *http.Request) {
	org, err := h.orgsUC.Lookup(r.Context(), chi.URLParam(r, "slug"))
	if err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusOK, org)
}

func (h *OrgHandler) Delete(w http.ResponseWriter, r *http.Request) {
	if err := h.orgsUC.Delete(r.Context(), chi.URLParam(r, "id")); err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondNoContent(w)
}

func (h *OrgHandler) ListEmployees(w http.ResponseWriter, r *http.Request) {
	list, err := h.employeesUC.List(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusOK, list)
}

// ImportEmployees takes the emails the dashboard read from a CSV or text file.
func (h *OrgHandler) ImportEmployees(w http.ResponseWriter, r *http.Request) {
	var req ImportEmployeesRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		httputil.RespondError(w, err)
		return
	}
	if req.Mode != "add" && req.Mode != "replace" {
		httputil.RespondError(w, httputil.ErrValidation("mode must be \"add\" or \"replace\"", nil))
		return
	}
	res, err := h.employeesUC.Import(r.Context(), chi.URLParam(r, "id"), req.Emails, req.Mode == "replace")
	if errors.Is(err, domain.ErrNoValidEmails) {
		httputil.RespondError(w, httputil.ErrValidation(
			"none of these emails are on the organisation's domains", map[string]interface{}{"rejected": res.Rejected}))
		return
	}
	if err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusOK, res)
}

func (h *OrgHandler) RemoveEmployee(w http.ResponseWriter, r *http.Request) {
	// The email arrives percent-encoded ("%40"), and chi matches on the raw path.
	email, err := url.PathUnescape(chi.URLParam(r, "email"))
	if err != nil {
		httputil.RespondError(w, httputil.ErrValidation("invalid email", nil))
		return
	}
	if err := h.employeesUC.Remove(r.Context(), chi.URLParam(r, "id"), email); err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondNoContent(w)
}

func (h *OrgHandler) ClearEmployees(w http.ResponseWriter, r *http.Request) {
	removed, err := h.employeesUC.Clear(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		respondError(w, err)
		return
	}
	httputil.RespondJSON(w, http.StatusOK, map[string]int{"removed": removed})
}
