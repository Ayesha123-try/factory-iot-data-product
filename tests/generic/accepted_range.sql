{#
    Generic test: every value of the column must be inside [min_value, max_value].
    Either bound can be left out. Returns the offending rows (a test passes when it returns 0 rows).
#}
{% test accepted_range(model, column_name, min_value=none, max_value=none) %}

select {{ column_name }}
from {{ model }}
where
    {%- if min_value is not none %} {{ column_name }} < {{ min_value }} {%- endif %}
    {%- if min_value is not none and max_value is not none %} or {%- endif %}
    {%- if max_value is not none %} {{ column_name }} > {{ max_value }} {%- endif %}

{% endtest %}
