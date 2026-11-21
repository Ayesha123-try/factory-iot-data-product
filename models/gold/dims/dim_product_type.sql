{# GOLD dimension: product quality variant (L / M / H). Grain: one row per product type. #}

select
    {{ surrogate_key(['product_type_code']) }}   as product_type_key,
    product_type_code,
    quality_variant,
    documented_population_share_pct,
    tool_wear_increment_min,
    overstrain_threshold_min_nm
from {{ ref('ref_product_types') }}
