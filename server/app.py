"""
AI-сервер для сегментации + перекраски с SAM-2 и адаптивным recoloring
"""
import logging
import time
import traceback
import numpy as np
import torch
from io import BytesIO
from contextlib import asynccontextmanager
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, ImageDraw
from colorsys import rgb_to_hsv, hsv_to_rgb

torch.set_float32_matmul_precision('high')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DARK_THRESHOLD = 0.35
BRIGHT_THRESHOLD = 0.75


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _predictor, _device
    _device = "cuda" if torch.cuda.is_available() else "cpu"
    logger.info(f"Using device: {_device}")

    try:
        from sam2.sam2_image_predictor import SAM2ImagePredictor
        _predictor = SAM2ImagePredictor.from_pretrained("facebook/sam2.1-hiera-large")
        _predictor.model = _predictor.model.to(_device).eval()
        logger.info("SAM-2 Hiera-L loaded")
    except Exception as e:
        logger.error(f"SAM-2 load error: {e}")
        _predictor = None

    yield

    if torch.cuda.is_available():
        torch.cuda.empty_cache()
        logger.info("GPU cache cleared")


app = FastAPI(title="AI Colorization API", version="2.2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_predictor = None
_device = "cpu"


def get_color_hex_name(hex_color: int) -> str:
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


def _screen_blend(base, target):
    return base + target - (base * target) / 255.0


def _overlay_blend(base, target):
    if base < 0.5:
        return 2 * base * target
    else:
        return 1 - 2 * (1 - base) * (1 - target)


def _build_sam_point_coords(positive_point, negative_points):
    positive_coord = np.array([positive_point])
    positive_labels = np.array([1])
    if len(negative_points) > 0:
        negative_coords = np.array(negative_points)
        negative_labels = np.array([0] * len(negative_points))
        all_coords = np.vstack([positive_coord, negative_coords])
        all_labels = np.concatenate([positive_labels, negative_labels])
        return all_coords, all_labels
    return positive_coord, positive_labels


def recolor_adaptive(image_pil, mask_pil, target_r, target_g, target_b, strength=1.0):
    image_np = np.array(image_pil).astype(np.float32) / 255.0
    mask_np = np.array(mask_pil.convert('L')).astype(np.float32) / 255.0
    h_img, w_img = image_pil.size
    result = image_np.copy()

    t_r, t_g, t_b = target_r / 255.0, target_g / 255.0, target_b / 255.0
    t_h, t_s, t_v = rgb_to_hsv(t_r, t_g, t_b)

    dark_count = 0
    bright_count = 0
    medium_count = 0

    pixel_classes = np.zeros((h_img, w_img), dtype=np.int8)
    for y in range(h_img):
        for x in range(w_img):
            idx = y * w_img + x
            if mask_np[idx] > 0.5:
                r, g, b = image_np[y, x]
                luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if luma < DARK_THRESHOLD:
                    pixel_classes[y, x] = 0
                    dark_count += 1
                elif luma > BRIGHT_THRESHOLD:
                    pixel_classes[y, x] = 1
                    bright_count += 1
                else:
                    pixel_classes[y, x] = 2
                    medium_count += 1

    total = dark_count + bright_count + medium_count
    if total == 0:
        return image_pil

    if dark_count > bright_count and dark_count > medium_count:
        dominant = 'dark'
    elif bright_count > dark_count and bright_count > medium_count:
        dominant = 'bright'
    elif medium_count > dark_count and medium_count > bright_count:
        dominant = 'medium'
    else:
        dominant = 'mixed'

    logger.info(f"   Dominant type: {dominant} (dark={dark_count}, bright={bright_count}, medium={medium_count})")

    use_screen = (dominant == 'dark')
    use_overlay = (dominant in ('bright', 'medium', 'mixed'))

    if use_screen:
        for y in range(h_img):
            for x in range(w_img):
                idx = y * w_img + x
                if mask_np[idx] > 0.5:
                    r, g, b = image_np[y, x] * 255.0
                    tr, tg, tb = t_r * 255.0, t_g * 255.0, t_b * 255.0

                    new_r = _screen_blend(r, tr)
                    new_g = _screen_blend(g, tg)
                    new_b = _screen_blend(b, tb)

                    luma = 0.2126 * (r/255.0) + 0.7152 * (g/255.0) + 0.0722 * (b/255.0)
                    luminance_factor = 0.3 + 0.7 * luma
                    new_r = new_r * luminance_factor
                    new_g = new_g * luminance_factor
                    new_b = new_b * luminance_factor

                    new_r = r + (new_r - r) * strength
                    new_g = g + (new_g - g) * strength
                    new_b = b + (new_b - b) * strength

                    result[y, x] = [new_r/255.0, new_g/255.0, new_b/255.0]

    elif use_overlay:
        for y in range(h_img):
            for x in range(w_img):
                idx = y * w_img + x
                if mask_np[idx] > 0.5:
                    r, g, b = image_np[y, x]
                    gray = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    value = gray

                    nr, ng, nb = hsv_to_rgb(t_h, t_s, value)

                    new_r = r + (nr - r) * strength
                    new_g = g + (ng - g) * strength
                    new_b = b + (nb - b) * strength

                    result[y, x] = [new_r, new_g, new_b]
    else:
        for y in range(h_img):
            for x in range(w_img):
                idx = y * w_img + x
                if mask_np[idx] > 0.5:
                    r, g, b = image_np[y, x]
                    value = max(r, g, b)
                    c = value * t_s
                    x_val = c * (1 - abs((t_h * 60 / 60) % 2 - 1))
                    m = value - c
                    if t_h < 60:
                        nr, ng, nb = c, x_val, 0
                    elif t_h < 120:
                        nr, ng, nb = x_val, c, 0
                    elif t_h < 180:
                        nr, ng, nb = 0, c, x_val
                    elif t_h < 240:
                        nr, ng, nb = 0, x_val, c
                    elif t_h < 300:
                        nr, ng, nb = x_val, 0, c
                    else:
                        nr, ng, nb = c, 0, x_val
                    result[y, x] = [(nr + m), (ng + m), (nb + m)]

    return Image.fromarray((result * 255).astype(np.uint8), 'RGB')


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "device": _device,
        "models_loaded": _predictor is not None
    }


