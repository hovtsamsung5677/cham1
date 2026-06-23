"""
AI-сервер для сегментации + перекраски с SAM-2 Hiera-L + ControlNet Tile
"""
import os
import json
import numpy as np
import torch
from io import BytesIO
from typing import Optional
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image

app = FastAPI(title="AI Colorization API", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global model references
_predictor = None
_pipe = None
_device = "cuda" if torch.cuda.is_available() else "cpu"

# Material mapping to prompts
MATERIAL_PROMPTS = {
    "wood": "wood texture, natural wood grain, brown {color}",
    "metal": "metallic surface, shiny metal, reflective, {color}",
    "plastic": "plastic surface, smooth, matte, {color}",
    "fabric": "fabric texture, textile, cloth, {color}",
    "glass": "glass, transparent, reflective, {color}",
}

COLOR_NAMES = {
    "brown": ["saddlebrown", "sienna", "chocolate", "peru", "tan"],
    "green": ["forestgreen", "seagreen", "olive", "darkgreen"],
    "blue": ["steelblue", "navy", "teal", "darkblue"],
    "red": ["darkred", "crimson", "maroon"],
    "yellow": ["gold", "goldenrod", "khaki"],
    "black": ["black", "darkgray"],
    "white": ["white", "lightgray"],
}


def get_color_hex_name(hex_color: int) -> str:
    """Convert hex to closest color name"""
    from colorsys import rgb_to_hsv

    r = (hex_color >> 16) & 0xFF
    g = (hex_color >> 8) & 0xFF
    b = hex_color & 0xFF

    h, s, v = rgb_to_hsv(r/255, g/255, b/255)

    if s < 0.15:
        if v > 0.8:
            return "white"
        if v < 0.2:
            return "black"
        return "lightgray"

    if h < 0.1:
        return "red"
    if h < 0.2:
        return "yellow"
    if h < 0.4:
        return "green"
    if h < 0.6:
        return "blue"
    if h < 0.8:
        return "purple"
    return "red"


@app.on_event("startup")
async def load_models():
    global _predictor, _pipe

    # SAM-2 Hiera-L
    try:
        from sam2.sam2_image_predictor import SAM2ImagePredictor
        _predictor = SAM2ImagePredictor.from_pretrained(
            "facebook/sam2.1-hiera-large")
        _predictor.model = _predictor.model.to(_device).eval()
        if _device == "cuda":
            _predictor.model = _predictor.model.half()
        print("SAM-2 Hiera-L loaded")
    except Exception as e:
        print(f"SAM-2 load error: {e}")

    # ControlNet Tile (InstructPix2Pix variant for faster inference)
    try:
        from diffusers import StableDiffusionControlNetPipeline, ControlNetModel

        controlnet = ControlNetModel.from_pretrained(
            "lllyasviel/control_v11f1p_sd15_depth",
            torch_dtype=torch.float16 if _device == "cuda" else torch.float32
        )

        _pipe = StableDiffusionControlNetPipeline.from_pretrained(
            "runwayml/stable-diffusion-inpainting",
            controlnet=controlnet,
            torch_dtype=torch.float16 if _device == "cuda" else torch.float32
        ).to(_device)

        _pipe.enable_xformers_memory_efficient_attention()
        _pipe.enable_model_cpu_offload()
        print("ControlNet Tile loaded")
    except Exception as e:
        print(f"ControlNet load error: {e}")


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "device": _device,
        "models_loaded": _predictor is not None and _pipe is not None
    }


@app.post("/ai-recolor")
async def ai_recolor(
    image: UploadFile = File(...),
    point_x: float = Form(...),
    point_y: float = Form(...),
    material: str = Form("wood"),
    color_hex: str = Form("0xFF8B4513"),
    strength: float = Form(1.0),
):
    """
    AI-перекраска: сегментация SAM-2 + стилизация ControlNet
    """
    if _predictor is None or _pipe is None:
        raise HTTPException(503, "Models not loaded")

    try:
        # Load image
        img_bytes = await image.read()
        image_pil = Image.open(BytesIO(img_bytes)).convert("RGB")
        image_np = np.array(image_pil)
        if color_hex.startswith("0x"):
            color_hex_int = int(color_hex, 16)
        else:
            color_hex_int = int(color_hex)
        h, w = image_np.shape[:2]

        # SAM-2 segmentation
        with torch.no_grad():
            _predictor.set_image(image_np)
            masks, scores, _ = _predictor.predict(
                point_coords=np.array([[int(point_x), int(point_y)]]),
                point_labels=np.array([1]),
                multimask_output=True,
            )

        best_mask = masks[np.argmax(scores)]

        # Generate prompt
        color_name = get_color_hex_name(color_hex_int)
        prompt_template = MATERIAL_PROMPTS.get(
            material, "smooth surface, {color}")
        prompt = prompt_template.format(
            color=color_name) + f", high quality, photorealistic"

        # Create mask PIL
        mask_pil = Image.fromarray(
            (best_mask * 255).astype(np.uint8), mode='L')

        # ControlNet inference
        result = _pipe(
            prompt=prompt,
            image=image_pil,
            mask_image=mask_pil,
            strength=0.65 + 0.25 * strength,
            guidance_scale=7.5,
            num_inference_steps=20,
            generator=torch.Generator(_device).manual_seed(42),
        ).images[0]

        # Return PNG
        buf = BytesIO()
        result.save(buf, format="PNG")
        return Response(content=buf.getvalue(), media_type="image/png")

    except Exception as e:
        raise HTTPException(500, str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
