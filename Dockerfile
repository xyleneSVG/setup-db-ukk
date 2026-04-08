FROM python:3.11-slim

RUN pip install flask docker --break-system-packages

WORKDIR /app/dashboard

CMD ["python", "app.py"]