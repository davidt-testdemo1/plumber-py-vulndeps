# syntax=docker/dockerfile:1
# Tudovu-generated. Multi-stage, non-root runtime, with a HEALTHCHECK.
FROM python:3.12-slim AS build
WORKDIR /app
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONDONTWRITEBYTECODE=1
# Build toolchain for dependencies that ship no wheel for this platform. Very
# common in real requirements files (multidict, psycopg2, lxml, cryptography on
# older pins): without gcc, `pip install` dies with
# "error: command 'gcc' failed: No such file or directory" and the whole pipeline
# fails at the build gate. This is the BUILD stage of a multi-stage build and only
# /opt/venv is copied forward, so none of it reaches the runtime image or its
# vulnerability surface.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential libpq-dev \
 && rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

FROM python:3.12-slim AS runtime
WORKDIR /app
ENV PYTHONUNBUFFERED=1 PORT=3000 PATH="/opt/venv/bin:$PATH"
COPY --from=build /opt/venv /opt/venv
COPY --from=build /app /app
# Run as a non-root user.
RUN addgroup --system app && adduser --system --ingroup app app && chown -R app:app /app
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:3000/healthz').status==200 else 1)" || exit 1
CMD ["gunicorn","--config","gunicorn.conf.py","gettingstarted.wsgi"]
