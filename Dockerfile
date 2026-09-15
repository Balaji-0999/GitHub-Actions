FROM python:3.13-slim-bookworm

WORKDIR /app

RUN apt-get update && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

COPY . .

RUN pip install  --no-cache-dir -r requirements.txt

RUN pip list | grep -iE "msgpack|setuptools"

EXPOSE 80

CMD ["python", "app.py"]