# =====================================================================
# Innovatech SOAR - container image
# Stage "test": lint + unit tests. If they fail, no image is built.
# Stage "runtime": only the app and its runtime packages.
# =====================================================================

FROM python:3.12-slim AS base
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ---------------------------------------------------------------- test
FROM base AS test
COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY . .
RUN ruff check . && pytest -q && touch /tmp/tests-passed

# ---------------------------------------------------------------- runtime
FROM base AS runtime
# This line makes the runtime image depend on the test stage,
# so a normal "docker build" always runs the tests first
COPY --from=test /tmp/tests-passed /tmp/tests-passed
COPY app.py engine.py actions.py rules.yaml ./
RUN useradd --create-home soar
USER soar
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", "--access-logfile", "-", "app:create_app()"]