// Nurse Triage Dashboard
const { useState, useMemo, useEffect } = React;

function NurseDashboard() {
  const all = window.VF_DATA.patients;
  const [selectedId, setSelectedId] = useState("p-paul");
  const [filter, setFilter] = useState("all"); // all | critical | warning | stable | pending
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState("severity");

  const filtered = useMemo(() => {
    let list = all.slice();
    if (filter !== "all") list = list.filter(p => p.status === filter);
    if (query) {
      const q = query.toLowerCase();
      list = list.filter(p => p.name.toLowerCase().includes(q) || p.mrn.toLowerCase().includes(q));
    }
    if (sort === "severity") {
      const order = { critical:0, warning:1, pending:2, stable:3 };
      list.sort((a,b)=> order[a.status]-order[b.status] || (b.score||0)-(a.score||0));
    } else if (sort === "name") {
      list.sort((a,b)=> a.name.localeCompare(b.name));
    } else if (sort === "pod") {
      list.sort((a,b)=> a.pod - b.pod);
    }
    return list;
  }, [filter, query, sort]);

  const selected = filtered.find(p=>p.id===selectedId) || all.find(p=>p.id===selectedId) || filtered[0];

  const counts = useMemo(()=>({
    critical: all.filter(p=>p.status==="critical").length,
    warning: all.filter(p=>p.status==="warning").length,
    stable: all.filter(p=>p.status==="stable").length,
    pending: all.filter(p=>p.status==="pending").length,
  }), []);

  return (
    <div className="nurse">
      <div className="nurse-header">
        <div>
          <div className="section-label">Triage Queue · Tuesday, May 17</div>
          <h1 className="page-title">Good morning, Nancy</h1>
        </div>
        <div className="metrics">
          <Metric label="Critical" value={counts.critical} status="critical" active={filter==="critical"} onClick={()=>setFilter(filter==="critical"?"all":"critical")}/>
          <Metric label="Trending" value={counts.warning} status="warning" active={filter==="warning"} onClick={()=>setFilter(filter==="warning"?"all":"warning")}/>
          <Metric label="Awaiting" value={counts.pending} status="pending" active={filter==="pending"} onClick={()=>setFilter(filter==="pending"?"all":"pending")}/>
          <Metric label="Stable" value={counts.stable} status="stable" active={filter==="stable"} onClick={()=>setFilter(filter==="stable"?"all":"stable")}/>
        </div>
      </div>

      <div className="nurse-body">
        <aside className="queue">
          <div className="queue-toolbar">
            <div className="search">
              <Icon.Search/>
              <input placeholder="Search name or MRN…" value={query} onChange={e=>setQuery(e.target.value)}/>
            </div>
            <div className="sort">
              <span className="section-label">Sort</span>
              {[["severity","Severity"],["name","Name"],["pod","POD"]].map(([k,l])=>(
                <button key={k} className={`sort-btn ${sort===k?"on":""}`} onClick={()=>setSort(k)}>{l}</button>
              ))}
            </div>
          </div>

          <div className="queue-list scroll">
            {filtered.length === 0 && <div className="queue-empty">No patients match.</div>}
            {filtered.map(p => (
              <PatientRow key={p.id} p={p} selected={selected?.id===p.id} onClick={()=>setSelectedId(p.id)}/>
            ))}
          </div>

          <div className="queue-footer">
            <span className="section-label">{filtered.length} of {all.length} patients</span>
            <span className="section-label" style={{marginLeft:"auto", color:"var(--muted)"}}>Auto-refresh · 30s</span>
          </div>
        </aside>

        <main className="detail scroll">
          {selected ? <PatientDetail p={selected}/> : <div className="empty">Select a patient.</div>}
        </main>
      </div>
    </div>
  );
}

function Metric({ label, value, status, active, onClick }) {
  return (
    <button className={`metric ${active?"active":""}`} data-status={status} onClick={onClick}>
      <span className="metric-value">{value}</span>
      <span className="metric-label">
        <span className="pill-dot" style={{
          background:
            status==="critical"?"var(--critical)":
            status==="warning"?"var(--warning)":
            status==="stable"?"var(--stable)":"var(--muted)"
        }}/>
        {label}
      </span>
    </button>
  );
}

