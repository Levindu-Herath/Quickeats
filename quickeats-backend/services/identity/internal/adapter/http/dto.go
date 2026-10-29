package http

type RegisterRequest struct {
	OrganisationSlug string `json:"organisationSlug"`
	Email            string `json:"email"`
	Password         string `json:"password"`
	DisplayName      string `json:"displayName"`
	InviteCode       string `json:"inviteCode,omitempty"`
}

// RegisterShopRequest signs up a merchant. organisationSlugs lists every organisation
// the shop serves; the older single organisationSlug is still accepted.
type RegisterShopRequest struct {
	OrganisationSlug  string   `json:"organisationSlug,omitempty"`
	OrganisationSlugs []string `json:"organisationSlugs,omitempty"`
	Email             string   `json:"email"`
	Password          string   `json:"password"`
	DisplayName       string   `json:"displayName"`
	InviteCode        string   `json:"inviteCode,omitempty"`
	ShopName          string   `json:"shopName"`
	ShopDescription   string   `json:"shopDescription"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refreshToken"`
}

// OrgRequest creates or edits an organisation from the admin dashboard.
type OrgRequest struct {
	Name         string   `json:"name"`
	Slug         string   `json:"slug"`
	EmailDomains []string `json:"emailDomains"`
}

// ImportEmployeesRequest uploads an organisation's employee emails. Mode "add" keeps
// the current list; "replace" makes the list exactly these emails.
type ImportEmployeesRequest struct {
	Emails []string `json:"emails"`
	Mode   string   `json:"mode"`
}

type UpdateProfileRequest struct {
	DisplayName string `json:"displayName"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"currentPassword"`
	NewPassword     string `json:"newPassword"`
}

type ShopOrganisationsRequest struct {
	OrganisationSlugs []string `json:"organisationSlugs"`
}
