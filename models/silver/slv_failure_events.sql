{#
    SILVER: failure events. Grain: one row per (failed reading x failure mode).
    The raw data stores failure modes as five wide 0/1 columns, and a single failure
    can carry more than one mode. Unpivoting to a long table lets the gold layer count
    modes correctly without double counting failures.

    Only readings with machine_failure = 1 produce events. A failed reading that has no
    mode flag gets the mode 'UNK' so that every failure is accounted for.
#}

with failed as (

    select * from {{ ref('slv_sensor_readings') }}
    where is_machine_failure

),

events as (

    select reading_id, 'TWF' as failure_mode_code from failed where has_twf
    union all
    select reading_id, 'HDF' from failed where has_hdf
    union all
    select reading_id, 'PWF' from failed where has_pwf
    union all
    select reading_id, 'OSF' from failed where has_osf
    union all
    select reading_id, 'RNF' from failed where has_rnf
    union all
    select reading_id, 'UNK' from failed where failure_mode_count = 0

)

select
    reading_id,
    failure_mode_code
from events
