// Thin client for the QuickEats API (same origin, routed by Kong).

export interface Organisation {
  id: string;
  name: string;
  slug: string;
  emailDomains: string[];
  memberCount?: number;
  /** Size of the employee list; 0 means customers are checked by domain only. */
  employeeCount?: number;
  createdAt?: string;
}

export interface EmployeeEmail {
  email: string;
  addedAt: string;
  /** A customer account exists for this email. */
  registered: boolean;
}

export interface RejectedEmail {
  value: string;
  reason: string;
}

export interface ImportResult {
  added: number;
  removed: number;
  total: number;
  rejected: RejectedEmail[];
}

export interface OrgInput {
  name: string;
  slug: string;
  emailDomains: string[];
}

interface Tokens {
  accessToken: string;
  refreshToken: string;
}

export class ApiError extends Error {
  constructor(message: string, public status: number, public details?: Record<string, unknown>) {
    super(message);
  }
}

const STORAGE_KEY = 'quickeats-admin-tokens';

function loadTokens(): Tokens | null {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Tokens) : null;
  } catch {
    return null;
  }
}

function saveTokens(tokens: Tokens | null) {
  try {
    if (tokens) sessionStorage.setItem(STORAGE_KEY, JSON.stringify(tokens));
    else sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    /* storage unavailable: the session just won't survive a reload */
  }
}

let tokens: Tokens | null = loadTokens();
let onSessionExpired: () => void = () => {};

export function setSessionExpiredHandler(handler: () => void) {
  onSessionExpired = handler;
}

/** Reads the role and email from the access token (the server re-checks on every call). */
export function currentSession(): { role: string; userId: string } | null {
  if (!tokens) return null;
  try {
    const payload = JSON.parse(atob(tokens.accessToken.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return { role: payload.role ?? '', userId: payload.sub ?? '' };
  } catch {
    return null;
  }
}

async function parse<T>(resp: Response): Promise<T> {
  if (resp.status === 204) return undefined as T;
  const body = await resp.json().catch(() => null);
  if (!resp.ok) {
    const message = body?.error?.message ?? `Request failed (${resp.status})`;
    throw new ApiError(message.charAt(0).toUpperCase() + message.slice(1), resp.status, body?.error?.details);
  }
  return body?.data as T;
}

async function refresh(): Promise<boolean> {
  if (!tokens) return false;
  const resp = await fetch('/api/v1/auth/refresh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken: tokens.refreshToken }),
  });
  if (!resp.ok) return false;
  tokens = await parse<Tokens>(resp);
  saveTokens(tokens);
  return true;
}

async function request<T>(method: string, path: string, body?: unknown, retry = true): Promise<T> {
  const resp = await fetch(path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(tokens ? { Authorization: `Bearer ${tokens.accessToken}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (resp.status === 401 && retry && (await refresh())) {
    return request<T>(method, path, body, false);
  }
  if (resp.status === 401) {
    logout();
    onSessionExpired();
  }
  return parse<T>(resp);
}

export async function login(email: string, password: string) {
  const resp = await fetch('/api/v1/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  tokens = await parse<Tokens>(resp);
  if (currentSession()?.role !== 'admin') {
    tokens = null;
    throw new ApiError('This account is not an administrator.', 403);
  }
  saveTokens(tokens);
}

export function logout() {
  tokens = null;
  saveTokens(null);
}

export const api = {
  listOrganisations: () => request<Organisation[]>('GET', '/api/v1/admin/organisations'),
  createOrganisation: (input: OrgInput) => request<Organisation>('POST', '/api/v1/admin/organisations', input),
  updateOrganisation: (id: string, input: OrgInput) =>
    request<Organisation>('PUT', orgPath(id), input),
  deleteOrganisation: (id: string) => request<void>('DELETE', orgPath(id)),

  listEmployees: (orgId: string) => request<EmployeeEmail[]>('GET', `${orgPath(orgId)}/employees`),
  importEmployees: (orgId: string, emails: string[], mode: 'add' | 'replace') =>
    request<ImportResult>('POST', `${orgPath(orgId)}/employees`, { emails, mode }),
  removeEmployee: (orgId: string, email: string) =>
    request<void>('DELETE', `${orgPath(orgId)}/employees/${encodeURIComponent(email)}`),
  clearEmployees: (orgId: string) => request<{ removed: number }>('DELETE', `${orgPath(orgId)}/employees`),
};

function orgPath(id: string) {
  return `/api/v1/admin/organisations/${encodeURIComponent(id)}`;
}
