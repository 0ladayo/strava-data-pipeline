select * from {{ ref('int_weekly_summary') }}

union all

select * from {{ ref('int_monthly_summary') }}