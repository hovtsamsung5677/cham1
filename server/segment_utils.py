"""
Вспомогательные функции для сегментации объектов с MobileSAM.
"""

import os
import sys
import urllib.request
from pathlib import Path
from typing import Optional, Tuple

import cv2
import numpy as np
import torch
from PIL import Image

# Импорты MobileSAM с несколькими вариантами для совместимости
_sam_import_error = None
_sam_model_registry = None
_SamPredictor = None

try:
    from mobile_sam import sam_model_registry, SamPredictor
    _sam_model_registry = sam_model_registry
    _SamPredictor = SamPredictor
except ImportError as e:
    _sam_import_error = e
    try:
        # Альтернативный путь (может быть в site-packages или при запуске из Docker)
        import site
        site_packages = site.getsitepackages()
        for sp in site_packages:
            sys.path.insert(0, sp)
        from mobile_sam import sam_model_registry, SamPredictor
        _sam_model_registry = sam_model_registry
        _SamPredictor = SamPredictor
    except ImportError as e2:
        _sam_import_error = e2

if _sam_model_registry is None or _SamPredictor is None:
    raise ImportError(
        f"MobileSAM не установлен или не может быть импортирован.\n"
        f"Попробуйте установить: pip install git+https://github.com/ChaoningZhang/MobileSAM.git\n"
        f"Оригинальная ошибка: {_sam_import_error}"
    )

# Глобальная переменная для хранения загруженного предиктора
_predictor = None
_device = None


def get_device() -> str:
    """Определяет доступное устройство (cuda или cpu) с учетом переменной окружения."""
    # Проверяем переменную окружения DEVICE
    env_device = os.environ.get('DEVICE', '').lower()
    if env_device in ('cuda', 'gpu'):
        if torch.cuda.is_available():
            return "cuda"
        else:
            print(
                "Предупреждение: CUDA запрошена через DEVICE, но не доступна. Используется CPU.")
            return "cpu"
    elif env_device == 'cpu':
        return 'cpu'
    else:
        # Автоматическое определение
        return "cuda" if torch.cuda.is_available() else "cpu"


def download_weights(weights_path: str = "weights/mobile_sam.pt") -> str:
    """
    Скачивает веса MobileSAM если они отсутствуют.

    Args:
        weights_path: Путь к файлу весов

    Returns:
        Путь к файлу весов
    """
    weights_file = Path(weights_path)
    weights_file.parent.mkdir(parents=True, exist_ok=True)

    if not weights_file.exists():
        print(f"Скачивание весов MobileSAM в {weights_path}...")
        url = "https://github.com/ChaoningZhang/MobileSAM/raw/master/weights/mobile_sam.pt"
        try:
            urllib.request.urlretrieve(url, weights_path)
            print("Веса успешно скачаны.")
        except Exception as e:
            raise RuntimeError(f"Не удалось скачать веса модели с {url}: {e}")
    else:
        print(f"Веса найдены в {weights_path}")

    return str(weights_file)


def load_model(model_type: str = "vit_t", device: Optional[str] = None):
    """
    Загружает модель MobileSAM и создает предиктор.
    Модель кэшируется для повторного использования.

    Args:
        model_type: Тип модели (vit_t для MobileSAM)
        device: Устройство для инференса ('cuda' или 'cpu')

    Returns:
        SamPredictor: Готовый предиктор для сегментации
    """
    global _predictor, _device

    if _predictor is not None:
        return _predictor

    if device is None:
        device = get_device()

    print(f"Загрузка модели MobileSAM на устройство: {device}")

    # Скачиваем веса если нужно
    weights_path = download_weights()

    # Загружаем модель
    mobile_sam = sam_model_registry[model_type](checkpoint=weights_path)
    mobile_sam.to(device=device)
    mobile_sam.eval()

    # Создаем предиктор
    _predictor = SamPredictor(mobile_sam)
    _device = device

    print(f"Модель MobileSAM успешно загружена на {device}")
    return _predictor


