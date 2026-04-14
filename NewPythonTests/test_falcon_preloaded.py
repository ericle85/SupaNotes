"""Client — runs on Mac, sends image to Linux box for OCR."""
import requests
import time

SERVER = "http://100.121.248.31:8000"
IMAGE_PATH = "/Users/ericle/.claude/image-cache/a02ae143-82cc-451e-8d10-cd5fc12095b4/1.png"

def ocr(image_path):
    with open(image_path, "rb") as f:
        r = requests.post(f"{SERVER}/ocr", files={"file": ("image.png", f, "image/png")})
    r.raise_for_status()
    return r.json()["text"]

# Warmup
print("Warmup run...")
t1 = time.time()
text = ocr(IMAGE_PATH)
print(f"Warmup time: {time.time()-t1:.2f}s")

# Timed
print("\nTimed run...")
t2 = time.time()
text = ocr(IMAGE_PATH)
print(f"Inference time: {time.time()-t2:.2f}s")

print("\n--- OCR Output ---")
print(text)
