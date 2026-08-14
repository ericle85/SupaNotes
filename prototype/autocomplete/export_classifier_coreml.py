import torch
import numpy as np
import coremltools as ct
from models.classifier.network import StrokeClassifier

CKPT_PATH = "models/classifier/xy_classifier.pt"
OUTPUT_PATH = "models/classifier/StrokeClassifier.mlpackage"

ckpt = torch.load(CKPT_PATH, map_location="cpu", weights_only=False)

model = StrokeClassifier(
    input_features=int(ckpt.get("input_features", 2)),
    width=int(ckpt.get("model_width", 32)),
)
model.load_state_dict(ckpt["model_state"])
model.eval()

class_names = list(ckpt.get("class_names"))
seq_len = int(ckpt.get("sequence_length", 160))

print(f"Classes: {class_names}")
print(f"Sequence length: {seq_len}")

class ClassifierWithSoftmax(torch.nn.Module):
    def __init__(self, base):
        super().__init__()
        self.base = base

    def forward(self, x):
        return self.base(x).softmax(dim=1)

wrapped = ClassifierWithSoftmax(model)
wrapped.eval()

dummy = torch.randn(1, seq_len, 2)
traced = torch.jit.trace(wrapped, dummy)

mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="sequence", shape=(1, seq_len, 2))],
    outputs=[ct.TensorType(name="class_probabilities")],
    minimum_deployment_target=ct.target.iOS16,
)

mlmodel.save(OUTPUT_PATH)
print(f"Saved to {OUTPUT_PATH}")

test_input = np.random.randn(1, seq_len, 2).astype(np.float32)
out_torch = wrapped(torch.from_numpy(test_input)).detach().numpy()
out_coreml = mlmodel.predict({"sequence": test_input})["class_probabilities"]
diff = np.abs(out_torch.flatten() - out_coreml.flatten()).max()
print(f"Max diff torch vs coreml: {diff:.6f}")
print(f"Torch output: {out_torch}")
print(f"CoreML output: {out_coreml}")
