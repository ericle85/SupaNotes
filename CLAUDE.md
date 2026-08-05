App isn't in production yet, so don't worry about backwards compatibility. 
Use base python env to run python scripts

For a fresh conversation, before any code is written lets work through questions you have about the topic. Lets talk brief and concise so we can ping pong ideas more often. Lets hash out cases, we are more looking at things through a technical lense

Coding Rules:
    - Never write a README.md
    - Prioritize simple code
    - No inline code (things like loops, if statements, etc should be expanded out)
    - No Ternary Operator
    - Single thread
    - Functional programming
    - Zero comments to be written
    - File names and class names must be explicit and word-for-word describe what they do, readable by non-coders at a glance
    Style should match:

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
    


    
Swift: 
    - Swift lint & swift format commands to be run after all changes are made.
    Once you are done working, build on ipad air 13 inch (M3). 