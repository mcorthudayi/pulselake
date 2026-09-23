with source as (
    select resource
    from {{ source('raw', 'fhir_resources') }}
    where resource_type = 'Encounter'
)

select
    resource->>'id'                                                 as encounter_id,
    {{ fhir_ref_id("resource->'subject'->>'reference'") }}          as patient_id,
    resource->>'status'                                             as status,
    resource->'class'->>'code'                                      as encounter_class,
    resource->'type'->0->>'text'                                    as encounter_type,
    resource->'type'->0->'coding'->0->>'code'                       as encounter_type_code,
    resource->'reasonCode'->0->'coding'->0->>'display'              as reason,
    resource->'serviceProvider'->>'display'                         as service_provider,
    resource->'participant'->0->'individual'->>'display'            as practitioner_name,
    (resource->'period'->>'start')::timestamptz                     as started_at,
    (resource->'period'->>'end')::timestamptz                       as ended_at
from source
