from models.classifier.model import ClassifierModel
from models.ctc.model import CTCModel
from math_engine.ctc_to_autosuggest_translator import translate_ctc_line_to_sympy
from math_engine.engine import do_autosuggestion

ctc_model = CTCModel()
classifier_model = ClassifierModel()

def pipeline(strokes):
    kind = classify_strokes(strokes)
    if kind == "scribble": return

    strokes_as_string = translate_strokes_to_string(strokes, kind)
    suggestion = get_autosuggestion(strokes_as_string, kind)
    print(suggestion)
    # render_suggestion(suggestion) # TODO when we have a UI

def classify_strokes(strokes) -> str:
    return classifier_model.classify(strokes)["class"]

def translate_strokes_to_string(strokes, kind) -> str:
    if kind == "math":
        return ctc_model.transcribe(strokes)
    if kind == "writing":
        # TODO: use google digital ink ml
        return "PLACE HOLDER GOOGLE"
    raise NotImplementedError

def get_autosuggestion(strokes_as_string, kind) -> str:
    if kind == "math":
        sympy_expression = translate_ctc_line_to_sympy(strokes_as_string)
        return do_autosuggestion(sympy_expression)
    
    if kind == "writing":
        return "place holder google"
    raise NotImplementedError



if __name__ == "__main__":
    from models.ctc.preprocessing import parse_inkml
    sample_path = "samples/0a0b310001bedb73.inkml"
    strokes, _ = parse_inkml(sample_path)
    pipeline(strokes)