from models.ctc.model import CTCModel

ctc_model = CTCModel()

def pipeline(strokes) -> bool:
    kind = isMathWritingOrScribble(strokes)
    if kind == "scribble" or kind == "writing":
        return False # No autocomplete for these two

    suggestion = get_autosuggestion(translate_strokes_as_string(strokes, kind))
    print(suggestion)
    # render_suggestion(suggestion) # TODO when we have a UI
    return True

def isMathWritingOrScribble(strokes) -> str:
    raise NotImplementedError

def translate_strokes_as_string(strokes, kind) -> str:
    if kind == "math":
        return ctc_model.transcribe(strokes)
    if kind == "writing":
        # TODO: use google digital ink ml
        return "google ocr output"
    raise NotImplementedError

def clean_up_ocr(ctc_output) -> str:
    # clean up the ocr output to remove noise and make it more readable
    raise NotImplementedError

def get_autosuggestion(cleaned_up_ocr) -> str:
    # get the autosuggestion from the cleaned up ocr output
    raise NotImplementedError

if __name__ == "__main__":

    
    pipeline(strokes)