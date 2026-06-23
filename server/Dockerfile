# AI Server - SAM-2 + ControlNet (fp16 optimized)
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3-pip python3-dev git ca-certificates \
    libglib2.0-0 libsm6 libxext6 libxrender1 libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install PyTorch (CUDA)
RUN pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cu121 --no-cache-dir

# Install dependencies
COPY requirements.ai.txt .
RUN pip3 install -r requirements.ai.txt --no-cache-dir

# Copy app
COPY app.py .

# Cache models on first build
RUN python3 -c "from huggingface_hub import snapshot_download; snapshot_download('facebook/sam2-hiera-l')" 2>/dev/null || true

EXPOSE 8001

CMD ["python3", "app.py"]