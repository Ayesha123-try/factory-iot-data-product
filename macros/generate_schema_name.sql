{#
    By default dbt prefixes custom schemas with the target schema (main_bronze, main_silver...).
    This override uses the layer name as-is, so the warehouse has clean schemas:
    raw, bronze, silver, gold.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
