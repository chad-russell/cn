FROM python:3.12-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY static/ static/
COPY restaurants.json /data/restaurants.json
EXPOSE 7890
CMD ["python", "app.py"]
