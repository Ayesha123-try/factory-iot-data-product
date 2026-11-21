{#
    KPI: failure rate by tool wear band. Grain: one row per 50-minute tool wear band.
    Answers "when should a tool be replaced?" - the point where risk starts to climb.
#}

select
    tool_wear_band,
    cast(count(*) as bigint)                                               as readings,
    {{ count_if_true('is_machine_failure') }}                              as failures,
    {{ failure_rate_pct(count_if_true('is_machine_failure'), 'count(*)') }} as failure_rate_pct,
    cast(round(avg(torque_nm), 2) as double)                               as avg_torque_nm
from {{ ref('fct_sensor_readings') }}
group by tool_wear_band
order by tool_wear_band
