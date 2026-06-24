"""
AI-сервер для сегментации + перекраски с SAM-2 и адаптивным recoloring
"""
import logging
import time
import traceback
import base64
import json
import sys
import os
import numpy as np
import torch
import cv2
from io import BytesIO
from contextlib import asynccontextmanager
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, ImageDraw
from colorsys import rgb_to_hsv, hsv_to_rgb

_base_dir = os.path.dirname(os.path.abspath(__file__))
INTRINSIC_DIR = os.path.join(_base_dir, '..', 'intrinsic_model')
INTRINSIC_DIR = os.path.normpath(INTRINSIC_DIR)
if not os.path.isdir(INTRINSIC_DIR):
    INTRINSIC_DIR = os.path.join(_base_dir, 'intrinsic_model')
if INTRINSIC_DIR not in sys.path:
    sys.path.insert(0, INTRINSIC_DIR)

torch.set_float32_matmul_precision('high')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DARK_THRESHOLD = 0.35
BRIGHT_THRESHOLD = 0.75

MATERIAL_GLOSS_PRESETS = {
    "wood": 0.2,
    "fabric": 0.05,
    "leather": 0.4,
    "plastic": 0.6,
    "metal": 0.8,
    "matte_paint": 0.0,
    "gloss_paint": 0.7,
}
DEFAULT_GLOSS = 0.3

_intrinsic_models = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _predictor, _device
    _device = "cuda" if torch.cuda.is_available() else "cpu"
    logger.info(f"Using device: {_device}")

    try:
        from sam2.sam2_image_predictor import SAM2ImagePredictor
        _predictor = SAM2ImagePredictor.from_pretrained(
            "facebook/sam2.1-hiera-large")
        _predictor.model = _predictor.model.to(_device).eval()
        logger.info("SAM-2 Hiera-L loaded")
    except Exception as e:
        logger.error(f"SAM-2 load error: {e}")
        _predictor = None

    try:
        _load_intrinsic_models()
    except Exception as e:
        logger.error(f"Intrinsic model preload failed: {e}")

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

    logger.info(
        f"   Dominant type: {dominant} (dark={dark_count}, bright={bright_count}, medium={medium_count})")

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

                    luma = 0.2126 * (r/255.0) + 0.7152 * \
                        (g/255.0) + 0.0722 * (b/255.0)
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


