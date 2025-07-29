FROM python:3.13-slim

ENV DBT_ANONYMOUS_USAGE_STATS=False

WORKDIR /app

COPY . .

RUN pip install --no-cache-dir -r requirements.txt

CMD ["dbt", "run"]