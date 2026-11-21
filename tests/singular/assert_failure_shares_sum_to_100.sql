{# Shares of failures and readings across product types must add up to 100% (allowing rounding). #}

select
    sum(share_of_failures_pct) as total_failure_share,
    sum(share_of_readings_pct) as total_reading_share
from {{ ref('kpi_failure_rate_by_product_type') }}
having abs(sum(share_of_failures_pct) - 100) > 0.05
    or abs(sum(share_of_readings_pct) - 100) > 0.05
