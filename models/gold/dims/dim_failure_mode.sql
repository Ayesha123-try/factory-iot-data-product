{# GOLD dimension: failure mode. Grain: one row per failure mode (TWF, HDF, PWF, OSF, RNF, UNK). #}

select
    {{ surrogate_key(['failure_mode_code']) }}   as failure_mode_key,
    failure_mode_code,
    failure_mode_name,
    failure_mode_category,
    trigger_rule
from {{ ref('ref_failure_modes') }}
