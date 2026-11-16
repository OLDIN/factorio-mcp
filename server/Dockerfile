FROM python:3.13-alpine
WORKDIR /app
COPY pyproject.toml ./
COPY factorio_mcp ./factorio_mcp
RUN pip install --no-cache-dir . && adduser -D -H mcp
USER mcp
ENV PYTHONUNBUFFERED=1
CMD ["python", "-m", "factorio_mcp"]
