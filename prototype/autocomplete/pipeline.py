from models.classifier.model import ClassifierModel
from models.ctc.model import CTCModel
from math_engine.engine import do_autosuggestion

ctc_model = CTCModel()
classifier_model = ClassifierModel()

def pipeline(strokes) -> str:
    """"
    strokes[0] stroke indexing
    strokes[0][i] indexing points of strokes 0
    strokes[0][i][j] indexing point data of strokes 0, stroke i, point j
    """
    kind = classify_strokes(strokes)
    if kind == "scribble": return

    strokes_as_string = translate_strokes_to_string(strokes, kind)
    suggestion = get_autosuggestion(strokes_as_string, kind)
    return suggestion

def classify_strokes(strokes) -> str:
    return classifier_model.classify(strokes)["class"]

def translate_strokes_to_string(strokes, kind) -> str:
    if kind == "math":
        return ctc_model.transcribe(strokes)
    if kind == "writing":
        # TODO: use google digital ink ml which is IOS only
        return "PLACE HOLDER GOOGLE"
    raise NotImplementedError

def get_autosuggestion(strokes_as_string, kind) -> str:
    if kind == "math":
        return do_autosuggestion(strokes_as_string)
    
    if kind == "writing":
        return "place holder google"
    raise NotImplementedError



if __name__ == "__main__":
    from models.ctc.preprocessing import parse_inkml
    sample_path = "samples/math.inkml"
    strokes, _ = parse_inkml(sample_path)
    pipeline(strokes)