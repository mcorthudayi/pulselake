select
    observation_id,
    patient_id,
    encounter_id,
    status,
    category,
    code_system,
    observation_code,
    observation_name,
    value_numeric,
    value_unit,
    value_text,
    component_count,
    observed_at,
    issued_at
from {{ ref('stg_fhir__observations') }}