function PatientRow({ p, selected, onClick }) {
  const initials = p.name.split(" ").map(s=>s[0]).slice(0,2).join("");
  return (
    <button className={`prow ${selected?"selected":""}`} data-status={p.status} onClick={onClick}>
      <div className="prow-bar"/>
      <div className="prow-avatar">{initials}</div>
      <div className="prow-main">
        <div className="prow-top">
          <span className="prow-name">{p.name}</span>
          <Trend dir={p.trend}/>
        </div>
        <div className="prow-sub">
          <span>POD {p.pod}</span>
          <span className="dot">·</span>
          <span style={{textOverflow:"ellipsis", overflow:"hidden", whiteSpace:"nowrap"}}>{p.procedure}</span>
        </div>
        {p.triggers && p.triggers.length > 0 && (
          <div className="prow-trigger">{p.triggers[0]}{p.triggers.length>1 && ` · +${p.triggers.length-1}`}</div>
        )}
      </div>
      <div className="prow-meta">
        <StatusPill status={p.status} dot={false}/>
        <span className="prow-time">{p.lastCheckin}</span>
      </div>
    </button>
  );
}

function PatientDetail({ p }) {
  return (
    <div className="detail-inner">
      <div className="detail-head">
        <div>
          <div className="patient-meta">
            <span className="patient-mrn">{p.mrn}</span>
            <span className="dot">·</span>
            <span>{p.age} {p.sex}</span>
            <span className="dot">·</span>
            <span>POD {p.pod}</span>
            <span className="dot">·</span>
            <span>{p.surgeon}</span>
          </div>
          <h2 className="patient-name">{p.name}</h2>
          <div className="patient-procedure">{p.procedure}</div>
        </div>
        <div className="detail-head-right">
          <StatusPill status={p.status}/>
          <div className="detail-actions">
            <button className="btn btn-ghost btn-sm"><Icon.Bell/> Snooze</button>
            <button className="btn btn-ghost btn-sm">Assign</button>
            <button className="btn btn-primary btn-sm"><Icon.Phone size={12}/> Call patient</button>
          </div>
        </div>
      </div>

      {p.status === "critical" && <AlertBanner p={p}/>}

      <div className="detail-grid">
        <Vitals p={p}/>
        <Meds p={p}/>
      </div>

      <CheckinPanel p={p}/>

      <LogicInspector p={p}/>

      <AuditTrail p={p}/>
    </div>
  );
}

function AlertBanner({ p }) {
  return (
    <div className="alert-banner">
      <div className="alert-icon"><Icon.Bolt size={18}/></div>
      <div className="alert-main">
        <div className="alert-title">
          Critical alert · <span className="mono">{p.triggered_protocol}</span>
        </div>
        <div className="alert-sub">
          {p.triggers.join(" · ")} — flagged for possible DVT. Page Dr. Smith&apos;s on-call within 30 min.
        </div>
      </div>
      <div className="alert-actions">
        <button className="btn btn-sm btn-ghost">View protocol</button>
        <button className="btn btn-sm btn-danger"><Icon.Phone size={12}/> Page on-call</button>
      </div>
    </div>
  );
}

