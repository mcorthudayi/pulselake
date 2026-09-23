export type Role = 'clinician' | 'analyst' | 'auditor'

export interface Session {
  token: string
  name: string
  roles: Role[]
}

export interface Coding {
  system?: string
  code?: string
  display?: string
}

export interface CodeableConcept {
  text?: string
  coding?: Coding[]
}

export interface Quantity {
  value?: number
  unit?: string
}

export interface Patient {
  id: string
  name?: { given?: string[]; family?: string }[]
  gender?: string
  birthDate?: string
  deceasedDateTime?: string
  address?: { city?: string; state?: string }[]
}

export interface Condition {
  id: string
  code?: CodeableConcept
  clinicalStatus?: CodeableConcept
  onsetDateTime?: string
}

export interface Observation {
  id: string
  code?: CodeableConcept
  valueQuantity?: Quantity
  valueCodeableConcept?: CodeableConcept
  valueString?: string
  component?: { code?: CodeableConcept; valueQuantity?: Quantity }[]
  effectiveDateTime?: string
}

export interface Encounter {
  id: string
  class?: Coding
  type?: CodeableConcept[]
  period?: { start?: string; end?: string }
  serviceProvider?: { display?: string }
}

export interface Bundle<T> {
  entry?: { resource: T }[]
}

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}

const ROLES: Role[] = ['clinician', 'analyst', 'auditor']
const ROLE_CLAIM = 'http://schemas.microsoft.com/ws/2008/06/identity/claims/role'

function decodeSegment(segment: string): Record<string, unknown> {
  const base64 = segment.replace(/-/g, '+').replace(/_/g, '/')
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4)
  const json = decodeURIComponent(
    Array.from(atob(padded), char => '%' + char.charCodeAt(0).toString(16).padStart(2, '0')).join('')
  )
  return JSON.parse(json) as Record<string, unknown>
}

export function parseToken(raw: string): Session {
  const token = raw.trim().replace(/^Bearer\s+/i, '')
  const parts = token.split('.')
  if (parts.length !== 3) throw new Error('This does not look like a JWT.')

  let payload: Record<string, unknown>
  try {
    payload = decodeSegment(parts[1])
  } catch {
    throw new Error('Token payload could not be decoded.')
  }

  if (typeof payload.exp === 'number' && payload.exp * 1000 < Date.now()) {
    throw new Error('Token has expired.')
  }

  const claim = payload.role ?? payload[ROLE_CLAIM]
  const values: unknown[] = Array.isArray(claim) ? claim : claim === undefined ? [] : [claim]
  const roles = ROLES.filter(role => values.includes(role))
  const name =
    typeof payload.unique_name === 'string'
      ? payload.unique_name
      : typeof payload.sub === 'string'
        ? payload.sub
        : 'unknown'

  return { token, name, roles }
}

export async function apiGet<T>(session: Session, path: string): Promise<T> {
  const response = await fetch(path, {
    headers: {
      Authorization: `Bearer ${session.token}`,
      Accept: 'application/json, application/fhir+json'
    }
  })

  if (!response.ok) {
    const message =
      response.status === 401
        ? 'Session is not authenticated. Sign in again.'
        : response.status === 403
          ? 'Access denied for your role.'
          : response.status === 429
            ? 'Rate limit exceeded. Try again in a minute.'
            : `Request failed (${response.status}).`
    throw new ApiError(response.status, message)
  }

  return (await response.json()) as T
}

export const errorMessage = (error: unknown) =>
  error instanceof Error ? error.message : 'Unexpected error.'

export const entries = <T>(bundle: Bundle<T>) => (bundle.entry ?? []).map(entry => entry.resource)

export const conceptText = (concept?: CodeableConcept) =>
  concept?.text ?? concept?.coding?.[0]?.display ?? concept?.coding?.[0]?.code ?? '—'

const cleanName = (value?: string) => (value ?? '').replace(/\d+/g, '')

export const patientName = (patient: Patient) => {
  const name = patient.name?.[0]
  return [cleanName(name?.given?.[0]), cleanName(name?.family)].filter(Boolean).join(' ') || patient.id
}

export const formatDate = (value?: string) =>
  value ? new Date(value).toLocaleDateString('en-GB') : '—'

export const byDateDesc =
  <T>(pick: (item: T) => string | undefined) =>
  (a: T, b: T) =>
    (pick(b) ?? '').localeCompare(pick(a) ?? '')

const round = (value: number) => Math.round(value * 100) / 100

export function observationValue(observation: Observation): string {
  if (observation.valueQuantity?.value !== undefined) {
    return `${round(observation.valueQuantity.value)} ${observation.valueQuantity.unit ?? ''}`.trim()
  }
  if (observation.valueCodeableConcept) return conceptText(observation.valueCodeableConcept)
  if (observation.valueString) return observation.valueString

  const values = (observation.component ?? [])
    .map(component => component.valueQuantity?.value)
    .filter((value): value is number => value !== undefined)

  if (values.length > 0) {
    return `${values.map(round).join(' / ')} ${observation.component?.[0]?.valueQuantity?.unit ?? ''}`.trim()
  }
  return '—'
}