def preprocess_image(image_bytes: bytes) -> np.ndarray:
    """
    Преобразует байты изображения в numpy array в формате RGB.

    Args:
        image_bytes: Байты изображения

    Returns:
        np.ndarray: Изображение в формате (H, W, 3), RGB
    """
    from io import BytesIO

    # Загружаем изображение через PIL
    image = Image.open(BytesIO(image_bytes)).convert("RGB")

    # Конвертируем в numpy array
    image_array = np.array(image)

    return image_array


def rle_encode(mask: np.ndarray) -> dict:
    """
    Кодирует бинарную маску в RLE (Run-Length Encoding) в формате COCO.
    Оптимизированная векторизованная реализация на numpy.

    Args:
        mask: Бинарная маска (H, W) или (H, W, 1)

    Returns:
        dict: Словарь с ключами 'counts' и 'size'
    """
    if mask.ndim == 3:
        mask = mask.squeeze(-1)

    flat_mask = mask.flatten(order="C").astype(np.uint8)

    if flat_mask.size == 0:
        return {"counts": [0], "size": [int(mask.shape[0]), int(mask.shape[1])]}

    prepend_val = 0 if flat_mask[0] == 1 else 1
    changes = np.diff(flat_mask, prepend=prepend_val)
    segment_starts = np.where(changes != 0)[0]
    counts = np.diff(np.append(segment_starts, len(flat_mask)))

    if flat_mask[0] == 1:
        counts = np.concatenate([[0], counts])

    return {
        "counts": counts.tolist(),
        "size": [int(mask.shape[0]), int(mask.shape[1])]
    }


def rle_decode(rle: dict) -> np.ndarray:
    """
    Декодирует RLE маску в бинарную маску.
    Совместимо с COCO RLE: counts начинается с фона (0).

    Args:
        rle: Словарь с ключами 'counts' и 'size'

    Returns:
        np.ndarray: Бинарная маска (H, W)
    """
    h, w = rle["size"]
    mask = np.zeros(h * w, dtype=np.uint8)

    if not rle["counts"]:
        return mask.reshape(h, w)

    counts = rle["counts"]
    idx = 0
    val = 0  # Начинаем с фона (0)

    for count in counts:
        mask[idx:idx + count] = val
        idx += count
        val = 1 - val  # Меняем 0<->1

    # Используем row-major (C-style) порядок для совместимости с Dart/Flutter
    return mask.reshape(h, w, order="C")


def color_flood_expand(
    image_array: np.ndarray,
    mask: np.ndarray,
    color_threshold: float = 25.0,
    max_iterations: int = 2,
    kernel_size: int = 3
) -> np.ndarray:
    """
    Расширяет маску на 1-2 пикселя для захвата бликов/высвечившихся участков.
    Добавляет пиксели на границе, если они похожи по цвету на средний цвет объекта.
    """
    mask_u8 = mask.astype(np.uint8)
    kernel = np.ones((kernel_size, kernel_size), np.uint8)

    mask_pixels = image_array[mask_u8 > 0]
    if len(mask_pixels) > 0:
        avg_color = mask_pixels.mean(axis=0)
    else:
        return mask_u8

    h, w = mask_u8.shape

    for _ in range(max_iterations):
        dilated = cv2.dilate(mask_u8, kernel, iterations=1)
        boundary = (dilated & (~mask_u8)).astype(np.uint8)

        if not boundary.any():
            break

        by, bx = np.where(boundary > 0)
        expanded = mask_u8.copy()

        for y, x in zip(by, bx):
            dist = np.linalg.norm(
                image_array[y, x].astype(np.float32) - avg_color
            )
            if dist < color_threshold:
                expanded[y, x] = 1

        mask_u8 = expanded

    return mask_u8


