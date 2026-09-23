import { useState, type FormEvent } from 'react'
import { errorMessage, parseToken, type Session } from './api'

export default function Login({ onLogin }: { onLogin: (session: Session) => void }) {
  const [token, setToken] = useState('')
  const [error, setError] = useState<string | null>(null)

  const submit = (event: FormEvent) => {
    event.preventDefault()
    try {
      const session = parseToken(token)
      if (session.roles.length === 0) throw new Error('This token has no PulseLake role.')
      onLogin(session)
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <div className="login">
      <form className="card login-card" onSubmit={submit}>
        <div className="brand">
          <span className="pulse">●</span> PulseLake
        </div>
        <p className="muted">
          FHIR health data portal. Paste a JWT issued for the clinician, analyst or auditor role.
        </p>
        <textarea
          value={token}
          onChange={event => setToken(event.target.value)}
          placeholder="eyJhbGciOi..."
          rows={5}
          spellCheck={false}
          autoComplete="off"
        />
        {error && <p className="error">{error}</p>}
        <button type="submit" disabled={!token.trim()}>
          Sign in
        </button>
        <p className="hint">The token is kept in memory only and is discarded when the page is refreshed.</p>
      </form>
    </div>
  )
}
