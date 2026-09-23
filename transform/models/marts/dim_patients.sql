select
    patient_id,
    given_name,
    family_name,
    gender,
    birth_date,
    deceased_at,
    deceased_at is not null as is_deceased,
    date_part('year', age(coalesce(deceased_at::date, current_date), birth_date))::int as age_years,
    marital_status,
    city,
    state,
    postal_code,
    language
from {{ ref('stg_fhir__patients') }}
