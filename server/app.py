"""
FastAPI сервер для сегментации объектов по одному клику с использованием MobileSAM.
"""

import json
import os
from typing import Optional
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
import numpy as np
import sys
import traceback
from io import BytesIO
import httpx

from segment_utils import preprocess_image, segment_image, rle_encode, rle_decode, load_model, multi_step_segment, color_flood_expand

app = FastAPI(title="MobileSAM Segmentation API", version="1.0.0")

# Настройка CORS для доступа из Flutter-приложения
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # В production укажите конкретные домены
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Глобальные переменные для отслеживания состояния модели
_model_loaded = False
_model_error = None


@app.on_event("startup")
async def startup_event():
    """Инициализация модели при запуске сервера."""
    global _model_loaded, _model_error
    try:
        print("Загрузка модели MobileSAM при старте...")
        load_model()
        _model_loaded = True
        print("Модель успешно загружена. Сервер готов к работе.")
    except Exception as e:
        _model_error = str(e)
        print(f"ОШИБКА при загрузке модели: {e}", file=sys.stderr)
        print("Сервер запущен, но модель не готова. Запросы к /segment будут возвращать ошибку.", file=sys.stderr)


@app.get("/health")
async def health_check():
    """
    Проверка готовности сервиса.
    """
    return {"status": "healthy", "message": "MobileSAM segmentation service is running"}


@app.get("/mobilesam-health")
async def mobilesam_health_check():
    """
    Проверка готовности MobileSAM сервиса через Docker сеть.
    """
    mobilesam_url = os.environ.get("MOBILESAM_URL", "http://mobilesam:7860/")
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(mobilesam_url)
            return {"status": "reachable", "mobilesam_url": mobilesam_url, "response": response.status_code}
    except Exception as e:
        return {"status": "unreachable", "mobilesam_url": mobilesam_url, "error": str(e)}


@app.post("/segment-proxy")
async def segment_proxy_endpoint(
    image: UploadFile = File(..., description="Изображение для сегментации"),
    point_x: float = Form(...,
                          description="Координата X точки клика (пиксели)"),
    point_y: float = Form(...,
                          description="Координата Y точки клика (пиксели)"),
    point_label: int = Form(
        1, description="Метка точки: 1 - foreground, 0 - background"),
    min_component_area: int = Form(
        300, description="Минимальная площадь компонента (пиксели) для сохранения в маске"),
    dilate_kernel: int = Form(
        3, description="Размер ядра дилатации для постобработки"),
    expand_color_threshold: float = Form(
        25.0, description="Порог цветового расстояния для захвата бликов")
):
    """
    Прокси-эндпоинт для пересылки запросов к segment-server.
    Используется для взаимодействия между сервисами в Docker сети.
    """
    segment_server_url = os.environ.get(
        "SEGMENT_SERVER_URL", "http://segment-server:8001/segment")

    try:
        image_bytes = await image.read()

        files = {"image": (image.filename, image_bytes,
                           image.content_type or "application/octet-stream")}
        data = {
            "point_x": str(point_x), 
            "point_y": str(point_y), 
            "point_label": str(point_label), 
            "min_component_area": str(min_component_area),
            "dilate_kernel": str(dilate_kernel),
            "expand_color_threshold": str(expand_color_threshold),
        }

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(segment_server_url, files=files, data=data)
            return JSONResponse(content=response.json(), status_code=response.status_code)

    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"success": False, "error": f"Proxy error: {str(e)}"}
        )


