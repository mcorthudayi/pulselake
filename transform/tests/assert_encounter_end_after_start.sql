select encounter_id, started_at, ended_at
from {{ ref('fct_encounters') }}
where ended_at < started_at