def postprocess_mask(
    mask: np.ndarray,
    min_component_area: int = 300,
    dilate_kernel: int = 3
) -> np.ndarray:
    """
    1. Удаление мелких отдельных компонентов (мелкие блики)
    2. Удаление внутренних контуров (дырок: ручки дверей, окна)
    3. Дилатация — включить освещённые «ошпареные» участки вокруг объекта

    Args:
        mask: Бинарная маска (H, W)
        min_component_area: Минимальная площадь компонента в пикселях для сохранения
        dilate_kernel: Размер ядра дилатации (0 — пропустить)

    Returns:
        np.ndarray: Обработанная бинарная маска (H, W), dtype=uint8
    """
    mask_u8 = mask.astype(np.uint8)

    # 1. Удаляем мелкие отдельные компоненты (мелкие блики)
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(
        mask_u8, connectivity=8
    )
    
    if num_labels > 1:
        areas = stats[1:, cv2.CC_STAT_AREA]
        keep_mask = areas >= min_component_area
        label_indices = np.arange(1, num_labels)
        keep_labels = label_indices[keep_mask]
        lookup = np.zeros(num_labels, dtype=np.uint8)
        lookup[keep_labels] = 1
        mask_u8 = lookup[labels]

    # 2. Удаляем внутренние контуры (дырки), если они мелкие
    # Используем RETR_CCOMP для получения внешних и внутренних контуров
    contours, hierarchy = cv2.findContours(
        mask_u8, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE
    )
    
    if hierarchy is not None and len(contours) > 0:
        h = hierarchy[0]
        # Внутренние контуры: у них родитель != -1
        inner_contours = [contours[i] for i in range(len(contours)) if h[i][3] != -1]
        
        for cnt in inner_contours:
            area = cv2.contourArea(cnt)
            # Удаляем внутренние контуры мелче порога
            if area < min_component_area * 3:
                cv2.drawContours(mask_u8, [cnt], -1, 0, -1)

    # 3. Дилатация для захвата бликов
    if dilate_kernel > 0 and mask_u8.any():
        kernel = np.ones((dilate_kernel, dilate_kernel), np.uint8)
        mask_u8 = cv2.dilate(mask_u8, kernel, iterations=1)

    return mask_u8


def analyze_boundary(
    image_array: np.ndarray,
    existing_mask: np.ndarray,
    new_mask: np.ndarray,
    color_threshold: float = 35.0,
    sample_size: int = 200
) -> dict:
    """
    Анализирует цветовую границу между существующей и новой маской.
    Определяет, можно ли их слияние (мягкая граница - один объект, жёсткая - разные объекты).

    Args:
        image_array: RGB изображение (H, W, 3)
        existing_mask: Существующая маска (H, W)
        new_mask: Новая маска (H, W)
        color_threshold: Порог цветового расстояния для "мягкой" границы
        sample_size: Размер выборки для анализа (ограничение для производительности)

    Returns:
        dict: Метрики границы и флаг can_merge
    """
    existing_u8 = existing_mask.astype(np.uint8)
    new_u8 = new_mask.astype(np.uint8)

    kernel = np.ones((3, 3), np.uint8)

    # Граница existing (внешние пиксели вокруг маски)
    dilated_existing = cv2.dilate(existing_u8, kernel, iterations=1)
    boundary_existing = (dilated_existing & (~existing_u8)).astype(bool)

    # Пиксели new_only, которые соприкасаются с границей existing
    new_only = (new_u8 & (~existing_u8)).astype(bool)
    dilated_new_only = cv2.dilate(new_only.astype(np.uint8), kernel, iterations=1)
    contact = boundary_existing & dilated_new_only

    if not contact.any():
        return {
            "can_merge": True,
            "reason": "no_contact",
            "mean_color_distance": 0.0,
            "contact_pixels": 0
        }

    contact_coords = np.argwhere(contact)
    new_only_coords = np.argwhere(new_only)

    if len(new_only_coords) == 0 or len(contact_coords) == 0:
        return {
            "can_merge": True,
            "reason": "empty_coords",
            "mean_color_distance": 0.0,
            "contact_pixels": 0
        }

    # Ограничиваем размер выборки для скорости
    sample_size = min(sample_size, len(contact_coords), len(new_only_coords))
    if len(contact_coords) > sample_size:
        idx = np.random.choice(len(contact_coords), sample_size, replace=False)
        contact_coords = contact_coords[idx]
    if len(new_only_coords) > sample_size:
        idx = np.random.choice(len(new_only_coords), sample_size, replace=False)
        new_only_coords = new_only_coords[idx]

    # Находим цвета у граничителей
    boundary_colors = image_array[contact_coords[:, 0], contact_coords[:, 1]].astype(np.float32)

    # Находим ближайшие цвета в new_only к каждому граничителю
    nearest_new_colors = []
    for bc in contact_coords:
        dists = np.sum((new_only_coords - bc) ** 2, axis=1)
        nearest_idx = np.argmin(dists)
        nearest_new_colors.append(image_array[new_only_coords[nearest_idx, 0], new_only_coords[nearest_idx, 1]])

    new_colors = np.array(nearest_new_colors, dtype=np.float32)

    # Вычисляем цветовое расстояние
    color_distances = np.linalg.norm(boundary_colors - new_colors, axis=1)
    mean_dist = float(np.mean(color_distances))

    return {
        "can_merge": mean_dist < color_threshold,
        "reason": "soft_boundary" if mean_dist < color_threshold else "hard_boundary",
        "mean_color_distance": mean_dist,
        "contact_pixels": int(len(contact_coords))
    }


