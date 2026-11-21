{#
    Standardised KPI formulas.
    Every KPI model calls these macros instead of writing its own arithmetic, so
    "failure rate" means exactly the same thing in every table that reports it.
#}

{# Failure rate in percent, rounded to 2 decimals. Safe against divide-by-zero. #}
{% macro failure_rate_pct(failures, readings) -%}
    cast(round(100.0 * ({{ failures }}) / nullif(({{ readings }}), 0), 2) as double)
{%- endmacro %}

{# Events per 1,000 readings, used where percentages get too small to read. #}
{% macro rate_per_1000(events, readings) -%}
    cast(round(1000.0 * ({{ events }}) / nullif(({{ readings }}), 0), 2) as double)
{%- endmacro %}

{# Share of a part in a whole, in percent. #}
{% macro share_pct(part, whole) -%}
    cast(round(100.0 * ({{ part }}) / nullif(({{ whole }}), 0), 2) as double)
{%- endmacro %}

{# Count rows where a boolean expression is true, returned as BIGINT (DuckDB sums to HUGEINT otherwise). #}
{% macro count_if_true(condition) -%}
    cast(sum(case when {{ condition }} then 1 else 0 end) as bigint)
{%- endmacro %}
