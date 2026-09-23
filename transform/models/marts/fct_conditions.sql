select
    condition_id,
    patient_id,
    encounter_id,
    code_system,
    condition_code,
    condition_name,
    clinical_status,
    clinical_status = 'active' as is_active,
    verification_status,
    category,
    onset_at,
    abated_at,
    recorded_at
from {{ ref('stg_fhir__conditions') }}
