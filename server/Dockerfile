FROM python:3.15-alpine
LABEL org.opencontainers.image.source="https://github.com/OLDIN/factorio-mcp" \
      org.opencontainers.image.description="Read-only MCP server for Factorio 2.1" \
      org.opencontainers.image.licenses="MIT"
WORKDIR /app
COPY pyproject.toml ./
COPY factorio_mcp ./factorio_mcp
RUN pip install --no-cache-dir . && adduser -D -H mcp
USER mcp
ENV PYTHONUNBUFFERED=1
CMD ["python", "-m", "factorio_mcp"]
