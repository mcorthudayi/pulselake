import { useEffect, useState, type FormEvent } from 'react'
import {
  apiGet,
  byDateDesc,
  conceptText,
  entries,
  errorMessage,
  formatDate,
  observationValue,
  patientName,
  type Bundle,
  type Condition,
  type Encounter,
  type Observation,
  type Patient,
  type Session
} from './api'

export default function ClinicianView({ session }: { session: Session }) {
  const [query, setQuery] = useState('')
  const [patients, setPatients] = useState<Patient[]>([])
  const [selected, setSelected] = useState<Patient | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const search = async (name: string) => {
    setLoading(true)
    setError(null)
    try {
      const params = new URLSearchParams({ _count: '50' })
      if (name.trim()) params.set('name', name.trim())
      const bundle = await apiGet<Bundle<Patient>>(session, `/fhir/Patient?${params}`)
      setPatients(entries(bundle))
    } catch (err) {
      setError(errorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void search('')
  }, [session])

  const onSubmit = (event: FormEvent) => {
    event.preventDefault()
    void search(query)
  }

  return (
    <div className="split">
      <section className="card">
        <h2>Patients</h2>
        <form className="search" onSubmit={onSubmit}>
          <input value={query} onChange={event => setQuery(event.target.value)} placeholder="First or last name" />
          <button type="submit">Search</button>
        </form>
        {error && <p className="error">{error}</p>}
        {loading ? (
          <p className="muted">Loading…</p>
        ) : (
          <ul className="list">
            {patients.map(patient => (
              <li key={patient.id}>
                <button
                  className={selected?.id === patient.id ? 'row active' : 'row'}
                  onClick={() => setSelected(patient)}
                >
                  <span>{patientName(patient)}</span>
                  <span className="muted">
                    {patient.gender ?? '—'} · {patient.birthDate ?? '—'}
                  </span>
                </button>
              </li>
            ))}
            {patients.length === 0 && <li className="muted">No patients found.</li>}
          </ul>
        )}
      </section>
      <section className="card">
        {selected ? (
          <PatientRecord key={selected.id} session={session} patient={selected} />
        ) : (
          <p className="muted">Select a patient to open the clinical record.</p>
        )}
      </section>
    </div>
  )
}

function PatientRecord({ session, patient }: { session: Session; patient: Patient }) {
  const [conditions, setConditions] = useState<Condition[]>([])
  const [observations, setObservations] = useState<Observation[]>([])
  const [encounters, setEncounters] = useState<Encounter[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    const id = encodeURIComponent(patient.id)

    Promise.all([
      apiGet<Bundle<Condition>>(session, `/fhir/Condition?patient=${id}&_count=100`),
      apiGet<Bundle<Observation>>(session, `/fhir/Observation?patient=${id}&_count=100`),
      apiGet<Bundle<Encounter>>(session, `/fhir/Encounter?patient=${id}&_count=100`)
    ])
      .then(([conditionBundle, observationBundle, encounterBundle]) => {
        if (cancelled) return
        setConditions(entries(conditionBundle))
        setObservations(entries(observationBundle).sort(byDateDesc(item => item.effectiveDateTime)).slice(0, 15))
        setEncounters(entries(encounterBundle).sort(byDateDesc(item => item.period?.start)).slice(0, 10))
      })
      .catch(err => {
        if (!cancelled) setError(errorMessage(err))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => {
      cancelled = true
    }
  }, [session, patient.id])

  const active = conditions.filter(condition => condition.clinicalStatus?.coding?.[0]?.code === 'active')
  const address = patient.address?.[0]

  return (
    <div>
      <h2>{patientName(patient)}</h2>
      <div className="meta">
        <span>{patient.gender ?? '—'}</span>
        <span>Born {formatDate(patient.birthDate)}</span>
        {address && <span>{[address.city, address.state].filter(Boolean).join(', ')}</span>}
        {patient.deceasedDateTime && <span className="badge err">Deceased {formatDate(patient.deceasedDateTime)}</span>}
        <code className="muted">{patient.id}</code>
      </div>
      {error && <p className="error">{error}</p>}
      {loading ? (
        <p className="muted">Loading clinical record…</p>
      ) : (
        <>
          <h3>Active conditions ({active.length})</h3>
          <div className="chips">
            {active.map(condition => (
              <span className="chip" key={condition.id}>
                {conceptText(condition.code)}
              </span>
            ))}
            {active.length === 0 && <span className="muted">No active conditions.</span>}
          </div>

          <h3>Observations</h3>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Observation</th>
                  <th>Value</th>
                </tr>
              </thead>
              <tbody>
                {observations.map(observation => (
                  <tr key={observation.id}>
                    <td>{formatDate(observation.effectiveDateTime)}</td>
                    <td>{conceptText(observation.code)}</td>
                    <td>{observationValue(observation)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h3>Encounters</h3>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Class</th>
                  <th>Type</th>
                  <th>Provider</th>
                </tr>
              </thead>
              <tbody>
                {encounters.map(encounter => (
                  <tr key={encounter.id}>
                    <td>{formatDate(encounter.period?.start)}</td>
                    <td>{encounter.class?.code ?? '—'}</td>
                    <td>{conceptText(encounter.type?.[0])}</td>
                    <td>{encounter.serviceProvider?.display ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  )
}