def generate_mask_preview(image_pil, mask_pil):
    overlay_color = (74, 144, 226)
    contour_color = (255, 255, 255)
    image_np = np.array(image_pil)
    mask_np = np.array(mask_pil.convert('L'))
    overlay = image_np.copy()
    mask_bool = mask_np > 128
    overlay[mask_bool] = (
        image_np[mask_bool] * 0.55 + np.array(overlay_color) * 0.45
    ).astype(np.uint8)
    contours, _ = cv2.findContours(
        mask_np, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    cv2.drawContours(overlay, contours, -1, contour_color, 2)
    return Image.fromarray(overlay, 'RGB')


def _load_intrinsic_models():
    global _intrinsic_models
    if _intrinsic_models is not None:
        return _intrinsic_models
    try:
        from intrinsic.pipeline import load_models
        _intrinsic_models = load_models('v2.1', device=_device, stage=4)
        logger.info("Intrinsic v2.1 model loaded successfully")
        return _intrinsic_models
    except Exception as e:
        logger.error(f"Failed to load Intrinsic model: {e}")
        _intrinsic_models = {}
        return _intrinsic_models


def recolor_intrinsic(image_pil, mask_pil, target_r, target_g, target_b,
                      gloss_level=0.3, fallback_fn=None):
    try:
        models = _load_intrinsic_models()
        if not models or 'hr_alb' not in [k for k in models.keys()]:
            if fallback_fn:
                logger.warning("Intrinsic model not available, using fallback")
                return fallback_fn(image_pil, mask_pil, target_r, target_g, target_b)
            return image_pil

        from intrinsic.pipeline import run_pipeline
        from chrislib.general import to2np
        from chrislib.color_util import batch_rgb2lab, batch_lab2rgb
        import torch

        image_np = np.array(image_pil).astype(np.float32) / 255.0
        mask_np = np.array(mask_pil.convert('L')).astype(np.float32) / 255.0
        h_img, w_img = image_pil.size
        result = image_np.copy()

        mask_bool = mask_np > 0.5
        if not np.any(mask_bool):
            return image_pil

        masked_region = image_np.copy()
        masked_region[~mask_bool] = 0.5

        with torch.no_grad():
            intrinsic_results = run_pipeline(
                models, masked_region, device=_device, stage=4
            )

        if 'hr_alb' not in intrinsic_results:
            if fallback_fn:
                return fallback_fn(image_pil, mask_pil, target_r, target_g, target_b)
            return image_pil

        albedo = intrinsic_results['hr_alb']
        shading = intrinsic_results['hr_shd']

        albedo_rgb = to2np(albedo) if hasattr(albedo, 'cpu') else albedo
        shading_rgb = to2np(shading) if hasattr(shading, 'cpu') else shading

        if albedo_rgb.ndim == 3 and albedo_rgb.shape[2] == 3:
            albedo_uint8 = (albedo_rgb * 255).clip(0, 255).astype(np.uint8)
            albedo_lab = cv2.cvtColor(albedo_uint8, cv2.COLOR_RGB2LAB)
        else:
            if fallback_fn:
                return fallback_fn(image_pil, mask_pil, target_r, target_g, target_b)
            return image_pil

        t_r, t_g, t_b = target_r / 255.0, target_g / 255.0, target_b / 255.0
        t_uint8 = np.array([[[int(t_r * 255), int(t_g * 255), int(t_b * 255)]]], dtype=np.uint8)
        t_lab = cv2.cvtColor(t_uint8, cv2.COLOR_RGB2LAB)[0, 0]

        mean_a = float(np.mean(albedo_lab[:, :, 1][mask_bool]))
        mean_b = float(np.mean(albedo_lab[:, :, 2][mask_bool]))
        delta_a = float(t_lab[1]) - mean_a
        delta_b = float(t_lab[2]) - mean_b
        albedo_lab[:, :, 1] = np.clip(albedo_lab[:, :, 1].astype(np.float32) + delta_a, 0, 255).astype(np.uint8)
        albedo_lab[:, :, 2] = np.clip(albedo_lab[:, :, 2].astype(np.float32) + delta_b, 0, 255).astype(np.uint8)

        new_albedo_rgb = cv2.cvtColor(albedo_lab, cv2.COLOR_LAB2RGB)
        new_albedo_rgb = new_albedo_rgb.astype(np.float32) / 255.0

        recolored = new_albedo_rgb * shading_rgb
        recolored = np.clip(recolored, 0, 1)

        if gloss_level > 0.0:
            luma = 0.2126 * recolored[:, :, 0] + 0.7152 * recolored[:, :, 1] + 0.0722 * recolored[:, :, 2]
            highlight_mask = luma > 0.86
            boost = 1.0 + gloss_level * 0.3
            recolored[highlight_mask] = np.clip(recolored[highlight_mask] * boost, 0, 1)

        mask_3ch = mask_np[:, :, np.newaxis]
        blur_mask = cv2.GaussianBlur(mask_np, (7, 7), 3.0)
        blur_mask_3ch = blur_mask[:, :, np.newaxis]
        result = image_np * (1 - blur_mask_3ch) + recolored * blur_mask_3ch
        result = np.clip(result, 0, 1)

        return Image.fromarray((result * 255).astype(np.uint8), 'RGB')

    except Exception as e:
        logger.error(f"Intrinsic recolor failed: {e}\n{traceback.format_exc()}")
        if fallback_fn:
            logger.info("Falling back to recolor_adaptive")
            return fallback_fn(image_pil, mask_pil, target_r, target_g, target_b)
        return image_pil


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
    Returns JSON: {"mask": "<base64>", "preview": "<base64>"}
    """
    if _predictor is None:
        raise HTTPException(503, "SAM-2 not loaded")

    try:
        img_bytes = await image.read()
        image_pil = Image.open(BytesIO(img_bytes)).convert("RGB")
        orig_w, orig_h = image_pil.size
        logger.info(
            f"📥 get-mask: original size {orig_w}x{orig_h}, point=({point_x},{point_y})")

        max_size = 1024
        if orig_w > max_size or orig_h > max_size:
            scale = min(max_size / orig_w, max_size / orig_h)
            new_w = int(orig_w * scale)
            new_h = int(orig_h * scale)
            image_pil.thumbnail((max_size, max_size))
            logger.info(f"   Resized to {new_w}x{new_h}, scale={scale:.3f}")
            point_x = point_x * scale
            point_y = point_y * scale
        else:
            scale = 1.0
            new_w, new_h = orig_w, orig_h

        px = int(point_x)
        py = int(point_y)
        logger.info(f"   Using scaled point: ({px},{py})")

        neg_xs = []
        neg_ys = []
        if negative_point_x.strip() and negative_point_y.strip():
            neg_xs = [float(x.strip()) for x in negative_point_x.split(',')]
            neg_ys = [float(y.strip()) for y in negative_point_y.split(',')]
            neg_xs = [x * scale for x in neg_xs]
            neg_ys = [y * scale for y in neg_ys]
            neg_xs = neg_xs[:len(neg_ys)]
            neg_ys = neg_ys[:len(neg_xs)]
            neg_points = [[int(x), int(y)] for x, y in zip(neg_xs, neg_ys)]
        else:
            neg_points = []

        image_np = np.array(image_pil)

        positive_coord = np.array([[px, py]])
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
        logger.info(
            f"   SAM-2: best score={scores[best_idx]:.3f}, mask area={mask_area} pixels")

        mask_binary = (best_mask > 0.5).astype(np.uint8)
        white_pixels = np.sum(mask_binary)
        logger.info(
            f"   Mask white pixels: {white_pixels} of {mask_binary.size}")

        if white_pixels == 0:
            logger.warning("⚠️ Empty mask! Check your point coordinates.")

        mask_img = Image.fromarray(mask_binary * 255, mode='L')

        mask_buf = BytesIO()
        mask_img.save(mask_buf, format="PNG")
        mask_b64 = base64.b64encode(mask_buf.getvalue()).decode('utf-8')

        preview_pil = generate_mask_preview(image_pil, mask_img)
        preview_buf = BytesIO()
        preview_pil.save(preview_buf, format="PNG")
        preview_b64 = base64.b64encode(preview_buf.getvalue()).decode('utf-8')

        logger.info(f"   Returning JSON with mask and preview")
        return JSONResponse(content={
            "mask": mask_b64,
            "preview": preview_b64,
        })

    except Exception as e:
        logger.error(f"Mask generation failed: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(500, str(e))


@app.post("/ai-recolor")
async def ai_recolor(
    image: UploadFile = File(...),
    point_x: float = Form(...),
    point_y: float = Form(...),
    material: str = Form("wood"),
    color_hex: str = Form("0xFF8B4513"),
    strength: float = Form(1.0),
    gloss: float = Form(-1.0),
    negative_point_x: str = Form(""),
    negative_point_y: str = Form(""),
):
    start_time = time.time()
    logger.info("📥 ===== NEW REQUEST =====")
    logger.info(f"   Filename: {image.filename}")
    logger.info(f"   point_x: {point_x}, point_y: {point_y}")
    logger.info(
        f"   material: {material}, color_hex: {color_hex}, strength: {strength}, gloss: {gloss}")

    if _predictor is None:
        logger.error("❌ SAM-2 not loaded")
        raise HTTPException(503, "SAM-2 not loaded")

    try:
        img_bytes = await image.read()
        image_pil = Image.open(BytesIO(img_bytes)).convert("RGB")
        orig_w, orig_h = image_pil.size
        logger.info(f"   Original dimensions: {orig_w}x{orig_h}")

        max_size = 1024
        if orig_w > max_size or orig_h > max_size:
            scale = min(max_size / orig_w, max_size / orig_h)
            new_w = int(orig_w * scale)
            new_h = int(orig_h * scale)
            image_pil.thumbnail((max_size, max_size))
            logger.info(f"   Resized to {new_w}x{new_h}, scale={scale:.3f}")
            point_x = point_x * scale
            point_y = point_y * scale
        else:
            scale = 1.0

        px = int(point_x)
        py = int(point_y)
        logger.info(f"   Using scaled point: ({px},{py})")

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

        neg_xs = []
        neg_ys = []
        if negative_point_x.strip() and negative_point_y.strip():
            neg_xs = [float(x.strip()) for x in negative_point_x.split(',')]
            neg_ys = [float(y.strip()) for y in negative_point_y.split(',')]
            neg_xs = [x * scale for x in neg_xs]
            neg_ys = [y * scale for y in neg_ys]
            neg_xs = neg_xs[:len(neg_ys)]
            neg_ys = neg_ys[:len(neg_xs)]
            neg_points = [[int(x), int(y)] for x, y in zip(neg_xs, neg_ys)]
        else:
            neg_points = []

        positive_coord = np.array([[px, py]])
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
        logger.info(
            f"   SAM-2: got {len(masks)} masks, best score={scores[best_idx]:.3f}, mask area={mask_area} pixels")

        if mask_area < 10:
            logger.warning(
                "⚠️ Mask area is very small – object might not be detected!")

        mask_binary = (best_mask > 0.5).astype(np.uint8) * 255
        white_pixels = np.sum(mask_binary > 0)
        logger.info(
            f"   Mask white pixels: {white_pixels} of {mask_binary.size}")
        mask_pil = Image.fromarray(mask_binary, mode='L')

        recolor_start = time.time()
        logger.info("   Recoloring with intrinsic decomposition...")

        target_r = (rgb_hex >> 16) & 0xFF
        target_g = (rgb_hex >> 8) & 0xFF
        target_b = rgb_hex & 0xFF

        if gloss < 0:
            gloss_level = MATERIAL_GLOSS_PRESETS.get(material, DEFAULT_GLOSS)
        else:
            gloss_level = max(0.0, min(1.0, gloss))
        logger.info(f"   Using gloss_level={gloss_level:.2f} for material={material}")

        result = recolor_intrinsic(
            image_pil, mask_pil, target_r, target_g, target_b,
            gloss_level=gloss_level,
            fallback_fn=recolor_adaptive,
        )
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
