FROM python:3.12-slim
COPY install_tools.sh /tmp/install_tools.sh
RUN bash /tmp/install_tools.sh && rm /tmp/install_tools.sh
# Send print() straight to Cloud Logging instead of buffering it.
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["functions-framework", "--target=on_storage_event", "--signature-type=cloudevent"]