def multi_step_segment(
    image_array: np.ndarray,
    existing_mask: Optional[np.ndarray],
    point_x: int,
    point_y: int,
    point_label: int = 1,
    color_threshold: float = 35.0,
    min_component_area: int = 300,
    dilate_kernel: int = 3,
    device: Optional[str] = None
) -> Tuple[np.ndarray, Optional[list], dict]:
    """
    Многошаговая сегментация с умным расширением маски.

    Если точка клика внутри существующей маски: пытается расширить маску.
    Если точка снаружи: проверяет возможность присоединения.
    При жёсткой границе (разный объект) не расширяет, а ограничивает.

    Args:
        image_array: RGB изображение (H, W, 3)
        existing_mask: Текущая аккумулированная маска (H, W) или None
        point_x, point_y: Координаты клика
        point_label: Метка точки (1 foreground, 0 background)
        color_threshold: Порог цветового расстояния для слияния
        min_component_area: Мин. площадь компонента при постобработке
        dilate_kernel: Размер ядра дилатации
        device: Устройство для инференса

    Returns:
        Tuple[маска, bbox, info_dict]
    """
    h, w = image_array.shape[:2]

    predictor = load_model(device=device)
    predictor.set_image(image_array)

    input_point = np.array([[point_x, point_y]])
    input_label = np.array([point_label])

    masks, scores, logits = predictor.predict(
        point_coords=input_point,
        point_labels=input_label,
        multimask_output=False
    )

    new_mask = masks[0].astype(np.uint8)

    info = {
        "point_inside": False,
        "action": "initial",
        "new_pixels": int(np.sum(new_mask)),
        "merged_pixels": int(np.sum(new_mask))
    }

    if existing_mask is None or not existing_mask.any():
        result = postprocess_mask(new_mask, min_component_area, dilate_kernel)
        if result.any():
            y_idx, x_idx = np.where(result)
            bbox = [int(x_idx.min()), int(y_idx.min()), int(x_idx.max()), int(y_idx.max())]
        else:
            bbox = None
        info["action"] = "initial_mask"
        return result, bbox, info

    if existing_mask.shape != new_mask.shape:
        raise ValueError(
            f"Mask size mismatch: existing {existing_mask.shape} vs new {new_mask.shape}"
        )

    existing_mask_u8 = existing_mask.astype(np.uint8)
    point_inside = bool(existing_mask_u8[point_y, point_x]) if 0 <= point_y < h and 0 <= point_x < w else False
    info["point_inside"] = point_inside

    overlap = (existing_mask_u8 & new_mask).astype(bool)
    new_only = (new_mask & (~existing_mask_u8)).astype(bool)

    if point_inside:
        masks_multi, scores_multi, _ = predictor.predict(
            point_coords=input_point,
            point_labels=input_label,
            multimask_output=True
        )

        best_mask = masks_multi[0]
        best_score = scores_multi[0]

        for m, s in zip(masks_multi, scores_multi):
            overlap_pixels = int(np.sum(m & existing_mask_u8))
            combined_score = s + overlap_pixels * 0.001
            if combined_score > best_score:
                best_score = combined_score
                best_mask = m

        new_mask = best_mask.astype(np.uint8)
        overlap = (existing_mask_u8 & new_mask).astype(bool)
        new_only = (new_mask & (~existing_mask_u8)).astype(bool)

        if not new_only.any():
            kernel_expand = np.ones((5, 5), np.uint8)
            dilated_existing = cv2.dilate(existing_mask_u8, kernel_expand, iterations=1)
            expanded_only = (dilated_existing & (~existing_mask_u8)).astype(bool)

            if expanded_only.any():
                expanded_info = analyze_boundary(
                    image_array, existing_mask_u8, dilated_existing, color_threshold
                )
                if expanded_info["can_merge"]:
                    result = dilated_existing
                    info["action"] = "expanded_dilate"
                else:
                    result = existing_mask_u8
                    info["action"] = "blocked_hard_boundary"
                info["boundary_analysis"] = expanded_info
            else:
                result = existing_mask_u8
                info["action"] = "fully_inside"
        else:
            boundary_info = analyze_boundary(
                image_array, existing_mask_u8, new_mask, color_threshold
            )

            if boundary_info["can_merge"]:
                merged = (existing_mask_u8 | new_mask).astype(bool)
                info["action"] = "expanded"
                result = merged.astype(np.uint8)
            else:
                merged = existing_mask_u8.astype(bool)
                info["action"] = "blocked_hard_boundary"
                result = merged.astype(np.uint8)

            info["boundary_analysis"] = boundary_info
            info["new_pixels"] = int(np.sum(new_only))
    else:
        if not overlap.any():
            boundary_info = analyze_boundary(
                image_array, existing_mask_u8, new_mask, color_threshold
            )

            if boundary_info["can_merge"]:
                merged = (existing_mask_u8 | new_mask).astype(bool)
                info["action"] = "attached_new"
                result = merged.astype(np.uint8)
            else:
                merged = existing_mask_u8.astype(bool)
                info["action"] = "separate_object_ignored"
                result = merged.astype(np.uint8)

            info["boundary_analysis"] = boundary_info
        else:
            merged = (existing_mask_u8 | new_mask).astype(bool)
            info["action"] = "partially_overlapped"
            result = merged.astype(np.uint8)

    result = postprocess_mask(result, min_component_area, dilate_kernel)

    if result.any():
        y_idx, x_idx = np.where(result)
        bbox = [int(x_idx.min()), int(y_idx.min()), int(x_idx.max()), int(y_idx.max())]
    else:
        bbox = None

    info["merged_pixels"] = int(np.sum(result))

    return result, bbox, info


