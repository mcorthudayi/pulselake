select source_count, deid_count
from (select count(*) as source_count from {{ ref('dim_patients') }}) s
cross join (select count(*) as deid_count from {{ ref('deid_patients') }}) d
where source_count <> deid_count
