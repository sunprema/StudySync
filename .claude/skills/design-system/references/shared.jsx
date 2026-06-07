// Shared icons + primitives for PostOpGuard
const Icon = {
  Heart: (p = {}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 12h4l2-5 4 10 2-5h6"/>
    </svg>
  ),
  Drop: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6"><path d="M12 3s6 6.5 6 11a6 6 0 1 1-12 0c0-4.5 6-11 6-11z"/></svg>
  ),
  Pill: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <rect x="3" y="9" width="18" height="6" rx="3" transform="rotate(-25 12 12)"/>
      <path d="M9 7.5l4.5 9.5" />
    </svg>
  ),
  Thermo: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round"><path d="M14 4a2 2 0 0 0-4 0v10a4 4 0 1 0 4 0V4z"/><circle cx="12" cy="17" r="1.5" fill="currentColor"/></svg>
  ),
  Mic: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>
  ),
  Phone: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M5 4h4l2 5-2 1a12 12 0 0 0 5 5l1-2 5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/></svg>
  ),
  Bell: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M6 16V11a6 6 0 1 1 12 0v5l2 2H4l2-2zM10 20a2 2 0 0 0 4 0"/></svg>
  ),
  Search: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round"><circle cx="11" cy="11" r="6"/><path d="M20 20l-3.5-3.5"/></svg>
  ),
  ArrowUp: (p={}) => (
    <svg width={p.size||12} height={p.size||12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M12 19V5M6 11l6-6 6 6"/></svg>
  ),
  ArrowDown: (p={}) => (
    <svg width={p.size||12} height={p.size||12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M12 5v14M6 13l6 6 6-6"/></svg>
  ),
  Dash: (p={}) => (
    <svg width={p.size||12} height={p.size||12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M5 12h14"/></svg>
  ),
  Play: (p={}) => (
    <svg width={p.size||12} height={p.size||12} viewBox="0 0 24 24" fill="currentColor"><path d="M7 5l12 7-12 7V5z"/></svg>
  ),
  Check: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12l5 5 9-11"/></svg>
  ),
  X: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>
  ),
  Lock: (p={}) => (
    <svg width={p.size||12} height={p.size||12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 1 1 8 0v3"/></svg>
  ),
  Sparkle: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5L18 18M6 18l2.5-2.5M15.5 8.5L18 6"/></svg>
  ),
  Wave: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round"><path d="M3 12h2M7 8v8M11 5v14M15 8v8M19 12h2"/></svg>
  ),
  Bolt: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M13 3L4 14h7l-1 7 9-11h-7l1-7z"/></svg>
  ),
  Stack: (p={}) => (
    <svg width={p.size||14} height={p.size||14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round"><path d="M12 3l9 5-9 5-9-5 9-5zM3 12l9 5 9-5M3 16l9 5 9-5"/></svg>
  )
};

function StatusPill({ status, children, dot=true }) {
  const map = { critical:"critical", warning:"warning", stable:"stable", pending:"muted", accent:"accent" };
  const label = children || (
    status==="critical" ? "Critical" :
    status==="warning" ? "Trending" :
    status==="stable" ? "Stable" :
    status==="pending" ? "Awaiting" : status
  );
  return (
    <span className={`pill ${map[status]||"muted"}`}>
      {dot && <span className="pill-dot"/>}
      {label}
    </span>
  );
}

function Trend({ dir }) {
  if (dir === "up") return <span style={{color:"var(--critical)", display:"inline-flex"}}><Icon.ArrowUp/></span>;
  if (dir === "down") return <span style={{color:"var(--stable)", display:"inline-flex"}}><Icon.ArrowDown/></span>;
  return <span style={{color:"var(--muted)", display:"inline-flex"}}><Icon.Dash/></span>;
}

