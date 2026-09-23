import { useEffect, useMemo, useState } from 'react'
import { apiGet, errorMessage, type Session } from './api'

interface ConditionStat {
  conditionName: string | null
  patients: number
  occurrences: number
}

interface TopConditions {
  minCellSize: number
  conditions: ConditionStat[]
}

interface DeidPatient {
  patientKey: string
  gender: string | null
  birthYear: number | null
  ageBand: string
  isDeceased: boolean
  state: string | null
  zip3: string | null
}

const AGE_BANDS = ['0-17', '18-34', '35-49', '50-64', '65-89', '90+']

export default function AnalystView({ session }: { session: Session }) {
  const [top, setTop] = useState<TopConditions | null>(null)
  const [patients, setPatients] = useState<DeidPatient[]>([])
  const [band, setBand] = useState('')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    Promise.all([
      apiGet<TopConditions>(session, '/deid/stats/top-conditions?limit=12'),
      apiGet<DeidPatient[]>(session, '/deid/patients?limit=500')
    ])
      .then(([stats, rows]) => {
        if (cancelled) return
        setTop(stats)
        setPatients(rows)
      })
      .catch(err => {
        if (!cancelled) setError(errorMessage(err))
      })
    return () => {
      cancelled = true
    }
  }, [session])

  const distribution = useMemo(
    () => AGE_BANDS.map(ageBand => ({ ageBand, count: patients.filter(p => p.ageBand === ageBand).length })),
    [patients]
  )

  const maxBand = Math.max(1, ...distribution.map(item => item.count))
  const maxCondition = Math.max(1, ...(top?.conditions.map(item => item.patients) ?? []))
  const filtered = band ? patients.filter(p => p.ageBand === band) : patients
  const female = patients.filter(p => p.gender === 'female').length
  const male = patients.filter(p => p.gender === 'male').length
  const deceased = patients.filter(p => p.isDeceased).length

  return (
    <div className="stack">
      {error && <p className="error">{error}</p>}

      <div className="stats">
        <div className="stat">
          <span className="muted">Patients</span>
          <strong>{patients.length}</strong>
        </div>
        <div className="stat">
          <span className="muted">Female / Male</span>
          <strong>
            {female} / {male}
          </strong>
        </div>
        <div className="stat">
          <span className="muted">Deceased</span>
          <strong>{deceased}</strong>
        </div>
        <div className="stat">
          <span className="muted">Min cell size</span>
          <strong>{top?.minCellSize ?? '—'}</strong>
        </div>
      </div>

      <div className="grid-2">
        <section className="card">
          <h2>Top conditions</h2>
          <p className="muted">
            Distinct patients per condition. Groups under {top?.minCellSize ?? 5} patients are suppressed.
          </p>
          <div className="bars">
            {top?.conditions.map(item => (
              <div className="bar" key={item.conditionName ?? 'unknown'}>
                <span className="ellipsis" title={item.conditionName ?? ''}>
                  {item.conditionName ?? 'Unknown'}
                </span>
                <div className="bar-track">
                  <div className="bar-fill" style={{ width: `${(item.patients / maxCondition) * 100}%` }} />
                </div>
                <strong>{item.patients}</strong>
              </div>
            ))}
          </div>
        </section>

        <section className="card">
          <h2>Age distribution</h2>
          <p className="muted">De-identified age bands. Ages 90+ are grouped and birth year is withheld.</p>
          <div className="bars">
            {distribution.map(item => (
              <div className="bar" key={item.ageBand}>
                <span>{item.ageBand}</span>
                <div className="bar-track">
                  <div className="bar-fill" style={{ width: `${(item.count / maxBand) * 100}%` }} />
                </div>
                <strong>{item.count}</strong>
              </div>
            ))}
          </div>
        </section>
      </div>

      <section className="card">
        <div className="toolbar">
          <h2 className="grow">De-identified patients</h2>
          <select value={band} onChange={event => setBand(event.target.value)}>
            <option value="">All age bands</option>
            {AGE_BANDS.map(ageBand => (
              <option key={ageBand} value={ageBand}>
                {ageBand}
              </option>
            ))}
          </select>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Patient key</th>
                <th>Gender</th>
                <th>Birth year</th>
                <th>Age band</th>
                <th>State</th>
                <th>ZIP3</th>
                <th>Deceased</th>
              </tr>
            </thead>
            <tbody>
              {filtered.slice(0, 50).map(p => (
                <tr key={p.patientKey}>
                  <td>
                    <code>{p.patientKey.slice(0, 16)}…</code>
                  </td>
                  <td>{p.gender ?? '—'}</td>
                  <td>{p.birthYear ?? '—'}</td>
                  <td>{p.ageBand}</td>
                  <td>{p.state ?? '—'}</td>
                  <td>{p.zip3 ?? '—'}</td>
                  <td>{p.isDeceased ? 'Yes' : 'No'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}
