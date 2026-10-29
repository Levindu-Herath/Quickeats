# QuickEats Admin Dashboard

React (Vite + TypeScript) app for platform admins to manage organisations:
the code users type when they register (e.g. `ruh-eng`) and the email domains
its customers must sign up with (e.g. `eng.ruh.ac.lk`, or `*.ruh.ac.lk` for every subdomain).

Merchants are not bound by these domains: they register with any email and pick
one or more organisation codes for their shop.

## Running it

It is served by Kong at **`/admin`**, next to the API:

- Local stack: `docker compose up -d` in `quickeats-backend`, then open http://localhost:8000/admin
- Production: `http://<server>/admin`

Sign in with the admin account the identity service creates on start-up from
`ADMIN_EMAIL` / `ADMIN_PASSWORD` (local defaults: `admin@quickeats.dev` / `Canteen#Dev2026`).

## Developing

```
npm install
npm run dev        # http://localhost:5173/admin/, proxies /api to http://localhost:8000
npm run build      # type-check + production build into dist/
```

Set `API_URL` to proxy to another gateway, e.g. `API_URL=http://13.63.249.122 npm run dev`.

## API used

| Method | Path | |
|---|---|---|
| POST | `/api/v1/auth/login` | admin role required |
| GET | `/api/v1/admin/organisations` | list with member counts |
| POST | `/api/v1/admin/organisations` | `{name, slug, emailDomains[]}` |
| PUT | `/api/v1/admin/organisations/{id}` | same body |
