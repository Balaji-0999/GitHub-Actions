FROM python:3.13-slim-bookworm

WORKDIR /app

RUN apt-get update && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

COPY . .

RUN python -m pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --force-reinstall --upgrade "setuptools>=78.1.1" "msgpack>=1.2.1" -r requirements.txt

EXPOSE 80

CMD ["python", "app.py"]