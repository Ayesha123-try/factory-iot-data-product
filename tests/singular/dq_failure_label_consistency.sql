{{ config(severity='warn') }}

{#
    DATA QUALITY (warning, not error).
    Flags readings whose labels contradict each other:
      - failure_without_mode : machine_failure = 1 but no failure mode flag
      - mode_without_failure : a failure mode flag = 1 but machine_failure = 0
    These are known quirks of the public dataset. We keep the rows (they are real source data),
    classify them in silver, and surface them here so they are visible on every build.
#}

select reading_id, product_id, failure_class
from {{ ref('slv_sensor_readings') }}
where failure_class in ('failure_without_mode', 'mode_without_failure')
