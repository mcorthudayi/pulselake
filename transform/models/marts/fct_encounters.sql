select
    encounter_id,
    patient_id,
    status,
    encounter_class,
    encounter_type,
    encounter_type_code,
    reason,
    service_provider,
    practitioner_name,
    started_at,
    ended_at,
    started_at::date as encounter_date,
    round(extract(epoch from (ended_at - started_at)) / 60.0, 1) as duration_minutes
from {{ ref('stg_fhir__encounters') }}