function Vitals({ p }) {
  if (!p.vitals) return <div className="card card-pad"><div className="section-label">Vitals</div><div className="empty-row">Not collected yet today.</div></div>;
  const v = p.vitals;
  const items = [
    { key:"hr", label:"Heart rate", icon:<Icon.Heart/>, ...v.hr, spark:[78,82,86,90,94,98,102] },
    { key:"spo2", label:"SpO₂", icon:<Icon.Wave/>, ...v.spo2, spark:[97,97,96,96,95,96,95] },
    { key:"temp", label:"Temperature", icon:<Icon.Thermo/>, ...v.temp, spark:[98.4,98.6,98.9,99.2,99.4,99.6,99.8] },
    { key:"bp",  label:"Blood pressure", icon:<Icon.Drop/>, ...v.bp, spark:null },
    { key:"pain", label:"Pain", icon:<Icon.Bolt/>, ...v.pain, spark:[2,3,4,5,6,6,6] }
  ];
  return (
    <section className="card vitals-card">
      <header className="card-head">
        <div className="section-label">Vitals · self-reported</div>
        <span className="mono-tag">updated {p.lastCheckinAt}</span>
      </header>
      <div className="vitals-grid">
        {items.map(it => (
          <div key={it.key} className="vital" data-state={it.state}>
            <div className="vital-top">
              <span className="vital-icon">{it.icon}</span>
              <span className="vital-label">{it.label}</span>
            </div>
            <div className="vital-value-row">
              <div className="vital-value">{it.value}<span className="vital-unit">{it.unit}</span></div>
              {it.spark && <Sparkline values={it.spark} color={it.state==="warning"?"var(--warning)":it.state==="critical"?"var(--critical)":"var(--ink-2)"} w={56} h={18}/>}
            </div>
            {it.range && (
              <div className="vital-range">target {it.range[0]}–{it.range[1]} {it.unit}</div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}

function Meds({ p }) {
  if (!p.meds) return null;
  return (
    <section className="card meds-card">
      <header className="card-head">
        <div className="section-label">Medications · today</div>
        <button className="btn btn-ghost btn-sm">Full schedule →</button>
      </header>
      <div className="meds-list">
        {p.meds.map(m => {
          const isMissed = m.status === "missed-am";
          const pct = m.expected ? (m.takenToday / m.expected) : 1;
          return (
            <div key={m.name} className="med-row" data-missed={isMissed}>
              <div className="med-icon"><Icon.Pill/></div>
              <div className="med-main">
                <div className="med-name">{m.name}</div>
                <div className="med-sub">{m.schedule} · {m.takenToday}{m.expected?` of ${m.expected}`:""} taken</div>
              </div>
              <div className="med-status">
                {isMissed ? (
                  <span className="pill critical"><span className="pill-dot"/>Missed AM</span>
                ) : (
                  <span className="pill stable"><span className="pill-dot"/>On schedule</span>
                )}
                <div className="med-bar"><div className="med-bar-fill" style={{width:`${Math.min(100,pct*100)}%`, background: isMissed?"var(--critical)":"var(--stable)"}}/></div>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function CheckinPanel({ p }) {
  if (!p.transcript) return null;
  return (
    <section className="card checkin-card">
      <AudioHero p={p}/>
      <ProsodySignals/>
      <div className="checkin-grid">
        <div className="transcript">
          <div className="transcript-head">
            <div className="section-label">Transcript</div>
            <span className="mono-tag">supporting · click a line to seek audio</span>
          </div>
          <div className="transcript-list">
            {p.transcript.map((m,i) => (
              <div key={i} className={`tline ${m.who}`}>
                <span className="tline-t mono">{m.t.slice(3)}</span>
                <span className="tline-who">{m.who==="system"?"System":"Paul"}</span>
                <div className="tline-text">{highlightHazards(m.text)}</div>
              </div>
            ))}
          </div>
        </div>
        <div className="extracted">
          <div className="section-label" style={{marginBottom:8}}>LLM-extracted variables</div>
          <div className="ext-list">
            {p.extracted.map(x => (
              <div className="ext-row" key={x.var}>
                <div>
                  <span className="mono ext-name">{x.var}</span>
                  <span className="ext-val mono">{x.val}</span>
                </div>
                <div className="ext-conf">
                  <span className="mono">{(x.conf*100).toFixed(0)}%</span>
                  <div className="ext-bar"><div style={{width:`${x.conf*100}%`}}/></div>
                </div>
              </div>
            ))}
          </div>
          <div className="ext-note">
            <Icon.Lock size={11}/>
            <span>Variables are passed to the deterministic Lua engine. The LLM never decides the alert.</span>
          </div>
        </div>
      </div>
    </section>
  );
}

// Audio is a first-class clinical object:
// - large waveform with elevated-tone regions colored
// - pause markers visible directly on the timeline
// - speaker swim-lanes so you can see who's talking when
// - emotional/clinical markers pinned to timestamps
function AudioHero({ p }) {
  const dur = p.audio_dur || 47;
  const [playing, setPlaying] = useState(false);
  const [pos, setPos] = useState(14); // seconds — start near the "warm/tender" mention

  useEffect(() => {
    if (!playing) return;
    const id = setInterval(() => {
      setPos(x => {
        const next = x + 0.5;
        if (next >= dur) { setPlaying(false); return 0; }
        return next;
      });
    }, 250);
    return () => clearInterval(id);
  }, [playing, dur]);

  // Generate waveform bars. Each bar has a time, a height, and a "tone" channel.
  const N = 96;
  const bars = useMemo(() => Array.from({length: N}).map((_, i) => {
    const t = (i / (N - 1)) * dur;
    // Pause regions (silence)
    const pauseA = t > 7.5 && t < 9.2;     // hesitation: "Um…"
    const pauseB = t > 30.5 && t < 33.0;   // pause before answering pain scale
    const pause = pauseA || pauseB;
    // Elevated-tone region: when Paul describes calf warmth (~13–22s) and pain (~33–37s)
    const elevatedA = t > 12 && t < 22;
    const elevatedB = t > 33 && t < 38;
    const elevated = elevatedA || elevatedB;
    // Speaker: system speaks first 0–7s + 24–32s + 41–47s; patient otherwise
    const isSystem = (t < 7) || (t > 24 && t < 32) || (t > 40.5);
    const base = 6 + Math.abs(Math.sin(i * 0.42) * 12) + Math.abs(Math.cos(i * 0.21) * 6);
    const boost = elevated ? 12 : 0;
    const h = pause ? 2 : (base + boost + (i % 7 === 0 ? 4 : 0));
    return { t, h, pause, elevated, isSystem };
  }), [dur]);

  const markersRaw = [
    { t: 8.2,  kind: "pause",   label: "1.7s pause", desc: "Hesitation before answering" },
    { t: 15.5, kind: "tone",    label: "Elevated tone", desc: "Voice strain detected — calf description" },
    { t: 20.0, kind: "keyword", label: "\u201Cwarm and tender\u201D", desc: "Hazard phrase · DVT screen" },
    { t: 31.5, kind: "pause",   label: "2.5s pause", desc: "Before answering pain scale" },
    { t: 34.0, kind: "tone",    label: "Wince audible", desc: "Sharp inhale on \u201Cwhen I press on it\u201D" }
  ];

  // Greedy collision-aware stagger across 3 levels.
  // Estimate flag width from label length (≈6px/char + 14px padding) and convert
  // to a "seconds" footprint so we can compare to other markers' time positions.
  const markers = useMemo(() => {
    const pxPerSec = 800 / dur; // assumes ~800px stage; conservative
    const buffer = 8; // px padding so neighbors don't kiss
    const placed = []; // {startT, endT, level}
    return markersRaw.map(m => {
      const widthPx = m.label.length * 6 + 14 + buffer * 2;
      const widthT = widthPx / pxPerSec;
      const startT = m.t - (buffer / pxPerSec);
      const endT = startT + widthT;
      let level = 0;
      while (placed.some(p => p.level === level && startT < p.endT && endT > p.startT)) {
        level++;
        if (level > 2) { level = 2; break; }
      }
      placed.push({ startT, endT, level });
      return { ...m, level };
    });
  }, [dur]);

  const fmt = (s) => {
    const m = Math.floor(s/60), r = Math.floor(s%60);
    return `${m}:${String(r).padStart(2,"0")}`;
  };

  const posPct = (pos / dur) * 100;

  const handleScrub = (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    setPos(x * dur);
  };

  return (
    <div className="audio-hero">
      <div className="audio-hero-head">
        <div>
          <div className="section-label">Original audio · clinical source-of-truth</div>
          <div className="checkin-meta">
            <span>Recorded {p.lastCheckinAt}</span>
            <span className="dot">·</span>
            <span>{p.audio_dur}s</span>
            <span className="dot">·</span>
            <span className="mono-tag">whisper-large-v3 · 16kHz mono</span>
          </div>
        </div>
        <div className="audio-actions">
          <button className="btn btn-sm btn-ghost">1.0×</button>
          <button className="btn btn-sm btn-ghost">Download</button>
          <button className="btn btn-sm">Open in player</button>
        </div>
      </div>

      <div className="audio-stage">
        <button className={`play-btn ${playing?"playing":""}`} onClick={()=>setPlaying(!playing)} aria-label={playing?"Pause":"Play"}>
          {playing
            ? <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>
            : <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M7 5l13 7-13 7V5z"/></svg>
          }
        </button>

        <div className="audio-track">
          <div className="audio-speaker-lanes">
            <span className="lane-label">System</span>
            <span className="lane-label">Paul</span>
          </div>

          <div className="audio-wave-big" onClick={handleScrub}>
            <div className="audio-marker-rail">
              {markers.map((m,i)=>(
                <div key={i} className={`amark ${m.kind}`} data-level={m.level} style={{left:`${(m.t/dur)*100}%`}}>
                  <span className="amark-stem"/>
                  <span className="amark-flag">
                    <span className="amark-label">{m.label}</span>
                  </span>
                </div>
              ))}
            </div>
            <div className="audio-bars-row top">
              {bars.map((b,i)=>(
                <span key={i}
                  className={`abar ${b.pause?"pause":""} ${b.elevated?"elev":""} ${b.isSystem?"on":"off"}`}
                  style={{height:`${b.isSystem?b.h:0}px`}}
                />
              ))}
            </div>
            <div className="audio-mid-rule"/>
            <div className="audio-bars-row bot">
              {bars.map((b,i)=>(
                <span key={i}
                  className={`abar ${b.pause?"pause":""} ${b.elevated?"elev":""} ${!b.isSystem?"on":"off"}`}
                  style={{height:`${!b.isSystem?b.h:0}px`}}
                />
              ))}
            </div>

            <div className="audio-playhead" style={{left:`${posPct}%`}}>
              <span className="audio-playhead-time mono">{fmt(pos)}</span>
            </div>
          </div>

          <div className="audio-timeline">
            {[0, 10, 20, 30, 40, dur].map(t => (
              <span key={t} className="mono">{fmt(t)}</span>
            ))}
          </div>
        </div>
      </div>

      <div className="audio-legend">
        <span><i className="sw" style={{background:"var(--accent)"}}/>System voice</span>
        <span><i className="sw" style={{background:"oklch(45% 0.16 70)"}}/>Patient · elevated tone</span>
        <span><i className="sw" style={{background:"var(--ink-2)"}}/>Patient · neutral</span>
        <span><i className="sw" style={{background:"var(--faint)"}}/>Pause / silence</span>
      </div>
    </div>
  );
}

// Acoustic / prosodic signals — first-class clinical chips.
// Designed as longitudinal signals that compare today vs. patient baseline.
function ProsodySignals() {
  const items = [
    {
      label: "Patient sounded distressed",
      severity: "warn",
      detail: "Stress index 0.71 · baseline 0.32",
      delta: "+39 pts vs. 7-day avg",
      spark: [28, 30, 34, 31, 40, 55, 71]
    },
    {
      label: "Long pauses detected",
      severity: "warn",
      detail: "2 pauses ≥ 1.5s · before calf + pain answers",
      delta: "baseline: 0 pauses",
      spark: [0, 0, 1, 0, 0, 1, 2]
    },
    {
      label: "Speech slower than baseline",
      severity: "info",
      detail: "118 wpm · baseline 154 wpm",
      delta: "−23% vs. 7-day avg",
      spark: [154, 150, 152, 148, 142, 130, 118]
    },
    {
      label: "Breathing pattern · normal",
      severity: "ok",
      detail: "No labored or shortened breaths detected",
      delta: "consistent with baseline",
      spark: [16, 17, 16, 17, 17, 16, 17]
    }
  ];
  return (
    <div className="prosody">
      <div className="prosody-head">
        <div>
          <div className="section-label">Acoustic signals · prosody analysis</div>
          <div className="prosody-sub">Tone, hesitation, and pace compared to Paul&apos;s 7-day baseline. Used as supporting context — never as a sole alert trigger.</div>
        </div>
        <span className="mono-tag">model: prosody-v0.4 · advisory</span>
      </div>
      <div className="prosody-grid">
        {items.map(it => (
          <div key={it.label} className={`prosody-card sev-${it.severity}`}>
            <div className="prosody-top">
              <span className="prosody-dot"/>
              <span className="prosody-label">{it.label}</span>
            </div>
            <div className="prosody-detail">{it.detail}</div>
            <div className="prosody-foot">
              <Sparkline values={it.spark} w={56} h={16}
                color={it.severity==="warn"?"var(--warning)":it.severity==="info"?"var(--accent)":"var(--stable)"}/>
              <span className="prosody-delta mono">{it.delta}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function highlightHazards(text) {
  // light highlight on a few hazard phrases
  const hazards = ["calf", "warm", "tender", "haven't taken", "blood thinners", "six", "hurts"];
  let parts = [text];
  hazards.forEach(h => {
    const next = [];
    parts.forEach(p => {
      if (typeof p !== "string") { next.push(p); return; }
      const idx = p.toLowerCase().indexOf(h);
      if (idx === -1) { next.push(p); return; }
      next.push(p.slice(0, idx));
      next.push(<mark key={h+idx}>{p.slice(idx, idx+h.length)}</mark>);
      next.push(p.slice(idx+h.length));
    });
    parts = next;
  });
  return parts;
}

function LogicInspector({ p }) {
  if (p.status !== "critical") return null;
  const lua = `-- DVT_Risk_Hip_v2 · live since 2026-04-29
-- Owner: Dr. M. Smith · signed: M.Smith@stmarys.org

function evaluate(patient, today)
  local warmth      = today.calf_warmth == true
  local tenderness  = today.calf_tenderness == true
  local pain        = tonumber(today.calf_pain_scale) or 0
  local missed_ac   = today.anticoag_taken_today_am == false

  local risk = 0
  if warmth then         risk = risk + 0.35 end
  if tenderness then     risk = risk + 0.30 end
  if pain >= 4 then      risk = risk + 0.15 end
  if missed_ac then      risk = risk + 0.20 end

  if risk >= 0.75 then
    return Alert.new {
      severity   = "critical",
      protocol   = "DVT_Risk_Hip_v2",
      page       = patient.surgeon_oncall,
      sla_min    = 30,
      message    = "Possible DVT — elevate leg, hold ambulation"
    }
  elseif risk >= 0.4 then
    return Alert.new { severity = "warning" }
  end
end`;
  const steps = [
    { label:"warmth", val:"true", weight:0.35, fired:true },
    { label:"tenderness", val:"true", weight:0.30, fired:true },
    { label:"pain ≥ 4", val:"6", weight:0.15, fired:true },
    { label:"missed AM anticoagulant", val:"true", weight:0.20, fired:true }
  ];
  const total = steps.reduce((a,s)=>a+(s.fired?s.weight:0),0);
  return (
    <section className="card logic-card">
      <header className="card-head">
        <div>
          <div className="section-label">Logic inspector · why this alert fired</div>
          <div className="logic-sub">
            <span className="pill accent"><span className="pill-dot"/>{p.triggered_protocol}</span>
            <span className="mono-tag">deterministic</span>
            <span className="mono-tag">audit #A-48201-0517-001</span>
          </div>
        </div>
        <button className="btn btn-ghost btn-sm">View protocol →</button>
      </header>

      <div className="logic-grid">
        <div className="logic-script">
          <div className="codehead">
            <span className="mono">protocols/DVT_Risk_Hip_v2.lua</span>
            <span className="mono-tag">Lua</span>
          </div>
          <pre className="code"><code>{lua}</code></pre>
        </div>
        <div className="logic-trace">
          <div className="section-label" style={{marginBottom:8}}>Score trace</div>
          {steps.map(s=>(
            <div className="trace-row" key={s.label} data-fired={s.fired}>
              <span className={`tick ${s.fired?"on":""}`}>{s.fired ? <Icon.Check size={11}/> : <Icon.X size={11}/>}</span>
              <span className="trace-label">{s.label}</span>
              <span className="mono trace-val">{s.val}</span>
              <span className="mono trace-w">+{s.weight.toFixed(2)}</span>
            </div>
          ))}
          <div className="trace-total">
            <span>Total risk score</span>
            <span className="mono"><b>{total.toFixed(2)}</b> / 1.00</span>
          </div>
          <div className="trace-bar">
            <div className="trace-bar-fill" style={{width:`${total*100}%`}}/>
            <div className="trace-bar-thresh" style={{left:"75%"}} title="Critical threshold 0.75"/>
            <div className="trace-bar-thresh warn" style={{left:"40%"}} title="Warning threshold 0.40"/>
          </div>
          <div className="trace-legend">
            <span><i className="sw stable"/>0.0</span>
            <span><i className="sw warning"/>0.40 warn</span>
            <span><i className="sw critical"/>0.75 critical</span>
          </div>
        </div>
      </div>
    </section>
  );
}

function AuditTrail({ p }) {
  const items = [
    { t:"08:42:48", text:"Alert paged to Dr. Smith on-call (SMS + EMR inbox)", who:"system" },
    { t:"08:42:43", text:`Protocol fired: ${p.triggered_protocol||"—"} · score 1.00 ≥ 0.75`, who:"lua" },
    { t:"08:42:24", text:"5 variables extracted from transcript", who:"llm" },
    { t:"08:42:08", text:"Voice check-in initiated by Oban job #check_daily_08", who:"oban" },
    { t:"08:42:00", text:"Patient answered call (3rd ring)", who:"system" }
  ];
  const tag = (who) => {
    if (who==="lua") return <span className="audit-tag lua">Lua</span>;
    if (who==="llm") return <span className="audit-tag llm">LLM</span>;
    if (who==="oban") return <span className="audit-tag oban">Oban</span>;
    return <span className="audit-tag sys">System</span>;
  };
  return (
    <section className="card audit-card">
      <header className="card-head">
        <div className="section-label">Audit trail · last 5 events</div>
        <button className="btn btn-ghost btn-sm">Full history →</button>
      </header>
      <ol className="audit-list">
        {items.map((it,i)=>(
          <li key={i}>
            <span className="audit-t mono">{it.t}</span>
            {tag(it.who)}
            <span className="audit-text">{it.text}</span>
          </li>
        ))}
      </ol>
    </section>
  );
}

window.NurseDashboard = NurseDashboard;
