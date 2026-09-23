import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { apiGet, errorMessage, type Session } from './api'

interface AuditEntry {
  id: number
  occurredAt: string
  userName: string | null
  roles: string | null
  method: string
  path: string
  queryString: string | null
  resourceType: string | null
  resourceId: string | null
  statusCode: number
  durationMs: number
}

const statusClass = (code: number) => (code < 300 ? 'ok' : code < 500 ? 'warn' : 'err')

export default function AuditorView({ session }: { session: Session }) {
  const [entries, setEntries] = useState<AuditEntry[]>([])
  const [user, setUser] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(
    async (filter: string) => {
      setLoading(true)
      setError(null)
      try {
        const params = new URLSearchParams({ limit: '200' })
        if (filter.trim()) params.set('user', filter.trim())
        setEntries(await apiGet<AuditEntry[]>(session, `/audit/access-log?${params}`))
      } catch (err) {
        setError(errorMessage(err))
      } finally {
        setLoading(false)
      }
    },
    [session]
  )

  useEffect(() => {
    void load('')
  }, [load])

  const onSubmit = (event: FormEvent) => {
    event.preventDefault()
    void load(user)
  }

  const denied = entries.filter(entry => entry.statusCode === 401 || entry.statusCode === 403).length
  const users = new Set(entries.map(entry => entry.userName).filter(Boolean)).size
  const avgLatency = entries.length
    ? Math.round(entries.reduce((sum, entry) => sum + entry.durationMs, 0) / entries.length)
    : 0

  return (
    <div className="stack">
      <div className="stats">
        <div className="stat">
          <span className="muted">Requests shown</span>
          <strong>{entries.length}</strong>
        </div>
        <div className="stat">
          <span className="muted">Denied (401/403)</span>
          <strong>{denied}</strong>
        </div>
        <div className="stat">
          <span className="muted">Distinct users</span>
          <strong>{users}</strong>
        </div>
        <div className="stat">
          <span className="muted">Avg latency</span>
          <strong>{avgLatency} ms</strong>
        </div>
      </div>

      <section className="card">
        <form className="toolbar" onSubmit={onSubmit}>
          <input
            className="grow"
            placeholder="Filter by user, e.g. dr.grey"
            value={user}
            onChange={event => setUser(event.target.value)}
          />
          <button type="submit">Apply</button>
          <button type="button" className="ghost" onClick={() => void load(user)}>
            Refresh
          </button>
          {loading && <span className="muted">Loading…</span>}
        </form>
        {error && <p className="error">{error}</p>}
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>User</th>
                <th>Roles</th>
                <th>Request</th>
                <th>Resource</th>
                <th>Status</th>
                <th>ms</th>
              </tr>
            </thead>
            <tbody>
              {entries.map(entry => (
                <tr key={entry.id}>
                  <td>{new Date(entry.occurredAt).toLocaleString('en-GB')}</td>
                  <td>{entry.userName ?? 'anonymous'}</td>
                  <td>{entry.roles || '—'}</td>
                  <td>
                    <code>
                      {entry.method} {entry.path}
                      {entry.queryString ?? ''}
                    </code>
                  </td>
                  <td>
                    {entry.resourceType
                      ? `${entry.resourceType}${entry.resourceId ? '/' + entry.resourceId.slice(0, 8) + '…' : ''}`
                      : '—'}
                  </td>
                  <td>
                    <span className={`badge ${statusClass(entry.statusCode)}`}>{entry.statusCode}</span>
                  </td>
                  <td>{entry.durationMs}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}
