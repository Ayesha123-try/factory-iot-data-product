{{ config(severity='warn') }}

{#
    DATA QUALITY (warning). Recomputes the documented physics rules from the raw sensors and
    compares them to the labels. Returns readings where a rule fired but the label is missing,
    or a label is present but the rule did not fire.
#}

select
    reading_id,
    case
        when hdf_rule_triggered != has_hdf then 'HDF'
        when pwf_rule_triggered != has_pwf then 'PWF'
        when osf_rule_triggered != has_osf then 'OSF'
    end as mismatched_mode
from {{ ref('slv_sensor_readings') }}
where hdf_rule_triggered != has_hdf
   or pwf_rule_triggered != has_pwf
   or osf_rule_triggered != has_osf
