{#
    GOLD fact: sensor readings. Grain: one row per reading.
    Foreign keys point to dim_machine and dim_product_type. reading_id is kept as a
    degenerate dimension (an identifier with no attributes of its own).
#}

select
    r.reading_id,
    {{ surrogate_key(['r.product_id']) }}           as machine_key,
    {{ surrogate_key(['r.product_type_code']) }}    as product_type_key,

    -- measures
    r.air_temp_k,
    r.process_temp_k,
    r.temp_diff_k,
    r.rotational_speed_rpm,
    r.torque_nm,
    r.power_w,
    r.tool_wear_min,
    r.overstrain_min_nm,
    r.tool_wear_band,

    -- outcome
    r.is_machine_failure,
    r.failure_mode_count,
    r.failure_class

from {{ ref('slv_sensor_readings') }} as r
