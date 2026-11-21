{#
    Deterministic surrogate key: an MD5 hash of the natural key columns.
    Same input always gives the same key, so dimensions and facts can be rebuilt
    independently and still join. (Same idea as dbt_utils.generate_surrogate_key,
    written here to keep the project free of package dependencies.)
#}
{% macro surrogate_key(columns) -%}
    md5(
        {%- for col in columns %}
        coalesce(cast({{ col }} as varchar), '_null_')
        {%- if not loop.last %} || '|' || {% endif %}
        {%- endfor %}
    )
{%- endmacro %}
