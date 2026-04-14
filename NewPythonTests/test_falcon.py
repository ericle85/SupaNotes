from falcon_perception import OCR_MODEL_ID, build_prompt_for_task, load_from_hf_export_mlx
from falcon_perception.mlx.batch_inference import BatchInferenceEngine, process_batch_and_generate
from PIL import Image
import numpy as np

IMAGE_PATH = "/Users/ericle/.claude/image-cache/a02ae143-82cc-451e-8d10-cd5fc12095b4/1.png"

print("Loading Falcon OCR...")
model, tokenizer, model_args = load_from_hf_export_mlx(
    hf_model_id=OCR_MODEL_ID, dtype="float16"
)
print("Loaded.")

img = Image.open(IMAGE_PATH).convert("RGB")
prompt = build_prompt_for_task("", "ocr_plain")

batch = process_batch_and_generate(
    tokenizer, [(IMAGE_PATH, prompt)],
    max_length=model_args.max_seq_len,
    min_dimension=64, max_dimension=1024,
    patch_size=model_args.spatial_patch_size
)

engine = BatchInferenceEngine(model, tokenizer)
stop_token_ids = [tokenizer.eos_token_id, tokenizer.end_of_query_token_id]

output_tokens, _ = engine.generate(
    tokens=batch["tokens"], pos_t=batch["pos_t"], pos_hw=batch["pos_hw"],
    pixel_values=batch["pixel_values"], pixel_mask=batch["pixel_mask"],
    max_new_tokens=4096, temperature=0.0,
    stop_token_ids=stop_token_ids,
    task="detection"
)

all_toks = np.array(output_tokens[0]).flatten()
n_prefill = batch["tokens"].shape[1]
decoded_toks = all_toks[n_prefill:]

stop_set = set(stop_token_ids + [tokenizer.pad_token_id])
eos_positions = np.where(np.isin(decoded_toks, list(stop_set)))[0]
n_decoded = int(eos_positions[0]) if len(eos_positions) > 0 else len(decoded_toks)
text = tokenizer.decode(decoded_toks[:n_decoded].tolist(), skip_special_tokens=True)

print("\n--- OCR Output ---")
print(text)