@app.post("/get-mask")
async def get_mask(
    image: UploadFile = File(...),
    point_x: float = Form(...),
    point_y: float = Form(...),
    negative_point_x: str = Form(""),
    negative_point_y: str = Form(""),
):
    """
    Returns SAM-2 segmentation mask with blue overlay on original image.
    Use this to check segmentation quality before recoloring.
    Pass negative_point_x and negative_point_y as comma-separated values.
    """
    if _predictor is None:
        raise HTTPException(503, "SAM-2 not loaded")

    try:
        img_bytes = await image.read()
        image_pil = Image.open(BytesIO(img_bytes)).convert("RGB")
        w, h = image_pil.size
        max_size = 1024
        if w > max_size or h > max_size:
            image_pil.thumbnail((max_size, max_size))
        image_np = np.array(image_pil)

        # Parse negative points
        neg_xs = []
        neg_ys = []
        if negative_point_x.strip() and negative_point_y.strip():
            neg_xs = [float(x.strip()) for x in negative_point_x.split(',')]
            neg_ys = [float(y.strip()) for y in negative_point_y.split(',')]
            neg_xs = neg_xs[:len(neg_ys)]
            neg_ys = neg_ys[:len(neg_xs)]
            neg_points = [[int(x), int(y)] for x, y in zip(neg_xs, neg_ys)]
        else:
            neg_points = []

        positive_coord = np.array([[int(point_x), int(point_y)]])
        positive_labels = np.array([1])
        if len(neg_points) > 0:
            negative_coords = np.array(neg_points)
            negative_labels = np.array([0] * len(neg_points))
            all_coords = np.vstack([positive_coord, negative_coords])
            all_labels = np.concatenate([positive_labels, negative_labels])
        else:
            all_coords = positive_coord
            all_labels = positive_labels

        with torch.no_grad():
            _predictor.set_image(image_np)
            masks, scores, _ = _predictor.predict(
                point_coords=all_coords,
                point_labels=all_labels,
                multimask_output=True,
            )
        best_idx = np.argmax(scores)
        best_mask = masks[best_idx]

        mask_binary = (best_mask > 0.5).astype(np.uint8)
        
        buf = BytesIO()
        Image.fromarray(mask_binary, mode='L').save(buf, format="PNG")
        return Response(content=buf.getvalue(), media_type="image/png")

    except Exception as e:
        logger.error(f"Mask generation failed: {e}")
        raise HTTPException(500, str(e))


