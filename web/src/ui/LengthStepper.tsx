// A size with − and +: shown and typed in metres, or in feet when the units are set to feet
// (12'6" works too). The value given and returned is always metres.
import { useState } from 'react';
import { fromInput, lengthUnitLabel, toInput, useLengthUnits } from './format';

export function LengthStepper({ label, note, value, min, max, compact, onChange }: {
  label: string; note?: string; value: number; min: number; max: number; compact?: boolean; onChange(metres: number): void;
}) {
  const u = useLengthUnits();
  const [text, setText] = useState<string>();
  // 10 cm, or 6 inches.
  const step = u === 'imperial' ? 0.1524 : 0.1;
  const clamp = (v: number) => Math.min(max, Math.max(min, v));
  const set = (v: number) => { setText(undefined); onChange(Math.round(clamp(v) * 1000) / 1000); };
  return (
    <div className={'stepper' + (compact ? ' compact' : '')}>
      {compact ? <span>{label}</span> : <span><span style={{ display: 'block' }}>{label}</span>{note && <span className="note" style={{ margin: 0 }}>{note}</span>}</span>}
      <span className="ctl">
        <button type="button" aria-label={`Less ${label.toLowerCase()}`} onClick={() => set(value - step)}>−</button>
        <input type="text" inputMode="decimal" aria-label={`${label} in ${u === 'imperial' ? 'feet' : 'metres'}`} value={text ?? String(toInput(value, u))}
          onChange={e => { setText(e.target.value); const m = fromInput(e.target.value, u); if (m !== undefined) onChange(m); }}
          onBlur={() => set(value)} />
        <span className="unit" aria-hidden="true">{lengthUnitLabel(u)}</span>
        <button type="button" aria-label={`More ${label.toLowerCase()}`} onClick={() => set(value + step)}>+</button>
      </span>
    </div>
  );
}