// Sparkline — tiny inline trend
function Sparkline({ values, color="var(--ink-2)", w=64, h=18 }) {
  if (!values || !values.length) return null;
  const min = Math.min(...values), max = Math.max(...values);
  const span = max - min || 1;
  const step = w / (values.length - 1);
  const pts = values.map((v,i)=>{
    const x = i*step;
    const y = h - ((v - min)/span) * (h-2) - 1;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(" ");
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`}>
      <polyline points={pts} fill="none" stroke={color} strokeWidth="1.4" strokeLinejoin="round" strokeLinecap="round"/>
    </svg>
  );
}

// PostOpGuard brand mark — shield with medical cross + ECG wave.
// Gradient mirrors the reference: blue → teal → green, top-left to bottom-right.
function BrandMark({ size = 26 }) {
  const id = React.useId();
  const g  = `bm-grad-${id}`;
  const s  = `bm-shadow-${id}`;
  return (
    <svg width={size} height={size} viewBox="0 0 40 40" aria-hidden="true" style={{display:"block"}}>
      <defs>
        <linearGradient id={g} x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%"   stopColor="#3387C7"/>
          <stop offset="55%"  stopColor="#3FB0A8"/>
          <stop offset="100%" stopColor="#7BC58A"/>
        </linearGradient>
        <linearGradient id={s} x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor="white" stopOpacity="0.55"/>
          <stop offset="100%" stopColor="white" stopOpacity="0"/>
        </linearGradient>
      </defs>
      {/* Shield body */}
      <path
        d="M20 2.5 L34.5 7 V19 C34.5 28.5 28 35 20 37.5 C12 35 5.5 28.5 5.5 19 V7 Z"
        fill={`url(#${g})`}
      />
      {/* Inner highlight ring */}
      <path
        d="M20 5.4 L31.6 9.0 V19 C31.6 27 26.4 32.5 20 34.7 C13.6 32.5 8.4 27 8.4 19 V9.0 Z"
        fill="none"
        stroke="white"
        strokeOpacity="0.55"
        strokeWidth="1"
      />
      {/* Medical cross */}
      <g fill="white">
        <rect x="17.3" y="10.5" width="5.4" height="11"  rx="0.9"/>
        <rect x="14.5" y="13.3" width="11"  height="5.4" rx="0.9"/>
      </g>
      {/* ECG wave across the lower half */}
      <path
        d="M8 24 L13 24 L15 20 L17.5 27.5 L20 18 L22.5 25 L25 22 L27 24 L32 24"
        fill="none"
        stroke="white"
        strokeWidth="1.4"
        strokeLinejoin="round"
        strokeLinecap="round"
        opacity="0.95"
      />
      {/* Top gloss */}
      <path
        d="M20 2.5 L34.5 7 V12 C28 9.5 22 8.6 20 8.6 C18 8.6 12 9.5 5.5 12 V7 Z"
        fill={`url(#${s})`}
        opacity="0.35"
      />
    </svg>
  );
}

// Gradient wordmark
function BrandWordmark({ size = 15 }) {
  const id = React.useId();
  const g = `bw-${id}`;
  return (
    <span style={{display:"inline-flex", alignItems:"baseline", fontSize:size, fontWeight:600, letterSpacing:"-0.01em", lineHeight:1}}>
      <svg width="0" height="0" style={{position:"absolute"}}>
        <defs>
          <linearGradient id={g} x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%"   stopColor="#1F5B8F"/>
            <stop offset="55%"  stopColor="#2E8A8B"/>
            <stop offset="100%" stopColor="#3FA372"/>
          </linearGradient>
        </defs>
      </svg>
      <span style={{
        background: "linear-gradient(90deg, #1F5B8F 0%, #2E8A8B 55%, #3FA372 100%)",
        WebkitBackgroundClip: "text",
        backgroundClip: "text",
        color: "transparent"
      }}>PostOpGuard</span>
    </span>
  );
}

Object.assign(window, { Icon, StatusPill, Trend, Sparkline, BrandMark, BrandWordmark });
