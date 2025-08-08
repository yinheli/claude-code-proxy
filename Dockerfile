FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder
ENV UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv venv /opt/venv && . /opt/venv/bin/activate && uv sync --frozen --no-dev
COPY server.py /app/server.py

FROM python:3.12-slim
ENV PATH="/opt/venv/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/server.py /app/server.py
EXPOSE 8082
USER 65534
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8082"]