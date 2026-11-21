{# Generic test: the combination of the given columns must be unique (the model's grain). #}
{% test unique_combination(model, columns) %}

select {{ columns | join(', ') }}, count(*) as n
from {{ model }}
group by {{ columns | join(', ') }}
having count(*) > 1

{% endtest %}
