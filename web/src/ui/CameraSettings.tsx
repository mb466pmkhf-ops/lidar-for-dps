// The camera settings every reading is worked out from, kept in view above the inspector so a change
// shows on every reading at once. Same steps as ExposureQuickBar / ExposureSheet on the iPhone.
import type { ExposureSettings } from '../model/types';
import { exposureTime, frameRates, isoSteps, keyLux, shutterAngles, speedLabel, steppedISO, steppedStop, stopLabel, thirdStops, trim } from '../model/exposure';
import { lux as fmtLux, READING_EXTRAS, readingExtra, setReadingExtra, useReadingExtra, type ReadingExtra } from './format';

/** The list plus the current value, so a value set on the phone still shows. */
const withCurrent = (list: number[], v: number) => (list.some(x => Math.abs(x - v) < 0.01) ? list : [...list, v].sort((a, b) => a - b));
const nearest = (list: number[], v: number) => list.find(x => Math.abs(x - v) < 0.01) ?? v;
const ndLabel = (s: number) => (s === 0 ? 'No ND' : `ND ${(s * 0.3).toFixed(1)}`);

function Stepper({ label, value, options, format, onChange, onStep }: {
  label: string; value: number; options: number[]; format(v: number): string; onChange(v: number): void; onStep(d: number): void;
}) {
  return (
    <div className="cam-step">
      <span className="label">{label}</span>
      <div className="cam-step-row">
        <button className="cam-btn" onClick={() => onStep(-1)} aria-label={`${label} down a third`} title="Down a third of a stop">−</button>
        <select value={nearest(options, value)} onChange={e => onChange(Number(e.target.value))} aria-label={label}>
          {withCurrent(options, value).map(v => <option key={v} value={v}>{format(v)}</option>)}
        </select>
        <button className="cam-btn" onClick={() => onStep(1)} aria-label={`${label} up a third`} title="Up a third of a stop">+</button>
      </div>
    </div>
  );
}

export function CameraSettingsBar({ exposure: e, onChange }: { exposure: ExposureSettings; onChange(patch: Partial<ExposureSettings>): void }) {
  useReadingExtra();
  const extra = readingExtra();
  return (
    <section className="cam-bar" aria-label="Camera settings">
      <div className="cam-bar-head">
        <h3>Camera settings</h3>
        <span className="mono muted" title="Incident reading that exposes a subject correctly at these settings">key ≈ {fmtLux(keyLux(e))}</span>
      </div>
      <div className="cam-grid">
        <Stepper label="T-stop" value={e.tStop} options={thirdStops} format={v => stopLabel(v)}
          onChange={v => onChange({ tStop: v })} onStep={d => onChange({ tStop: steppedStop(e.tStop, d) })} />
        <Stepper label="ISO" value={e.iso} options={isoSteps} format={v => String(v)}
          onChange={v => onChange({ iso: v })} onStep={d => onChange({ iso: steppedISO(e.iso, d) })} />
      </div>
      <div className="cam-grid three">
        <label className="cam-step"><span className="label">Frame rate</span>
          <select value={nearest(frameRates, e.frameRate)} onChange={x => onChange({ frameRate: Number(x.target.value), shutterSeconds: undefined })} disabled={e.shutterSeconds !== undefined}>
            {withCurrent(frameRates, e.frameRate).map(v => <option key={v} value={v}>{trim(v)} fps</option>)}
          </select>
        </label>
        <label className="cam-step"><span className="label">Shutter</span>
          <select value={e.shutterSeconds !== undefined ? 'speed' : nearest(shutterAngles, e.shutterAngle)}
            onChange={x => onChange({ shutterAngle: Number(x.target.value), shutterSeconds: undefined })} title={speedLabel(exposureTime(e))}>
            {e.shutterSeconds !== undefined && <option value="speed">{speedLabel(e.shutterSeconds)} (set on the phone)</option>}
            {withCurrent(shutterAngles, e.shutterAngle).map(v => <option key={v} value={v}>{trim(v)}°</option>)}
          </select>
        </label>
        <label className="cam-step"><span className="label">ND</span>
          <select value={e.ndStops} onChange={x => onChange({ ndStops: Number(x.target.value) })}>
            {withCurrent([0, 1, 2, 3, 4, 5, 6, 7, 8], e.ndStops).map(v => <option key={v} value={v}>{ndLabel(v)}</option>)}
          </select>
        </label>
      </div>
      <div className="cam-readings" role="group" aria-label="After the stop, show">
        <span className="label">Readings</span>
        <div className="seg">
          {READING_EXTRAS.map(([v, label]) => (
            <button key={v} className={'chip' + (extra === v ? ' on' : '')} aria-pressed={extra === v} onClick={() => setReadingExtra(v as ReadingExtra)}>
              {v === 'off' ? 'Stop only' : `+ ${label.toLowerCase()}`}
            </button>
          ))}
        </div>
      </div>
    </section>
  );
}
