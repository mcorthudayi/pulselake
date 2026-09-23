with source as (
    select resource
    from {{ source('raw', 'fhir_resources') }}
    where resource_type = 'Condition'
)

select
    resource->>'id'                                                 as condition_id,
    {{ fhir_ref_id("resource->'subject'->>'reference'") }}          as patient_id,
    {{ fhir_ref_id("resource->'encounter'->>'reference'") }}        as encounter_id,
    resource->'code'->'coding'->0->>'system'                        as code_system,
    resource->'code'->'coding'->0->>'code'                          as condition_code,
    coalesce(
        resource->'code'->>'text',
        resource->'code'->'coding'->0->>'display'
    )                                                               as condition_name,
    resource->'clinicalStatus'->'coding'->0->>'code'                as clinical_status,
    resource->'verificationStatus'->'coding'->0->>'code'            as verification_status,
    resource->'category'->0->'coding'->0->>'code'                   as category,
    (resource->>'onsetDateTime')::timestamptz                       as onset_at,
    (resource->>'abatementDateTime')::timestamptz                   as abated_at,
    (resource->>'recordedDate')::timestamptz                        as recorded_at
from source
