from autocomplete.autocomplete_pipeline import run_autocomplete_on_document_text


def test_trailing_equals_places_ghost_text_right():
    result = run_autocomplete_on_document_text("2+3=")
    ghost = result.suggestion.ghost_text
    assert result.classified_intent.operation.name == "EVALUATE_NUMERIC"
    assert ghost is not None
    assert ghost.text == "5"
    assert ghost.placement == "right"


def test_leading_equals_places_ghost_text_left():
    result = run_autocomplete_on_document_text("=2+3")
    ghost = result.suggestion.ghost_text
    assert result.classified_intent.operation.name == "EVALUATE_NUMERIC"
    assert ghost is not None
    assert ghost.text == "5"
    assert ghost.placement == "left"


def test_definitions_from_preceding_feed_numeric_ghost():
    result = run_autocomplete_on_document_text("a=4\nb=3\na+b=")
    ghost = result.suggestion.ghost_text
    assert ghost is not None
    assert ghost.text == "7"
    assert ghost.placement == "right"


def test_non_numeric_has_no_ghost_text():
    result = run_autocomplete_on_document_text("a+b=")
    assert result.suggestion.ghost_text is None
    assert result.suggestion.has_suggestion is False
