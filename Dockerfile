# Multi-stage build for Python backend with TA-Lib

# Stage 1: Build TA-Lib
FROM python:3.11-slim AS talib-builder

RUN apt-get update && apt-get install -y \
    wget \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz && \
    tar -xzf ta-lib-0.4.0-src.tar.gz && \
    cd ta-lib/ && \
    ./configure --prefix=/usr && \
    make && \
    make install

# Stage 2: Runtime
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=talib-builder /usr/lib/libta_lib.* /usr/lib/
COPY --from=talib-builder /usr/include/ta-lib/ /usr/include/ta-lib/

WORKDIR /app

COPY python-backend/requirements.txt .

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY python-backend/app ./app
COPY python-backend/scripts ./scripts
COPY start.sh ./start.sh

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app && chmod +x /app/start.sh
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000/health', timeout=2)"

CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