@app.post("/segment")
async def segment_endpoint(
    image: UploadFile = File(..., description="Изображение для сегментации"),
    point_x: float = Form(...,
                          description="Координата X точки клика (пиксели)"),
    point_y: float = Form(...,
                          description="Координата Y точки клика (пиксели)"),
    point_label: int = Form(
        1, description="Метка точки: 1 - foreground, 0 - background"),
    min_component_area: int = Form(
        300, description="Минимальная площадь компонента (пиксели) для сохранения в маске"),
    dilate_kernel: int = Form(
        3, description="Размер ядра дилатации для постобработки"),
    expand_color_threshold: float = Form(
        25.0, description="Порог цветового расстояния для захвата бликов")
):
    """
    Сегментация изображения по точке.

    Принимает изображение и координаты точки, возвращает бинарную маску в формате RLE.
    """
    try:
        print(f"\n--- Новый запрос на сегментацию ---")
        print(f"Файл: {image.filename}, content_type: {image.content_type}")
        print(
            f"Координаты: point_x={point_x}, point_y={point_y}, point_label={point_label}")

        # Проверяем, загружена ли модель
        if not _model_loaded:
            if _model_error:
                raise HTTPException(
                    status_code=503,
                    detail=f"Модель не загружена: {_model_error}"
                )
            else:
                raise HTTPException(
                    status_code=503,
                    detail="Модель загружается, попробуйте позже"
                )

        # Проверяем тип файла по содержимому (магические байты), а не по content_type из запроса
        # т.к. Flutter может отправлять application/octet-stream
        try:
            # Читаем байты один раз и используем их для проверки и обработки
            image_bytes = await image.read()
            print(f"Размер изображения: {len(image_bytes)} bytes")

            # Пробуем открыть изображение - PIL сам определит формат
            test_image = Image.open(BytesIO(image_bytes))
            test_image.verify()  # Проверяем, что файл не поврежден
            print(f"Формат изображения определен: {test_image.format}")
        except Exception as e:
            error_msg = f"Некорректный файл изображения: {str(e)}"
            print(f"ОШИБКА: {error_msg}")
            raise HTTPException(
                status_code=400,
                detail=error_msg
            )

        # Преобразуем в numpy array
        try:
            image_array = preprocess_image(image_bytes)
            h, w = image_array.shape[:2]
            print(f"Изображение преобразовано: размер {w}x{h}")
        except Exception as e:
            print(f"ОШИБКА при обработке изображения: {e}")
            raise HTTPException(
                status_code=400,
                detail=f"Не удалось обработать изображение: {str(e)}"
            )

        # Проверяем координаты
        if not (0 <= point_x < w) or not (0 <= point_y < h):
            error_msg = f"Coordinates out of bounds. Image size: {w}x{h}, point: ({point_x}, {point_y})"
            print(f"ОШИБКА: {error_msg}")
            raise HTTPException(
                status_code=400,
                detail=error_msg
            )

        # Выполняем сегментацию
        print(f"Запуск сегментации...")
        try:
            mask, bbox = segment_image(
                image_array=image_array,
                point_x=point_x,
                point_y=point_y,
                point_label=point_label,
                min_component_area=min_component_area,
                dilate_kernel=dilate_kernel,
                expand_color_threshold=expand_color_threshold
            )
            print(
                f"Сегментация завершена. Маска: shape={mask.shape}, bbox={bbox}")
        except Exception as e:
            print(f"ОШИБКА при сегментации: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Ошибка сегментации: {str(e)}"
            )

        # Кодируем маску в RLE
        try:
            mask_rle = rle_encode(mask)
            print(f"RLE кодирование: counts length={len(mask_rle['counts'])}")
        except Exception as e:
            print(f"ОШИБКА при RLE кодировании: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Ошибка кодирования маски: {str(e)}"
            )

        # Формируем ответ
        response = {
            "success": True,
            "mask": mask_rle,
            "image_size": {"width": w, "height": h}
        }

        if bbox is not None:
            response["bbox"] = bbox

        print(f"Отправка ответа: success=True, size={w}x{h}")
        return JSONResponse(content=response)

    except HTTPException:
        print(f"HTTPException: {traceback.format_exc()}")
        raise
    except Exception as e:
        print(f"Неожиданная ошибка: {traceback.format_exc()}")
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": str(e)
            }
        )


