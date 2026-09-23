with source as (
    select resource
    from {{ source('raw', 'fhir_resources') }}
    where resource_type = 'Patient'
)

select
    resource->>'id'                                   as patient_id,
    resource->'name'->0->'given'->>0                  as given_name,
    resource->'name'->0->>'family'                    as family_name,
    resource->>'gender'                               as gender,
    (resource->>'birthDate')::date                    as birth_date,
    (resource->>'deceasedDateTime')::timestamptz      as deceased_at,
    coalesce(
        resource->'maritalStatus'->>'text',
        resource->'maritalStatus'->'coding'->0->>'code'
    )                                                 as marital_status,
    resource->'address'->0->>'city'                   as city,
    resource->'address'->0->>'state'                  as state,
    resource->'address'->0->>'postalCode'             as postal_code,
    resource->'communication'->0->'language'->>'text' as language
from source
