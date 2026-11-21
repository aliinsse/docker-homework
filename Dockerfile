FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ .

RUN useradd -r -u 10001 appuser && \
    mkdir -p /data && \
    chown -R appuser:appuser /app /data

USER appuser

EXPOSE 8000

CMD ["python", "app.py"]
