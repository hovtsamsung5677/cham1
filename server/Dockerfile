# AI Server - SAM-2 + ControlNet (fp16 optimized)
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3-pip python3-dev git ca-certificates \
    libglib2.0-0 libsm6 libxext6 libxrender1 libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies first (will be cached unless requirements change)
COPY requirements.ai.txt .
RUN pip3 install -r requirements.ai.txt --no-cache-dir

# Copy app last (frequently changed, invalidates cache only for final layer)
COPY app.py .

EXPOSE 8001

CMD ["python3", "app.py"]
