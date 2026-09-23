select
    {{ pseudonymize('patient_id') }} as patient_key,
    gender,
    case when age_years >= 90 then null else extract(year from birth_date)::int end as birth_year,
    case
        when age_years < 18 then '0-17'
        when age_years < 35 then '18-34'
        when age_years < 50 then '35-49'
        when age_years < 65 then '50-64'
        when age_years < 90 then '65-89'
        else '90+'
    end as age_band,
    is_deceased,
    case when is_deceased and age_years < 90 then extract(year from deceased_at)::int end as deceased_year,
    state,
    left(postal_code, 3) as zip3
from {{ ref('dim_patients') }}
