-- Optional employee list per organisation. When an organisation has entries here,
-- customers must sign up with one of these emails (which are also on its domains).
-- Emails are stored lower-case.
CREATE TABLE organisation_employee_emails (
    organisation_id UUID NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
    email           VARCHAR(255) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (organisation_id, email)
);
