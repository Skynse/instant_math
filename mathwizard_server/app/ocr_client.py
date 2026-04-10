from __future__ import annotations

import io

from PIL import Image


class SuryaOcrClient:
    """Math OCR using surya's RecognitionPredictor with math_mode=True."""

    def __init__(self) -> None:
        self._predictor = None
        self._det_predictor = None

    def _load_model(self) -> None:
        if self._predictor is not None:
            return
        try:
            from surya.recognition import RecognitionPredictor
            from surya.detection import DetectionPredictor
            from surya.foundation import FoundationPredictor
            from surya.settings import settings as surya_settings
        except ImportError as exc:
            raise RuntimeError(
                "surya-ocr is required. Install with:\n"
                "  python3 -m pip install surya-ocr\n"
                "  python3 -m pip install torchvision --index-url https://download.pytorch.org/whl/cpu"
            ) from exc

        foundation = FoundationPredictor(
            checkpoint=surya_settings.RECOGNITION_MODEL_CHECKPOINT
        )
        self._predictor = RecognitionPredictor(foundation)
        self._det_predictor = DetectionPredictor()

    def extract_text(self, image_bytes: bytes) -> str:
        self._load_model()
        img = _preprocess(image_bytes)

        from surya.common.surya.schema import TaskNames

        # Treat the full image as one region to OCR with math mode enabled
        results = self._predictor(
            [img],
            task_names=[TaskNames.ocr_without_boxes],
            det_predictor=self._det_predictor,
            math_mode=True,
        )

        if not results:
            return ""

        lines = results[0].text_lines
        if not lines:
            return ""

        return " ".join(line.text for line in lines if line.text.strip())


def _preprocess(image_bytes: bytes) -> Image.Image:
    img = Image.open(io.BytesIO(image_bytes))
    if img.mode != "RGB":
        img = img.convert("RGB")
    min_side = 224
    if min(img.width, img.height) < min_side:
        ratio = min_side / min(img.width, img.height)
        img = img.resize(
            (int(img.width * ratio), int(img.height * ratio)),
            Image.Resampling.LANCZOS,
        )
    return img


def create_ocr_client() -> SuryaOcrClient:
    return SuryaOcrClient()
