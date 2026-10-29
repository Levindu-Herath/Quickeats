import { ChangeEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api, ApiError, EmployeeEmail, ImportResult, Organisation, RejectedEmail } from './api';
import ConfirmDialog from './ConfirmDialog';
import { exampleEmail, extractEmails } from './validation';

interface Props {
  org: Organisation;
  /** Called after any change, so the organisations table can refresh its counts. */
  onChanged: () => void;
  onClose: () => void;
}

interface PickedFile {
  name: string;
  emails: string[];
}

type Confirm = { kind: 'replace' } | { kind: 'clear' } | { kind: 'remove'; email: string };

const SHOW_REJECTED = 20;
const SHOW_EMAILS = 500;

/** Manages an organisation's employee list: import from CSV/text, remove, replace, clear. */
export default function EmployeesDialog({ org, onChanged, onClose }: Props) {
  const dialog = useRef<HTMLDialogElement>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const [list, setList] = useState<EmployeeEmail[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [file, setFile] = useState<PickedFile | null>(null);
  const [mode, setMode] = useState<'add' | 'replace'>('add');
  const [busy, setBusy] = useState(false);
  const [importError, setImportError] = useState<string | null>(null);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [rejected, setRejected] = useState<RejectedEmail[]>([]);
  const [confirm, setConfirm] = useState<Confirm | null>(null);

  useEffect(() => {
    dialog.current?.showModal();
  }, []);

  const load = useCallback(async () => {
    setLoadError(null);
    try {
      setList(await api.listEmployees(org.id));
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : 'Could not load the employee list');
    }
  }, [org.id]);

  useEffect(() => {
    load();
  }, [load]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!list || !q) return list ?? [];
    return list.filter((e) => e.email.includes(q));
  }, [list, query]);

  const registered = list?.filter((e) => e.registered).length ?? 0;

  async function pickFile(e: ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    setResult(null);
    setRejected([]);
    setImportError(null);
    if (!f) return;
    const emails = extractEmails(await f.text());
    setFile({ name: f.name, emails });
    if (emails.length === 0) setImportError(`No email addresses found in ${f.name}.`);
  }

  function resetFile() {
    setFile(null);
    if (fileInput.current) fileInput.current.value = '';
  }

  async function runImport() {
    if (!file || file.emails.length === 0) return;
    setBusy(true);
    setImportError(null);
    setResult(null);
    setRejected([]);
    try {
      const res = await api.importEmployees(org.id, file.emails, mode);
      setResult(res);
      setRejected(res.rejected ?? []);
      resetFile();
      await load();
      onChanged();
    } catch (err) {
      setImportError(err instanceof Error ? err.message : 'Import failed');
      if (err instanceof ApiError && Array.isArray(err.details?.rejected)) {
        setRejected(err.details.rejected as RejectedEmail[]);
      }
    } finally {
      setBusy(false);
    }
  }

  function onImportClick() {
    // Replacing a non-empty list drops emails, so ask first.
    if (mode === 'replace' && (list?.length ?? 0) > 0) setConfirm({ kind: 'replace' });
    else runImport();
  }

  async function removeOne(email: string) {
    await api.removeEmployee(org.id, email);
    setConfirm(null);
    setList((l) => l?.filter((e) => e.email !== email) ?? null);
    onChanged();
  }

  async function clearAll() {
    await api.clearEmployees(org.id);
    setConfirm(null);
    setResult(null);
    setRejected([]);
    await load();
    onChanged();
  }

  const domains = org.emailDomains;

  return (
    <dialog ref={dialog} className="dialog dialog-wide" onClose={onClose}>
      <div className="dialog-body">
        <header className="dialog-head">
          <div>
            <h2>Employee list</h2>
            <p className="muted small-text">
              {org.name} · <code className="code">{org.slug}</code>
            </p>
          </div>
          <button type="button" className="icon-btn" aria-label="Close" onClick={onClose}>
            ×
          </button>
        </header>

        <div className="preview">
          {list && list.length > 0 ? (
            <>
              Only the <strong>{list.length}</strong> listed {list.length === 1 ? 'email' : 'emails'} can sign up as
              customers ({registered} registered so far). Merchants are not checked.
            </>
          ) : (
            <>
              No list yet: any email on {domains.map((d) => '@' + d).join(', ')} can sign up. Import a list to allow
              only your employees, e.g. <code>{exampleEmail(domains[0] ?? 'example.com')}</code>.
            </>
          )}
        </div>

        <section className="import-box">
          <h3>Import from a file</h3>
          <p className="hint">
            A .csv or .txt file with one email per line, or an email column. Every email must be on{' '}
            {domains.map((d) => '@' + d).join(' or ')}.
          </p>

          <div className="file-row">
            <input
              ref={fileInput}
              type="file"
              accept=".csv,.txt,text/csv,text/plain"
              onChange={pickFile}
              aria-label="Employee email file"
            />
          </div>

          {file && file.emails.length > 0 && (
            <>
              <p className="file-summary">
                Found <strong>{file.emails.length}</strong> {file.emails.length === 1 ? 'email' : 'emails'} in{' '}
                <code>{file.name}</code>
              </p>
              <fieldset className="mode">
                <legend className="sr-only">Import mode</legend>
                <label>
                  <input type="radio" name="mode" checked={mode === 'add'} onChange={() => setMode('add')} />
                  <span>
                    <strong>Add to the list</strong>
                    <span className="hint">Keeps the current emails.</span>
                  </span>
                </label>
                <label>
                  <input type="radio" name="mode" checked={mode === 'replace'} onChange={() => setMode('replace')} />
                  <span>
                    <strong>Replace the list</strong>
                    <span className="hint">Emails not in this file are removed.</span>
                  </span>
                </label>
              </fieldset>
              <div className="import-actions">
                <button type="button" className="btn" onClick={resetFile} disabled={busy}>
                  Cancel
                </button>
                <button type="button" className="btn primary" onClick={onImportClick} disabled={busy}>
                  {busy ? 'Importing…' : mode === 'add' ? 'Add emails' : 'Replace list'}
                </button>
              </div>
            </>
          )}

          {importError && (
            <p className="error" role="alert">
              {importError}
            </p>
          )}
          {result && (
            <p className="success" role="status">
              Added {result.added}
              {result.removed > 0 && `, removed ${result.removed}`}. The list now has {result.total}{' '}
              {result.total === 1 ? 'email' : 'emails'}.
            </p>
          )}
          {rejected.length > 0 && (
            <div className="rejected">
              <p>
                <strong>{rejected.length}</strong> {rejected.length === 1 ? 'entry was' : 'entries were'} skipped:
              </p>
              <ul>
                {rejected.slice(0, SHOW_REJECTED).map((r) => (
                  <li key={r.value}>
                    <code>{r.value}</code> <span className="muted">— {r.reason}</span>
                  </li>
                ))}
              </ul>
              {rejected.length > SHOW_REJECTED && (
                <p className="muted">…and {rejected.length - SHOW_REJECTED} more.</p>
              )}
            </div>
          )}
        </section>

        <section>
          <div className="list-head">
            <h3>Listed emails {list && list.length > 0 && <span className="muted">({list.length})</span>}</h3>
            {list && list.length > 0 && (
              <button type="button" className="btn small danger-outline" onClick={() => setConfirm({ kind: 'clear' })}>
                Remove all
              </button>
            )}
          </div>

          {list && list.length > 5 && (
            <input
              type="search"
              className="list-search"
              placeholder="Search emails"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="Search employee emails"
            />
          )}

          {loadError && (
            <div className="empty">
              <p className="error">{loadError}</p>
              <button className="btn" onClick={load}>
                Try again
              </button>
            </div>
          )}
          {!loadError && list === null && <div className="empty muted">Loading…</div>}
          {!loadError && list !== null && filtered.length === 0 && (
            <div className="empty muted">{list.length === 0 ? 'The list is empty.' : 'No matches.'}</div>
          )}
          {!loadError && filtered.length > 0 && (
            <ul className="email-list">
              {filtered.slice(0, SHOW_EMAILS).map((e) => (
                <li key={e.email}>
                  <span className="email">{e.email}</span>
                  {e.registered && <span className="badge">Registered</span>}
                  <button
                    type="button"
                    className="btn small ghost"
                    aria-label={`Remove ${e.email}`}
                    onClick={() => setConfirm({ kind: 'remove', email: e.email })}
                  >
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          )}
          {filtered.length > SHOW_EMAILS && (
            <p className="hint list-more">
              Showing {SHOW_EMAILS} of {filtered.length}. Search to find a specific email.
            </p>
          )}
        </section>

        <footer className="dialog-foot">
          <button type="button" className="btn" onClick={onClose}>
            Done
          </button>
        </footer>
      </div>

      {confirm?.kind === 'replace' && (
        <ConfirmDialog
          title="Replace the employee list?"
          confirmLabel="Replace list"
          onClose={() => setConfirm(null)}
          onConfirm={async () => {
            setConfirm(null);
            await runImport();
          }}
        >
          The {list?.length} current emails will be replaced by the {file?.emails.length} in <code>{file?.name}</code>.
          Accounts that already exist are not affected.
        </ConfirmDialog>
      )}
      {confirm?.kind === 'clear' && (
        <ConfirmDialog title="Remove every email?" confirmLabel="Remove all" onClose={() => setConfirm(null)} onConfirm={clearAll}>
          The list will be empty, so any email on {domains.map((d) => '@' + d).join(', ')} can sign up again. Existing
          accounts are not affected.
        </ConfirmDialog>
      )}
      {confirm?.kind === 'remove' && (
        <ConfirmDialog
          title="Remove this email?"
          confirmLabel="Remove"
          onClose={() => setConfirm(null)}
          onConfirm={() => removeOne(confirm.email)}
        >
          <code>{confirm.email}</code> will no longer be able to sign up. If they already have an account, it keeps
          working.
          {list?.length === 1 && (
            <> This is the last email, so afterwards any email on {domains.map((d) => '@' + d).join(', ')} can sign up.</>
          )}
        </ConfirmDialog>
      )}
    </dialog>
  );
}
