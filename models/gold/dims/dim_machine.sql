{#
    GOLD dimension: machine (the product unit identified by Product ID).
    Grain: one row per product_id. Built from the distinct product IDs seen in silver,
    so a new machine appearing in the data automatically gets a dimension row.
#}

with machines as (

    select distinct
        product_id,
        product_serial_number,
        product_type_code
    from {{ ref('slv_sensor_readings') }}

)

select
    {{ surrogate_key(['m.product_id']) }}            as machine_key,
    m.product_id,
    m.product_serial_number,
    m.product_type_code,
    pt.product_type_key,
    pt.quality_variant
from machines as m
left join {{ ref('dim_product_type') }} as pt
    on m.product_type_code = pt.product_type_code
