import os
import torch
import numpy as np
from models.classifier.network import StrokeClassifier, normalize_sequence

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CKPT_PATH = os.path.join(SCRIPT_DIR, "xyt_zeroed_t.pt")


class ClassifierModel:

    def __init__(self):
        ckpt = torch.load(CKPT_PATH, map_location="cpu", weights_only=False)
        self.model = StrokeClassifier(
            input_features=int(ckpt.get("input_features", 3)),
            width=int(ckpt.get("model_width", 32)),
        )
        self.model.load_state_dict(ckpt["model_state"])
        self.model.eval()
        self.sequence_length = int(ckpt.get("sequence_length", 160))
        self.classes = tuple(ckpt.get("class_names"))

    @torch.no_grad()
    def classify(self, strokes) -> dict[str, object]:
        features = torch.from_numpy(
            normalize_sequence(strokes, self.sequence_length)
        ).unsqueeze(0)
        probabilities = self.model(features).softmax(dim=1)[0].cpu().numpy()
        index = int(probabilities.argmax())
        return {
            "class": self.classes[index],
            "probabilities": dict(zip(self.classes, probabilities.tolist())),
        }
