{% macro fhir_ref_id(column) -%}
    regexp_replace({{ column }}, '^(urn:uuid:|[A-Za-z]+/)', '')
{%- endmacro %}

{% macro pseudonymize(column) -%}
    encode(sha256(convert_to((select salt from {{ source('security', 'deid_config') }}) || ':' || {{ column }}::text, 'UTF8')), 'hex')
{%- endmacro %}
