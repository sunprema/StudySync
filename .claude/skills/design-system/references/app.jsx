// PostOpGuard — main app
const { useState: useStateA, useEffect: useEffectA } = React;

const DEFAULTS = /*EDITMODE-BEGIN*/{
  "density": "comfortable",
  "alertTone": "traditional"
}/*EDITMODE-END*/;

function App() {
  const [tab, setTab] = useStateA("nurse"); // nurse | protocol | patient
  const [t, setTweak] = useTweaks(DEFAULTS);

  useEffectA(() => {
    document.documentElement.dataset.density = t.density;
    document.documentElement.dataset.tone = t.alertTone;
  }, [t.density, t.alertTone]);

  return (
    <div className="app">
      <TopBar tab={tab} setTab={setTab}/>
      <div className="app-body" data-screen-label={tabLabel(tab)}>
        {tab === "nurse" && <NurseDashboard/>}
        {tab === "protocol" && <ProtocolBuilder/>}
        {tab === "patient" && <PatientCall/>}
      </div>

      <TweaksPanel title="Tweaks">
        <TweakSection label="Display">
          <TweakRadio label="Density" value={t.density} options={[{value:"comfortable",label:"Comfortable"},{value:"compact",label:"Compact"}]} onChange={v=>setTweak("density", v)}/>
          <TweakRadio label="Alert tone" value={t.alertTone} options={[{value:"soft",label:"Soft"},{value:"traditional",label:"Traditional"}]} onChange={v=>setTweak("alertTone", v)}/>
        </TweakSection>
        <TweakSection label="Jump to">
          <TweakButton label="Nurse triage dashboard" onClick={()=>setTab("nurse")}/>
          <TweakButton label="Doctor protocol builder" onClick={()=>setTab("protocol")}/>
          <TweakButton label="Patient mid-call view" onClick={()=>setTab("patient")}/>
        </TweakSection>
      </TweaksPanel>
    </div>
  );
}

function tabLabel(tab) {
  return tab === "nurse" ? "01 Nurse Triage" : tab === "protocol" ? "02 Protocol Builder" : "03 Patient Call";
}

function TopBar({ tab, setTab }) {
  return (
    <header className="topbar">
      <div className="brand">
        <BrandMark size={26}/>
        <BrandWordmark size={15}/>
        <span className="mono-tag brand-sep">St Mary&apos;s · Orthopedics</span>
      </div>
      <nav className="nav">
        <button className={tab==="nurse"?"active":""} onClick={()=>setTab("nurse")}>Triage</button>
        <button className={tab==="protocol"?"active":""} onClick={()=>setTab("protocol")}>Protocols</button>
        <button className={tab==="patient"?"active":""} onClick={()=>setTab("patient")}>Patient view</button>
      </nav>
      <div className="topbar-right">
        <div className="sys-status">
          <span className="heartbeat-dot"/>
          <span>oban · all jobs green</span>
        </div>
        <div className="user-chip">
          <span className="user-avatar">NN</span>
          <span style={{fontSize:13}}>Nancy N. <span style={{color:"var(--muted)"}}>· Care Mgr</span></span>
        </div>
      </div>
    </header>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App/>);
