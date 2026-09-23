import { useState } from 'react'
import type { Role, Session } from './api'
import Login from './Login'
import ClinicianView from './ClinicianView'
import AnalystView from './AnalystView'
import AuditorView from './AuditorView'

const LABELS: Record<Role, string> = {
  clinician: 'Clinical records',
  analyst: 'Population analytics',
  auditor: 'Access audit'
}

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [tab, setTab] = useState<Role | null>(null)

  if (!session) {
    return (
      <Login
        onLogin={next => {
          setSession(next)
          setTab(next.roles[0] ?? null)
        }}
      />
    )
  }

  const signOut = () => {
    setSession(null)
    setTab(null)
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="pulse">●</span> PulseLake
        </div>
        <nav className="tabs">
          {session.roles.map(role => (
            <button key={role} className={role === tab ? 'tab active' : 'tab'} onClick={() => setTab(role)}>
              {LABELS[role]}
            </button>
          ))}
        </nav>
        <div className="user">
          <span>
            {session.name} · {session.roles.join(', ')}
          </span>
          <button className="ghost" onClick={signOut}>
            Sign out
          </button>
        </div>
      </header>
      <main className="content">
        {tab === 'clinician' && <ClinicianView session={session} />}
        {tab === 'analyst' && <AnalystView session={session} />}
        {tab === 'auditor' && <AuditorView session={session} />}
      </main>
      <footer className="footer">Synthetic data only · Every request is recorded in an append-only audit log</footer>
    </div>
  )
}
