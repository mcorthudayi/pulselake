select table_name, column_name
from information_schema.columns
where table_schema = '{{ ref("deid_patients").schema }}'
  and table_name in (
      '{{ ref("deid_patients").identifier }}',
      '{{ ref("deid_encounters").identifier }}',
      '{{ ref("deid_conditions").identifier }}'
  )
  and column_name in (
      'patient_id', 'encounter_id', 'condition_id',
      'given_name', 'family_name', 'full_name', 'practitioner_name',
      'birth_date', 'deceased_at', 'address', 'city', 'postal_code',
      'ssn', 'phone', 'email'
  )
