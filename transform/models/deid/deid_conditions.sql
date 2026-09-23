select
    {{ pseudonymize('condition_id') }} as condition_key,
    {{ pseudonymize('patient_id') }}   as patient_key,
    code_system,
    condition_code,
    condition_name,
    clinical_status,
    extract(year from onset_at)::int as onset_year
from {{ ref('fct_conditions') }}
