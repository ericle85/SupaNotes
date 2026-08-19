--
title: Datafly wheel
status: planning
--

## Problem to solve

CTC model, Classifier Model will need extra data to improve.

## Bottleneck in Autosuggestion Quality

The biggest bottle neck is accuracy of the CTC model (used to go from online math strokes to latex).

## Desired Outcomes

When a suggestion appears on screen, user can accept, move the suggestion, or reject it. 
Once the interaction is done we track:
    The user's decision to accept, move, or reject
    The raw online strokes sent sent into the autocomplete pipeline (in inkml file)
    Classifier Output, CTC or Google Ink output, Suggestion generated, Initial placement of suggestion by Placement model, Final placement of suggestion if moved.

Data is packed up and sent later