@app.post("/ai-recolor")
async def ai_recolor(
    image: UploadFile = File(...),
    point_x: float = Form(...),
    point_y: float = Form(...),
    material: str = Form("wood"),
    color_hex: str = Form("0xFF8B4513"),
    strength: float = Form(1.0),
    negative_point_x: str = Form(""),
    negative_point_y: str = Form(""),
):
    start_time = time.time()
    logger.info("📥 ===== NEW REQUEST =====")
    logger.info(f"   Filename: {image.filename}")
    logger.info(f"   point_x: {point_x}, point_y: {point_y}")
    logger.info(f"   material: {material}, color_hex: {color_hex}, strength: {strength}")

    if _predictor is None:
        logger.error("❌ SAM-2 not loaded")
        raise HTTPException(503, "SAM-2 not loaded")

    try:
        img_bytes = await image.read()
        image_pil = Image.open(BytesIO(img_bytes)).convert("RGB")
        w, h = image_pil.size
        logger.info(f"   Original dimensions: {w}x{h}")
        max_size = 1024
        if w > max_size or h > max_size:
            image_pil.thumbnail((max_size, max_size))
            logger.info(f"   Resized to: {image_pil.size}")
        image_np = np.array(image_pil)

        try:
            if color_hex.startswith("0x"):
                color_hex_int = int(color_hex, 16)
            elif color_hex.startswith("FF"):
                color_hex_int = int("0x" + color_hex, 16)
            else:
                color_hex_int = int(color_hex)
        except ValueError:
            color_hex_int = 0xFF8B4513
        rgb_hex = color_hex_int & 0xFFFFFF

        # Parse negative points
        neg_xs = []
        neg_ys = []
        if negative_point_x.strip() and negative_point_y.strip():
            neg_xs = [float(x.strip()) for x in negative_point_x.split(',')]
            neg_ys = [float(y.strip()) for y in negative_point_y.split(',')]
            neg_xs = neg_xs[:len(neg_ys)]
            neg_ys = neg_ys[:len(neg_xs)]
            neg_points = [[int(x), int(y)] for x, y in zip(neg_xs, neg_ys)]
        else:
            neg_points = []

        positive_coord = np.array([[int(point_x), int(point_y)]])
        positive_labels = np.array([1])
        if len(neg_points) > 0:
            negative_coords = np.array(neg_points)
            negative_labels = np.array([0] * len(neg_points))
            all_coords = np.vstack([positive_coord, negative_coords])
            all_labels = np.concatenate([positive_labels, negative_labels])
        else:
            all_coords = positive_coord
            all_labels = positive_labels

        with torch.no_grad():
            _predictor.set_image(image_np)
            masks, scores, _ = _predictor.predict(
                point_coords=all_coords,
                point_labels=all_labels,
                multimask_output=True,
            )
        best_idx = np.argmax(scores)
        best_mask = masks[best_idx]
        mask_area = np.sum(best_mask)
        logger.info(f"   SAM-2: got {len(masks)} masks, best score={scores[best_idx]:.3f}, mask area={mask_area} pixels")

        if mask_area < 10:
            logger.warning("⚠️ Mask area is very small – object might not be detected!")

        mask_binary = (best_mask > 0.5).astype(np.uint8) * 255
        logger.info(f"   Mask white pixels: {np.sum(mask_binary > 0)} of {mask_binary.size}")
        mask_pil = Image.fromarray(mask_binary, mode='L')

        recolor_start = time.time()
        logger.info("   Recoloring with adaptive blend...")
        target_r = (rgb_hex >> 16) & 0xFF
        target_g = (rgb_hex >> 8) & 0xFF
        target_b = rgb_hex & 0xFF
        result = recolor_adaptive(image_pil, mask_pil, target_r, target_g, target_b, strength)
        recolor_time = time.time() - recolor_start
        logger.info(f"   Recoloring took {recolor_time:.2f}s")

        buf = BytesIO()
        result.save(buf, format="PNG")
        total_time = time.time() - start_time
        logger.info(f"✅ Request completed in {total_time:.2f}s total")
        return Response(content=buf.getvalue(), media_type="image/png")

    except Exception as e:
        total_time = time.time() - start_time
        logger.error(f"❌ Request failed after {total_time:.2f}s: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(500, str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)

