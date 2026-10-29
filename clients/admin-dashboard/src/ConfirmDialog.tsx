import { ReactNode, useEffect, useRef, useState } from 'react';

interface Props {
  title: string;
  children: ReactNode;
  confirmLabel: string;
  /** Runs the action; a thrown error is shown in the dialog. */
  onConfirm: () => Promise<void>;
  onClose: () => void;
}

/** A small modal that asks before a destructive action. */
export default function ConfirmDialog({ title, children, confirmLabel, onConfirm, onClose }: Props) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    dialog.current?.showModal();
  }, []);

  async function confirm() {
    setBusy(true);
    setError(null);
    try {
      await onConfirm();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong');
      setBusy(false);
    }
  }

  return (
    <dialog ref={dialog} className="dialog dialog-small" onClose={onClose}>
      <div className="dialog-body">
        <header className="dialog-head">
          <h2>{title}</h2>
        </header>
        <div className="confirm-text">{children}</div>
        {error && <p className="error" role="alert">{error}</p>}
        <footer className="dialog-foot">
          <button type="button" className="btn" onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button type="button" className="btn danger" onClick={confirm} disabled={busy}>
            {busy ? 'Working…' : confirmLabel}
          </button>
        </footer>
      </div>
    </dialog>
  );
}
