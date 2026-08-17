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

# Run as a non-root user. AgentCore Runtime already isolates each session in its own
# Firecracker microVM, and the execution role's credentials are readable from the microVM
# metadata service by any code running there - including code the model generates. Dropping
# root does not change what that role can reach, but it does limit what a code-execution
# flaw in the agent or one of its dependencies can do inside the microVM.
#
# The UID must be NUMERIC. A named user (`USER appuser`) combined with a high image layer
# count is a documented cause of an AgentCore start failure that surfaces as HTTP 424 with
# "Failed to mount overlay" - and, more confusingly, as a runtime stuck in READY that fails
# every invocation while writing no CloudWatch logs at all.
#
# chown comes after the last COPY so the venv and agent.py end up owned by the runtime user.
# HOME keeps uv's cache under the writable /app instead of a root-owned home directory.
RUN chown -R 1000:1000 /app
USER 1000
ENV HOME=/app

# Expose port
EXPOSE 8080

# Run application.
#
# `opentelemetry-instrument` is what produces spans - it auto-instruments Strands and
# the HTTP stack at startup. Remove it and you still get a working agent that deploys
# cleanly, reports healthy, and emits NO telemetry; the CloudWatch console cannot
# distinguish that from an agent receiving no traffic.
CMD ["uv", "run", "opentelemetry-instrument", "uvicorn", "agent:app", "--host", "0.0.0.0", "--port", "8080"]