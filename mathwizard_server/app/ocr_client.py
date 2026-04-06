from __future__ import annotations

import io

from PIL import Image


class SuryaOcrClient:
    """Client for Surya LaTeX OCR - converts math images to LaTeX."""

    def __init__(self) -> None:
        self._predictor = None

    def _load_model(self) -> None:
        """Lazy-load TexifyPredictor on first use."""
        if self._predictor is not None:
            return

        try:
            from surya.texify import TexifyPredictor
        except ImportError as exc:
            raise RuntimeError(
                "surya is required. Install with: pip install surya-ocr"
            ) from exc

        self._predictor = TexifyPredictor()

    def extract_text(self, image_bytes: bytes) -> str:
        """Extract LaTeX from a math image."""
        self._load_model()

        processed_bytes = self._preprocess_image(image_bytes)
        img = Image.open(io.BytesIO(processed_bytes))

        # TexifyPredictor returns one TexifyResult per image; .text is the LaTeX string.
        results = self._predictor([img])

        if results:
            return results[0].text.strip()

        return ""

    def _preprocess_image(self, image_bytes: bytes) -> bytes:
        """Preprocess image for optimal OCR performance."""
        img = Image.open(io.BytesIO(image_bytes))

        # Convert to RGB if necessary
        if img.mode != "RGB":
            img = img.convert("RGB")

        # Surya works well with images up to 1024px on longest side
        max_size = 1024
        min_size = 224

        # Resize if too large
        if max(img.width, img.height) > max_size:
            ratio = max_size / max(img.width, img.height)
            new_size = (int(img.width * ratio), int(img.height * ratio))
            img = img.resize(new_size, Image.Resampling.LANCZOS)

        # Ensure minimum size
        if min(img.width, img.height) < min_size:
            ratio = min_size / min(img.width, img.height)
            new_size = (int(img.width * ratio), int(img.height * ratio))
            img = img.resize(new_size, Image.Resampling.LANCZOS)

        # Convert back to bytes
        buffer = io.BytesIO()
        img.save(buffer, format="PNG")
        return buffer.getvalue()


def create_ocr_client() -> SuryaOcrClient:
    return SuryaOcrClient()
