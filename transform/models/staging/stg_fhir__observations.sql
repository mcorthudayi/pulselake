with source as (
    select resource
    from {{ source('raw', 'fhir_resources') }}
    where resource_type = 'Observation'
)

select
    resource->>'id'                                                 as observation_id,
    {{ fhir_ref_id("resource->'subject'->>'reference'") }}          as patient_id,
    {{ fhir_ref_id("resource->'encounter'->>'reference'") }}        as encounter_id,
    resource->>'status'                                             as status,
    resource->'category'->0->'coding'->0->>'code'                   as category,
    resource->'code'->'coding'->0->>'system'                        as code_system,
    resource->'code'->'coding'->0->>'code'                          as observation_code,
    coalesce(
        resource->'code'->>'text',
        resource->'code'->'coding'->0->>'display'
    )                                                               as observation_name,
    (resource->'valueQuantity'->>'value')::numeric                  as value_numeric,
    resource->'valueQuantity'->>'unit'                              as value_unit,
    coalesce(
        resource->'valueCodeableConcept'->>'text',
        resource->'valueCodeableConcept'->'coding'->0->>'display',
        resource->>'valueString'
    )                                                               as value_text,
    jsonb_array_length(coalesce(resource->'component', '[]'::jsonb)) as component_count,
    (resource->>'effectiveDateTime')::timestamptz                   as observed_at,
    (resource->>'issued')::timestamptz                              as issued_at
from source
