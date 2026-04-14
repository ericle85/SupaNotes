import requests, base64, time

SERVER = "http://100.121.248.31:11434"
IMAGE_PATH = "/Users/ericle/.claude/image-cache/a02ae143-82cc-451e-8d10-cd5fc12095b4/1.png"

img = base64.b64encode(open(IMAGE_PATH, "rb").read()).decode()
body = {
    "model": "glm-ocr:q8_0",
    "messages": [{"role": "user", "content": "Text Recognition:", "images": [img]}],
    "stream": False,
    "options": {"temperature": 0}
}

print("Warming up...")
requests.post(f"{SERVER}/api/chat", json=body)

print("Timed run...")
t = time.time()
r = requests.post(f"{SERVER}/api/chat", json=body)
print(f"Time: {time.time()-t:.2f}s")
print("Full response:", r.json())
print("OCR result:", r.json()["message"]["content"])
