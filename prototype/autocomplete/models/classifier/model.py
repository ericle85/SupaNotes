import os
import torch
import numpy as np
from models.classifier.network import (
    StrokeClassifier,
    normalize_sequence,
    strokes_to_classifier_sequence,
)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CKPT_PATH = os.path.join(SCRIPT_DIR, "math_google_scribble_none_width32.pt")


class ClassifierModel:

    def __init__(self):
        ckpt = torch.load(CKPT_PATH, map_location="cpu", weights_only=False)
        self.model = StrokeClassifier()
        self.model.load_state_dict(ckpt["model_state"])
        self.model.eval()
        self.sequence_length = int(ckpt.get("sequence_length", 160))
        self.classes = tuple(ckpt.get("class_names"))

    @torch.no_grad()
    def classify(self, strokes) -> dict[str, object]:
        sequence = strokes_to_classifier_sequence(strokes)
        features = torch.from_numpy(
            normalize_sequence(sequence, self.sequence_length)
        ).unsqueeze(0)
        probabilities = self.model(features).softmax(dim=1)[0].cpu().numpy()
        index = int(probabilities.argmax())
        return {
            "class": self.classes[index],
            "probabilities": dict(zip(self.classes, probabilities.tolist())),
        }
