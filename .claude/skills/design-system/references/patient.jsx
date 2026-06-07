// Patient mid-call screen — iOS frame
const { useState: useStateC, useEffect: useEffectC } = React;

function PatientCall() {
  const [phase, setPhase] = useStateC("listening"); // listening | thinking | responding
  const [transcript, setTranscript] = useStateC("Um… I'm okay, but my left calf is really warm and tender. I haven't taken my blood thinners yet today.");
  const [elapsed, setElapsed] = useStateC(34);

  useEffectC(() => {
    const t = setInterval(()=>setElapsed(e=>e+1), 1000);
    return ()=>clearInterval(t);
  }, []);

  // cycle phases for demo
  useEffectC(() => {
    const cycle = [
      { phase: "listening", dur: 6000 },
      { phase: "thinking",  dur: 2200 },
      { phase: "responding", dur: 5000 },
    ];
    let i = 0;
    const run = () => {
      setPhase(cycle[i].phase);
      const t = setTimeout(()=>{ i = (i+1) % cycle.length; run(); }, cycle[i].dur);
      return t;
    };
    const tid = run();
    return () => clearTimeout(tid);
  }, []);

  return (
    <div className="patient-stage">
      <div className="patient-stage-side">
        <div className="section-label">Patient view · what Paul sees during his daily check-in</div>
        <h2 className="page-title">Daily check-in · Voice-first</h2>
        <p className="patient-stage-copy">
          The voice interface is intentionally minimal — one ring, one prompt, one tap. The same call is shown to the right in three live phases. Whisper transcribes, the LLM extracts variables, and Lua decides the outcome.
        </p>
        <div className="phase-legend">
          <div className={`phase ${phase==="listening"?"on":""}`}>
            <span className="phase-dot"/>
            <div>
              <div className="phase-name">1 · Listening</div>
              <div className="phase-desc">Pulsing ring. Tolerates pauses and disfluencies.</div>
            </div>
          </div>
          <div className={`phase ${phase==="thinking"?"on":""}`}>
            <span className="phase-dot"/>
            <div>
              <div className="phase-name">2 · Processing</div>
              <div className="phase-desc">LLM extracts variables, Lua evaluates protocols.</div>
            </div>
          </div>
          <div className={`phase ${phase==="responding"?"on":""}`}>
            <span className="phase-dot"/>
            <div>
              <div className="phase-name">3 · Responding</div>
              <div className="phase-desc">Empathetic spoken response with clear next step.</div>
            </div>
          </div>
        </div>
      </div>

      <IOSDevice width={380} height={780}>
        <div className="phone-screen" data-phase={phase}>
          <div className="ps-top">
            <div className="ps-brand">
              <BrandMark size={20}/>
              <span>PostOpGuard</span>
            </div>
            <button className="ps-end"><Icon.X size={16}/></button>
          </div>

          <div className="ps-meta">
            <div className="ps-meta-label">Daily check-in · post-op day 4</div>
            <div className="ps-meta-time mono">{fmtTime(elapsed)}</div>
          </div>

          <div className="ps-orb-wrap">
            <Orb phase={phase}/>
          </div>

          <div className="ps-prompt">
            {phase === "listening" && (
              <>
                <div className="ps-cue">I&apos;m listening…</div>
                <div className="ps-sub">Take your time. Press to pause.</div>
              </>
            )}
            {phase === "thinking" && (
              <>
                <div className="ps-cue">Got it — checking with the team…</div>
                <div className="ps-sub">One moment, Paul.</div>
              </>
            )}
            {phase === "responding" && (
              <>
                <div className="ps-cue">Notifying Dr. Smith&apos;s team.</div>
                <div className="ps-sub">Please keep your leg elevated until they call.</div>
              </>
            )}
          </div>

          {phase !== "thinking" && (
            <div className="ps-caption">
              <div className="ps-caption-label">{phase==="listening"?"You said":"PostOpGuard said"}</div>
              <div className="ps-caption-text">{phase==="listening" ? transcript : `I've noted the calf warmth — that's important. I'm paging Dr. Smith's on-call team. They will call you within 30 minutes. Keep your leg elevated and stay seated.`}</div>
            </div>
          )}

          <div className="ps-actions">
            <button className="ps-btn ghost"><Icon.Mic/> Mute</button>
            <button className="ps-btn primary"><Icon.Phone size={14}/> End call</button>
            <button className="ps-btn ghost">Text instead</button>
          </div>

          <div className="ps-footer">
            <Icon.Lock size={10}/>
            <span>Encrypted · HIPAA · stored under MRN-48201</span>
          </div>
        </div>
      </IOSDevice>
    </div>
  );
}

function Orb({ phase }) {
  // Concentric pulsing ring; bars when responding
  return (
    <div className="orb" data-phase={phase}>
      <span className="orb-halo h1"/>
      <span className="orb-halo h2"/>
      <span className="orb-halo h3"/>
      <span className="orb-core"/>
      <span className="orb-mic"><Icon.Mic size={24}/></span>
    </div>
  );
}

function fmtTime(s) {
  const m = Math.floor(s/60), r = s%60;
  return `${m}:${String(r).padStart(2,"0")}`;
}

window.PatientCall = PatientCall;
