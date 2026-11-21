{#
    Every failed reading must appear at least once in fct_failure_events
    (with a real mode, or with UNK). Otherwise mode breakdowns would under-count failures.
#}

select f.reading_id
from {{ ref('fct_sensor_readings') }} as f
left join {{ ref('fct_failure_events') }} as e
    on f.reading_id = e.reading_id
where f.is_machine_failure
  and e.reading_id is null
