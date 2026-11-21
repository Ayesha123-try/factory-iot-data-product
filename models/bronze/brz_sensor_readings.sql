{#
    BRONZE: raw data, landed 1:1.
    - No filtering, no business logic, no type changes beyond what the loader set.
    - Only two things happen here:
        1. column names are standardised to snake_case (no spaces / units in names)
        2. lineage metadata is added (where the row came from, when it was loaded)
    If anything downstream ever looks wrong, bronze is the untouched copy to compare against.
#}

select
    "UDI"                      as udi,
    "Product ID"               as product_id,
    "Type"                     as product_type,
    "Air temperature [K]"      as air_temperature_k,
    "Process temperature [K]"  as process_temperature_k,
    "Rotational speed [rpm]"   as rotational_speed_rpm,
    "Torque [Nm]"              as torque_nm,
    "Tool wear [min]"          as tool_wear_min,
    "Machine failure"          as machine_failure,
    "TWF"                      as twf,
    "HDF"                      as hdf,
    "PWF"                      as pwf,
    "OSF"                      as osf,
    "RNF"                      as rnf,

    -- lineage metadata
    'uci_ai4i2020.csv'         as _source_file,
    current_timestamp          as _ingested_at

from {{ ref('ai4i2020') }}
