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
            from surya.common.surya.decoder.config import SuryaDecoderConfig
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

        _patch_surya_compatibility(SuryaDecoderConfig)
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


def _patch_surya_compatibility(config_cls: type) -> None:
    if not hasattr(config_cls, "pad_token_id"):
        # Surya 0.17.1 can load checkpoints whose nested decoder config omits
        # this field, while its decoder model reads it during construction.
        # The parent SuryaModelConfig default is 2.
        config_cls.pad_token_id = 2

    try:
        from transformers.modeling_rope_utils import ROPE_INIT_FUNCTIONS
    except ImportError:
        return

    if "default" not in ROPE_INIT_FUNCTIONS and "proportional" in ROPE_INIT_FUNCTIONS:
        # Surya's Qwen2RotaryEmbedding asks Transformers for the legacy
        # "default" RoPE initializer. Transformers 5 no longer exposes it, and
        # "proportional" is the unscaled initializer for configs without
        # rope_scaling.
        ROPE_INIT_FUNCTIONS["default"] = ROPE_INIT_FUNCTIONS["proportional"]


def create_ocr_client() -> SuryaOcrClient:
    return SuryaOcrClient()