def segment_image(
    image_array: np.ndarray,
    point_x: float,
    point_y: float,
    point_label: int = 1,
    device: Optional[str] = None,
    min_component_area: int = 300,
    dilate_kernel: int = 3,
    expand_color_threshold: float = 25.0
) -> Tuple[np.ndarray, Optional[list]]:
    """
    Выполняет сегментацию изображения по точке.

    Args:
        image_array: Изображение в формате (H, W, 3), RGB
        point_x: Координата X точки (пиксели)
        point_y: Координата Y точки (пиксели)
        point_label: Метка точки (1 - foreground, 0 - background)
        device: Устройство для инференса
        min_component_area: Мин. площадь компонента (отсекает мелкие детали)
        dilate_kernel: Размер ядра дилатации (захват бликов)
        expand_color_threshold: Порог цветового расстояния для бликов (строже)

    Returns:
        Tuple[np.ndarray, Optional[list]]: (маска, bbox в формате [x1,y1,x2,y2])
    """
    predictor = load_model(device=device)
    predictor.set_image(image_array)
    input_point = np.array([[point_x, point_y]])
    input_label = np.array([point_label])
    masks, scores, logits = predictor.predict(
        point_coords=input_point,
        point_labels=input_label,
        multimask_output=False
    )

    mask = masks[0].astype(np.uint8)

    mask = postprocess_mask(
        mask,
        min_component_area=min_component_area,
        dilate_kernel=dilate_kernel
    )

    mask = color_flood_expand(
        image_array,
        mask,
        color_threshold=expand_color_threshold,
        max_iterations=2,
        kernel_size=3
    )

    if mask.any():
        y_indices, x_indices = np.where(mask)
        x_min, x_max = x_indices.min(), x_indices.max()
        y_min, y_max = y_indices.min(), y_indices.max()
        bbox = [int(x_min), int(y_min), int(x_max), int(y_max)]
    else:
        bbox = None

    return mask, bbox
