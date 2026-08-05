# Use uv's ARM64 Python base image.
# Must satisfy requires-python in pyproject.toml (>=3.12) and match .python-version -
# all three are kept on 3.12 deliberately. A base image below the floor fails at
# `uv sync --frozen` rather than at runtime.
FROM --platform=linux/arm64 ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

# Copy uv files
COPY pyproject.toml uv.lock ./

# Install dependencies (including strands-agents)
RUN uv sync --frozen --no-cache

# Copy agent file
COPY agent.py ./

# Expose port
EXPOSE 8080

# Run application.
#
# `opentelemetry-instrument` is what produces spans - it auto-instruments Strands and
# the HTTP stack at startup. Remove it and you still get a working agent that deploys
# cleanly, reports healthy, and emits NO telemetry; the CloudWatch console cannot
# distinguish that from an agent receiving no traffic.
CMD ["uv", "run", "opentelemetry-instrument", "uvicorn", "agent:app", "--host", "0.0.0.0", "--port", "8080"]