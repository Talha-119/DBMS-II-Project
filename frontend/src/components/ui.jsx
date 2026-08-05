// Small shared UI primitives.
import { useMemo, useState } from 'react';

// Type-to-filter dropdown. Matches are ranked prefix-first then substring, so
// typing "bazar" surfaces "Bazar..." before "Rayer Bazar". By default only a value
// present in `options` can be committed (the user can't leave free text in the
// field); pass allowFreeText to keep whatever was typed when nothing matches
// (used for "previous school", which may not be registered).
export function Combobox({
  options, value, onChange, placeholder, disabled, disabledHint,
  allowFreeText = false, invalid = false,
}) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const [focused, setFocused] = useState(false);

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return options.slice(0, 12);
    const starts = [], subs = [];
    for (const o of options) {
      const i = o.toLowerCase().indexOf(q);
      if (i === 0) starts.push(o);
      else if (i > 0) subs.push(o);
    }
    starts.sort((a, b) => a.localeCompare(b));
    subs.sort((a, b) => a.localeCompare(b));
    return [...starts, ...subs].slice(0, 14);
  }, [options, query]);

  const shown = focused ? query : (value || '');
  const pick = (o) => { onChange(o); setQuery(o); setOpen(false); setFocused(false); };

  return (
    <div className="combo">
      <input
        className={invalid ? 'invalid' : (value ? 'valid' : '')}
        disabled={disabled}
        value={shown}
        placeholder={disabled ? (disabledHint || placeholder) : placeholder}
        onFocus={() => { if (disabled) return; setFocused(true); setQuery(value || ''); setOpen(true); }}
        onChange={(e) => { setQuery(e.target.value); setOpen(true); if (allowFreeText) onChange(e.target.value); }}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && matches.length) { e.preventDefault(); pick(matches[0]); }
          else if (e.key === 'Escape') setOpen(false);
        }}
        onBlur={() => setTimeout(() => { setFocused(false); setOpen(false); }, 130)}
      />
      {open && !disabled && (
        <ul className="combo-list">
          {matches.length
            ? matches.map((o) => (
              <li key={o} onMouseDown={(e) => { e.preventDefault(); pick(o); }}>{o}</li>))
            : <li className="combo-empty">{allowFreeText ? 'No match — your text will be used as typed' : 'No match'}</li>}
        </ul>
      )}
    </div>
  );
}

export function Alert({ kind = 'info', children }) {
  if (!children) return null;
  return <div className={`alert alert-${kind}`}>{children}</div>;
}

export function Stepper({ steps, current }) {
  return (
    <div className="stepper">
      {steps.map((s, i) => (
        <div key={s} className={`step ${i === current ? 'active' : i < current ? 'done' : ''}`}>
          {i + 1}. {s}
        </div>
      ))}
    </div>
  );
}

export function Field({ label, help, children }) {
  return (
    <div className="field">
      {label && <label>{label}</label>}
      {children}
      {help && <div className="help">{help}</div>}
    </div>
  );
}

export function Badge({ value }) {
  return <span className={`badge ${value}`}>{value}</span>;
}
