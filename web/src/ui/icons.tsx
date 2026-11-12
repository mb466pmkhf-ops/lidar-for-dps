// Small line icons drawn inline (no icon font, works offline).
const paths: Record<string, string> = {
  select: 'M5 3l12 6-5 2-2 5z',
  light: 'M9 18h6M10 21h4M12 3a6 6 0 0 0-4 10.5c.7.7 1 1.5 1 2.5h6c0-1 .3-1.8 1-2.5A6 6 0 0 0 12 3z',
  board: 'M5 4h14v16H5z',
  person: 'M12 7a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM7 22v-8a5 5 0 0 1 10 0v8',
  meter: 'M12 3l7 9-7 9-7-9z',
  camera: 'M3 7h12v10H3zM15 10l6-3v10l-6-3',
  undo: 'M9 14L4 9l5-5M4 9h11a5 5 0 0 1 0 10h-3',
  redo: 'M15 14l5-5-5-5M20 9H9a5 5 0 0 0 0 10h3',
  map: 'M3 3h18v18H3zM3 9h18M3 15h18M9 3v18M15 3v18',
  trash: 'M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3',
  copy: 'M8 8h12v12H8zM4 16V4h12',
  aim: 'M12 2v4M12 18v4M2 12h4M18 12h4M12 12m-6 0a6 6 0 1 0 12 0 6 6 0 1 0-12 0',
  menu: 'M3 6h18M3 12h18M3 18h18',
  cloud: 'M7 18h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 9a4.5 4.5 0 0 0 1 9z',
  upload: 'M12 16V4M7 9l5-5 5 5M4 20h16',
  download: 'M12 4v12M7 11l5 5 5-5M4 20h16',
  plus: 'M12 5v14M5 12h14',
  eye: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12zM12 12m-3 0a3 3 0 1 0 6 0 3 3 0 1 0-6 0',
  power: 'M12 3v9M6.3 6.3a8 8 0 1 0 11.4 0',
  home: 'M4 11l8-7 8 7v8a1 1 0 0 1-1 1h-4v-6h-6v6H5a1 1 0 0 1-1-1z',
  pencil: 'M4 20l4-1L19 8l-3-3L5 16zM14 7l3 3',
  folder: 'M3 7a1 1 0 0 1 1-1h5l2 2h9a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z',
  phone: 'M8 2h8a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zM11 18h2',
  moon: 'M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.500 10.500z',
  sun: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2',
  planmap: 'M9 4L3 6v14l6-2 6 2 6-2V4l-6 2zM9 4v14M15 6v14',
  fit: 'M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5',
  sofa: 'M5 11V8a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v3M3 13a2 2 0 0 1 4 0v2h10v-2a2 2 0 0 1 4 0v5H3zM5 18v2M19 18v2',
  turnLeft: 'M4 9a8 8 0 1 1 1.5 7M4 4v5h5',
  turnRight: 'M20 9a8 8 0 1 0-1.5 7M20 4v5h-5',
};
export function Icon({ name, className = 'icon' }: { name: keyof typeof paths | string; className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={paths[name] ?? ''} />
    </svg>
  );
}

/** The FrameScan mark: the false-colour stop scale with the key raised, as on the plan legend. */
export function StopMark() {
  const cols = ['#1f296b', '#2e54cc', '#4d9ec7', '#8c8c8c', '#40bf5e', '#e68ca8', '#e0663d', '#ff2929'];
  return (
    <svg className="stopmark" viewBox="0 0 36 12" aria-hidden="true">
      {cols.map((c, i) => <rect key={c} x={i * 4.5} y={i === 4 ? 0 : 3} width={4.5} height={i === 4 ? 12 : 6} fill={c} />)}
    </svg>
  );
}
