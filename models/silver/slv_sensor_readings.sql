{#
    SILVER: cleaned, typed and enriched readings. Grain: one row per sensor reading.
    - explicit types and trimmed / upper-cased codes
    - booleans instead of 0/1 integers
    - engineering features derived from physics (temperature delta, power, overstrain)
    - rule-based checks that recompute each failure condition from the raw sensors
    - a failure_class that exposes label inconsistencies instead of hiding them
#}

with bronze as (

    select * from {{ ref('brz_sensor_readings') }}

),

product_types as (

    select * from {{ ref('ref_product_types') }}

),

typed as (

    select
        cast(udi as integer)                              as reading_id,
        upper(trim(product_id))                           as product_id,
        upper(trim(product_type))                         as product_type_code,
        cast(substr(trim(product_id), 2) as integer)      as product_serial_number,

        cast(air_temperature_k as double)                 as air_temp_k,
        cast(process_temperature_k as double)             as process_temp_k,
        cast(rotational_speed_rpm as integer)             as rotational_speed_rpm,
        cast(torque_nm as double)                         as torque_nm,
        cast(tool_wear_min as integer)                    as tool_wear_min,

        machine_failure = 1                               as is_machine_failure,
        twf = 1                                           as has_twf,
        hdf = 1                                           as has_hdf,
        pwf = 1                                           as has_pwf,
        osf = 1                                           as has_osf,
        rnf = 1                                           as has_rnf,

        _source_file,
        _ingested_at

    from bronze

),

derived as (

    select
        typed.*,

        -- unit conversions
        round(air_temp_k - 273.15, 2)                                     as air_temp_c,
        round(process_temp_k - 273.15, 2)                                 as process_temp_c,

        -- physics-based features (these drive the failure rules in the dataset paper)
        round(process_temp_k - air_temp_k, 2)                             as temp_diff_k,
        round(torque_nm * rotational_speed_rpm * 2 * pi() / 60, 1)        as power_w,
        round(tool_wear_min * torque_nm, 1)                               as overstrain_min_nm,

        cast(has_twf as integer) + cast(has_hdf as integer) + cast(has_pwf as integer)
          + cast(has_osf as integer) + cast(has_rnf as integer)          as failure_mode_count,

        pt.overstrain_threshold_min_nm

    from typed
    left join product_types as pt
        on typed.product_type_code = pt.product_type_code

)

select
    reading_id,
    product_id,
    product_type_code,
    product_serial_number,

    air_temp_k,
    process_temp_k,
    air_temp_c,
    process_temp_c,
    temp_diff_k,
    rotational_speed_rpm,
    torque_nm,
    power_w,
    tool_wear_min,
    overstrain_min_nm,

    case
        when tool_wear_min < 50  then '000-049 min'
        when tool_wear_min < 100 then '050-099 min'
        when tool_wear_min < 150 then '100-149 min'
        when tool_wear_min < 200 then '150-199 min'
        else '200+ min'
    end                                                    as tool_wear_band,

    is_machine_failure,
    has_twf,
    has_hdf,
    has_pwf,
    has_osf,
    has_rnf,
    failure_mode_count,

    case
        when not is_machine_failure and failure_mode_count = 0 then 'no_failure'
        when is_machine_failure and failure_mode_count = 1     then 'single_mode_failure'
        when is_machine_failure and failure_mode_count > 1     then 'multi_mode_failure'
        when is_machine_failure and failure_mode_count = 0     then 'failure_without_mode'
        else 'mode_without_failure'
    end                                                    as failure_class,

    -- rule checks: would the documented physics rule have predicted this failure mode?
    (temp_diff_k < 8.6 and rotational_speed_rpm < 1380)    as hdf_rule_triggered,
    (power_w < 3500 or power_w > 9000)                     as pwf_rule_triggered,
    (overstrain_min_nm > overstrain_threshold_min_nm)      as osf_rule_triggered,

    _source_file,
    _ingested_at

from derived
