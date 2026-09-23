select
    {{ pseudonymize('encounter_id') }} as encounter_key,
    {{ pseudonymize('patient_id') }}   as patient_key,
    encounter_class,
    encounter_type,
    reason,
    extract(year from started_at)::int as encounter_year,
    duration_minutes
from {{ ref('fct_encounters') }}
