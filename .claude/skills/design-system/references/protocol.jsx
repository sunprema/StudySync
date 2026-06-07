// Protocol Builder — NL canvas ↔ generated Lua side-by-side
const { useState: useStateP, useEffect: useEffectP, useMemo: useMemoP } = React;

function ProtocolBuilder() {
  const protocols = window.VF_DATA.protocolList;
  const [activeId, setActiveId] = useStateP("DVT_Risk_Hip_v2");
  const [nl, setNl] = useStateP(DEFAULT_NL);
  const [version, setVersion] = useStateP("v3 (draft)");
  const [simInput, setSimInput] = useStateP({
    calf_warmth: true,
    calf_tenderness: true,
    calf_pain_scale: 6,
    anticoag_taken_today_am: false
  });
  const [compiling, setCompiling] = useStateP(false);
  const [compiled, setCompiled] = useStateP(true);

  useEffectP(() => {
    setCompiling(true);
    setCompiled(false);
    const t = setTimeout(()=>{ setCompiling(false); setCompiled(true); }, 700);
    return () => clearTimeout(t);
  }, [nl]);

  const luaCode = useMemoP(()=>generateLua(nl), [nl]);
  const sim = useMemoP(()=>simulate(simInput), [simInput]);

  return (
    <div className="protocol">
      <aside className="protocol-side">
        <div className="section-label" style={{padding:"14px 16px 8px"}}>Protocols</div>
        <div className="proto-list">
          {protocols.map(pr => (
            <button key={pr.id} className={`proto-item ${activeId===pr.id?"active":""}`} onClick={()=>setActiveId(pr.id)}>
              <div className="proto-item-top">
                <span className="proto-item-name">{pr.name}</span>
                {pr.live
                  ? <span className="pill stable" style={{padding:"2px 6px", fontSize:10}}><span className="pill-dot"/>Live</span>
                  : <span className="pill muted" style={{padding:"2px 6px", fontSize:10}}><span className="pill-dot"/>Draft</span>
                }
              </div>
              <div className="proto-item-sub">
                <span className="mono">{pr.id} · {pr.version}</span>
              </div>
              <div className="proto-item-meta">
                <span>{pr.patients} pts</span>
                <span className="dot">·</span>
                <span>{pr.fires7d} fires / 7d</span>
              </div>
            </button>
          ))}
        </div>
        <button className="btn btn-ghost proto-new">+ New protocol</button>
      </aside>

      <main className="protocol-main">
        <div className="protocol-header">
          <div>
            <div className="patient-meta">
              <span className="mono">DVT_Risk_Hip_v2</span>
              <span className="dot">·</span>
              <span>Owned by Dr. M. Smith</span>
              <span className="dot">·</span>
              <span>Applied to 14 patients</span>
            </div>
            <h2 className="page-title">DVT Risk — Hip Replacement</h2>
            <div className="protocol-subhead">
              <span className="pill accent"><span className="pill-dot"/>Editing {version}</span>
              <CompileStatus compiling={compiling} compiled={compiled}/>
              <span className="mono-tag"><Icon.Lock size={10}/> Signature required to publish</span>
            </div>
          </div>
          <div className="protocol-actions">
            <button className="btn btn-ghost">Discard changes</button>
            <button className="btn">Save draft</button>
            <button className="btn btn-primary">Publish v3 →</button>
          </div>
        </div>

        <div className="protocol-grid">
          <section className="card pc-nl">
            <header className="card-head">
              <div>
                <div className="section-label">Protocol canvas · natural language</div>
                <div className="logic-sub">
                  <span className="mono-tag"><Icon.Sparkle size={10}/> Drafted with claude-opus-4.5</span>
                </div>
              </div>
              <button className="btn btn-ghost btn-sm"><Icon.Sparkle size={12}/> Re-draft</button>
            </header>
            <textarea className="nl-input" value={nl} onChange={e=>setNl(e.target.value)} spellCheck={false}/>
            <div className="nl-help">
              <span className="section-label">Examples</span>
              <button className="chip" onClick={()=>setNl(DEFAULT_NL)}>DVT risk rule</button>
              <button className="chip" onClick={()=>setNl(SAMPLE_PAIN)}>Pain escalation</button>
              <button className="chip" onClick={()=>setNl(SAMPLE_FEVER)}>Fever watch</button>
            </div>
          </section>

          <section className="card pc-lua">
            <header className="card-head">
              <div>
                <div className="section-label">Generated Lua · deterministic</div>
                <div className="logic-sub">
                  <span className="mono-tag">protocols/DVT_Risk_Hip_v3.lua</span>
                  <span className="mono-tag">read-only</span>
                </div>
              </div>
              <button className="btn btn-ghost btn-sm">Edit raw Lua</button>
            </header>
            <pre className="code code-lua scroll"><code dangerouslySetInnerHTML={{__html: highlightLua(luaCode)}}/></pre>
            <div className="diff-strip">
              <span className="mono diff-add">+ 4 lines</span>
              <span className="mono diff-rem">− 1 line</span>
              <span className="mono diff-ctx">vs. v2 (live)</span>
              <button className="btn btn-ghost btn-sm" style={{marginLeft:"auto"}}>View diff →</button>
            </div>
          </section>

          <section className="card pc-sim">
            <header className="card-head">
              <div>
                <div className="section-label">Logic simulation</div>
                <div className="logic-sub">
                  <span className="mono-tag">test against synthetic patient</span>
                </div>
              </div>
              <button className="btn btn-ghost btn-sm">Load real case</button>
            </header>
            <div className="sim-grid">
              <div className="sim-inputs">
                <SimToggle label="calf_warmth" value={simInput.calf_warmth} onChange={v=>setSimInput({...simInput, calf_warmth:v})}/>
                <SimToggle label="calf_tenderness" value={simInput.calf_tenderness} onChange={v=>setSimInput({...simInput, calf_tenderness:v})}/>
                <SimSlider label="calf_pain_scale" min={0} max={10} value={simInput.calf_pain_scale} onChange={v=>setSimInput({...simInput, calf_pain_scale:v})}/>
                <SimToggle label="anticoag_taken_today_am" value={simInput.anticoag_taken_today_am} onChange={v=>setSimInput({...simInput, anticoag_taken_today_am:v})}/>
              </div>
              <div className="sim-result" data-sev={sim.severity}>
                <div className="sim-score">
                  <div className="sim-score-num mono">{sim.score.toFixed(2)}</div>
                  <div className="sim-score-label">risk score</div>
                </div>
                <div className="sim-meter">
                  <div className="sim-meter-track">
                    <div className="sim-meter-fill" style={{width:`${sim.score*100}%`}}/>
                    <div className="sim-meter-mark" style={{left:"40%"}}/>
                    <div className="sim-meter-mark crit" style={{left:"75%"}}/>
                  </div>
                  <div className="sim-meter-ticks">
                    <span>0.00</span><span>0.40 warn</span><span>0.75 critical</span><span>1.00</span>
                  </div>
                </div>
                <div className="sim-outcome">
                  <StatusPill status={sim.severity==="critical"?"critical":sim.severity==="warning"?"warning":"stable"}/>
                  <span className="sim-outcome-text">{sim.message}</span>
                </div>
                <div className="sim-trace mono">
                  {sim.steps.map((s,i)=>(
                    <div key={i} className="sim-trace-row">
                      <span className={`tick ${s.fired?"on":""}`}>{s.fired?"✓":"·"}</span>
                      <span className="sim-trace-label">{s.label}</span>
                      <span className="sim-trace-weight">{s.fired ? `+${s.weight.toFixed(2)}` : "—"}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
            <div className="sim-actions">
              <span className="section-label" style={{marginRight:"auto"}}>Tested against 28 historical cases · 26 ✓ / 2 ✗</span>
              <button className="btn btn-sm">Run full back-test</button>
            </div>
          </section>
        </div>
      </main>
    </div>
  );
}

function CompileStatus({ compiling, compiled }) {
  if (compiling) return <span className="pill muted"><span className="pill-dot" style={{background:"var(--warning)"}}/>Compiling Lua…</span>;
  if (compiled) return <span className="pill stable"><span className="pill-dot"/>Lua compiled · validated</span>;
  return null;
}

function SimToggle({ label, value, onChange }) {
  return (
    <div className="sim-input">
      <label className="mono">{label}</label>
      <div className="seg">
        <button className={value?"":"on"} onClick={()=>onChange(false)}>false</button>
        <button className={value?"on":""} onClick={()=>onChange(true)}>true</button>
      </div>
    </div>
  );
}

function SimSlider({ label, min, max, value, onChange }) {
  return (
    <div className="sim-input">
      <label className="mono">{label}<span className="mono sim-val">{value}</span></label>
      <input type="range" min={min} max={max} value={value} onChange={e=>onChange(+e.target.value)}/>
    </div>
  );
}

function simulate(input) {
  const steps = [
    { label:"calf_warmth == true", weight:0.35, fired: input.calf_warmth === true },
    { label:"calf_tenderness == true", weight:0.30, fired: input.calf_tenderness === true },
    { label:"calf_pain_scale ≥ 4", weight:0.15, fired: (input.calf_pain_scale||0) >= 4 },
    { label:"anticoag_taken_today_am == false", weight:0.20, fired: input.anticoag_taken_today_am === false }
  ];
  const score = steps.reduce((a,s)=>a+(s.fired?s.weight:0),0);
  let severity = "stable", message = "No action required.";
  if (score >= 0.75) { severity = "critical"; message = "Critical: possible DVT — page on-call within 30 min."; }
  else if (score >= 0.4) { severity = "warning"; message = "Warning: monitor & schedule follow-up call."; }
  return { steps, score, severity, message };
}

const DEFAULT_NL = `IF the patient reports their calf is warm OR tender (left or right),
AND the calf pain is at least 4 / 10,
AND they have not taken their AM anticoagulant,
THEN flag as Critical: Possible DVT.

Page the surgeon's on-call team within 30 minutes.
Advise the patient to elevate the leg and hold ambulation.

Otherwise, if any two of the above are true, mark as Warning
and schedule a follow-up call for later today.`;

const SAMPLE_PAIN = `IF self-reported pain is ≥ 7/10 for two consecutive check-ins,
OR pain has risen by 3+ points day-over-day,
THEN flag as Warning: Pain Escalation.

Notify the patient's primary care manager.`;

const SAMPLE_FEVER = `IF temperature ≥ 100.4 °F on any check-in within 7 days post-op,
OR ≥ 99.5 °F sustained across two check-ins,
THEN flag as Warning: Post-op Fever Watch and prompt wound photo.`;

function generateLua(nl) {
  // Faux "compiled" code, slightly responsive to NL content
  const mentionsPain = /pain/i.test(nl);
  const mentionsCalf = /calf|dvt/i.test(nl);
  const mentionsFever = /fever|temperature|°f/i.test(nl);

  if (mentionsFever && !mentionsCalf) {
    return `-- Post-op Fever Watch · generated from natural language
function evaluate(patient, today, history)
  local temp        = tonumber(today.temperature_f) or 0
  local prev_temp   = tonumber(history.temperature_f_prev) or 0

  if temp >= 100.4 then
    return Alert.new {
      severity = "warning",
      protocol = "Fever_Postop_v1",
      message  = "Post-op fever — request wound photo"
    }
  end

  if temp >= 99.5 and prev_temp >= 99.5 then
    return Alert.new {
      severity = "warning",
      protocol = "Fever_Postop_v1",
      message  = "Sustained low-grade fever"
    }
  end
end`;
  }

  if (mentionsPain && !mentionsCalf) {
    return `-- Pain Escalation · generated from natural language
function evaluate(patient, today, history)
  local pain        = tonumber(today.pain_scale) or 0
  local prev_pain   = tonumber(history.pain_scale_prev) or 0
  local d           = pain - prev_pain

  if pain >= 7 and prev_pain >= 7 then
    return Alert.new {
      severity = "warning",
      protocol = "Pain_Escalation_v3",
      message  = "Two-check-in pain >= 7"
    }
  end

  if d >= 3 then
    return Alert.new {
      severity = "warning",
      protocol = "Pain_Escalation_v3",
      message  = "Pain jumped " .. d .. " points"
    }
  end
end`;
  }

  return `-- DVT_Risk_Hip_v3 (draft) · generated from natural language
-- Source: protocols/DVT_Risk_Hip_v3.nl  · Compiled at 08:51:02

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
      severity = "critical",
      protocol = "DVT_Risk_Hip_v3",
      page     = patient.surgeon_oncall,
      sla_min  = 30,
      advice   = "Elevate leg, hold ambulation"
    }
  elseif risk >= 0.4 then
    return Alert.new {
      severity = "warning",
      protocol = "DVT_Risk_Hip_v3",
      followup_min = 240
    }
  end
end`;
}

function highlightLua(src) {
  const esc = (s) => s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
  // Tokenize then render — avoids regex collisions when spans contain quotes/brackets.
  const tokens = [];
  const patterns = [
    [/--[^\n]*/g,                            "c-comment"],
    [/"(?:\\.|[^"\\])*"/g,                   "c-string"],
    [/\b(?:function|local|if|then|elseif|else|end|return|true|false|nil|and|or|not)\b/g, "c-kw"],
    [/\b\d+(?:\.\d+)?\b/g,                   "c-num"],
    [/\bAlert\b/g,                           "c-type"]
  ];
  patterns.forEach(([re, cls]) => {
    let m;
    while ((m = re.exec(src)) !== null) {
      tokens.push({ s: m.index, e: m.index + m[0].length, text: m[0], cls });
    }
  });
  // Resolve overlaps — keep the earliest, longest token starting at each position.
  tokens.sort((a, b) => a.s - b.s || (b.e - b.s) - (a.e - a.s));
  const kept = [];
  let cursor = 0;
  for (const t of tokens) {
    if (t.s < cursor) continue;
    kept.push(t);
    cursor = t.e;
  }
  let out = "";
  let i = 0;
  for (const t of kept) {
    out += esc(src.slice(i, t.s));
    out += `<span class="${t.cls}">${esc(t.text)}</span>`;
    i = t.e;
  }
  out += esc(src.slice(i));
  return out;
}

window.ProtocolBuilder = ProtocolBuilder;
