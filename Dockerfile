# syntax=docker/dockerfile:1
FROM python:3.12-slim

ARG APP_VERSION=dev
ARG GIT_SHA=unknown

LABEL org.opencontainers.image.title="hello-svc" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"
LABEL com.azure.containerizationassist.createdby="containerization-assist"

ENV APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA} \
    PORT=8080 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Non-root user; app files owned by root so the process can't modify them
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
COPY app/ /app/
USER 10001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "/app/main.py", "--healthcheck"]

CMD ["python", "/app/main.py"]