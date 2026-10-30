FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Dependências primeiro, para aproveitar o cache de camadas.
COPY pyproject.toml ./
RUN mkdir app && touch app/__init__.py && pip install . && rm -rf app

COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./
RUN pip install --no-deps . \
    && useradd --create-home --uid 10001 evofit
USER evofit

EXPOSE 8000
# As migrações são aplicadas explicitamente (scripts/), nunca automaticamente no start.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