@app.post("/segment-multi")
async def segment_multi_endpoint(
    image: UploadFile = File(..., description="Изображение для сегментации"),
    point_x: float = Form(...,
                          description="Координата X точки клика (пиксели)"),
    point_y: float = Form(...,
                          description="Координата Y точки клика (пиксели)"),
    point_label: int = Form(
        1, description="Метка точки: 1 - foreground, 0 - background"),
    min_component_area: int = Form(
        300, description="Минимальная площадь компонента (пиксели) для сохранения в маске"),
    color_threshold: float = Form(
        35.0, description="Порог цветового расстояния для слияния границ (меньше = строже)"),
    dilate_kernel: int = Form(
        3, description="Размер ядра дилатации для постобработки"),
    existing_mask_counts: Optional[str] = Form(
        None, description="RLE counts существующей маски (JSON массив)"),
    existing_mask_size: Optional[str] = Form(
        None, description="Размер маски '[height, width]' (JSON массив)")
):
    """
    Многошаговая сегментация с аккумуляцией маски.
    Позволяет последовательно добавлять новые участки к существующей маске,
    проверяя границы объекта и цветовую согласованность.
    """
    try:
        print(f"\n--- Многошаговый запрос на сегментацию ---")
        print(f"Файл: {image.filename}, точка: ({point_x}, {point_y})")

        if not _model_loaded:
            if _model_error:
                raise HTTPException(
                    status_code=503,
                    detail=f"Модель не загружена: {_model_error}"
                )
            else:
                raise HTTPException(
                    status_code=503,
                    detail="Модель загружается, попробуйте позже"
                )

        image_bytes = await image.read()
        print(f"Размер изображения: {len(image_bytes)} bytes")

        try:
            image_array = preprocess_image(image_bytes)
            h, w = image_array.shape[:2]
            print(f"Изображение: {w}x{h}")
        except Exception as e:
            print(f"ОШИБКА при обработке изображения: {e}")
            raise HTTPException(
                status_code=400,
                detail=f"Не удалось обработать изображение: {str(e)}"
            )

        if not (0 <= point_x < w) or not (0 <= point_y < h):
            raise HTTPException(
                status_code=400,
                detail=f"Coordinates out of bounds. Image size: {w}x{h}, point: ({point_x}, {point_y})"
            )

        # Декодируем существующую маску, если передана
        existing_mask = None
        if existing_mask_counts and existing_mask_size:
            try:
                counts = json.loads(existing_mask_counts)
                size = json.loads(existing_mask_size)
                existing_mask = rle_decode({"counts": counts, "size": size})
                print(f"Существующая маска: {existing_mask.shape}, пикселей={int(np.sum(existing_mask))}")
            except Exception as e:
                print(f"Предупреждение: не удалось декодировать существующую маску: {e}")

        print(f"Запуск многошаговой сегментации...")
        try:
            mask, bbox, info = multi_step_segment(
                image_array=image_array,
                existing_mask=existing_mask,
                point_x=int(point_x),
                point_y=int(point_y),
                point_label=point_label,
                color_threshold=color_threshold,
                min_component_area=min_component_area,
                dilate_kernel=dilate_kernel
            )
            print(f"Сегментация завершена: {info}")
        except Exception as e:
            print(f"ОШИБКА при сегментации: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Ошибка сегментации: {str(e)}"
            )

        mask_rle = rle_encode(mask)

        response = {
            "success": True,
            "mask": mask_rle,
            "info": info,
            "image_size": {"width": w, "height": h}
        }

        if bbox is not None:
            response["bbox"] = bbox

        return JSONResponse(content=response)

    except HTTPException:
        print(f"HTTPException: {traceback.format_exc()}")
        raise
    except Exception as e:
        print(f"Неожиданная ошибка: {traceback.format_exc()}")
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": str(e)
            }
        )


if __name__ == "__main__":
    import uvicorn
    # Порт можно переопределить через переменную окружения PORT
    import os
    port = int(os.environ.get("PORT", 8001))
    uvicorn.run(app, host="0.0.0.0", port=port)
