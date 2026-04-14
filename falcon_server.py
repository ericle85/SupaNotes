"""Run this on the Linux box: python falcon_server.py"""
import torch
from falcon_perception import OCR_MODEL_ID, load_and_prepare_model, setup_torch_config
from falcon_perception.data import ImageProcessor, load_image
from falcon_perception.paged_ocr_inference import OCRInferenceEngine
from fastapi import FastAPI, UploadFile, File
import tempfile, os, uvicorn
from PIL import Image
import io

setup_torch_config()

app = FastAPI()

print("Loading Falcon OCR...")
model, tokenizer, model_args = load_and_prepare_model(
    hf_model_id=OCR_MODEL_ID,
    device=None,
    dtype="bfloat16",
    compile=True,
)
image_processor = ImageProcessor(patch_size=16, merge_size=1)
engine = OCRInferenceEngine(model, tokenizer, image_processor, capture_cudagraph=False, n_pages=32)
print("Ready.")

@app.post("/ocr")
async def ocr(file: UploadFile = File(...)):
    data = await file.read()
    img = Image.open(io.BytesIO(data)).convert("RGB")
    with torch.inference_mode():
        texts = engine.generate_plain(images=[img])
    return {"text": texts[0]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
