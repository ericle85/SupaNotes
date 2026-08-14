---
title: AutoPlace PoC — Spline Overlay Placement Model
status: planning
---

## Goal

Train an RL model that takes existing strokes (randomized location) + suggestion strokes (location at 0,0) and outputs (dx, dy) to place the suggestion directly on top of the existing strokes. Proves the pipeline: splines in → model → transform out.

## Architecture

- Policy network: MLP (flattened points → hidden layers → 2 outputs: dx, dy)
- Algorithm: REINFORCE (continuous action, single-step episode = contextual bandit)
- Framework: PyTorch
- Deployment: CoreML export of policy net forward pass

## Environment (Pygame)

- Black canvas
- Reference strokes: red — one hardcoded "Hello World" stroke set (placed somewhere random)
- Suggestion strokes: green — same stroke set
- Each episode: model sees both stroke sets as observation, outputs (dx, dy), strokes are shifted, reward is computed
- Visual render: toggle-able so training can run headless, but can flip on to watch convergence

## Observation

- Sample N evenly-spaced (x, y) points from each stroke in the reference set → flatten
- Same for suggestion set (at its current random offset)
- Concatenate both → single vector of length 4N (ref_x, ref_y, sug_x, sug_y per point)
- Normalize to canvas dimensions [0, 1]

## Action

- Continuous (dx, dy), clipped to canvas bounds
- Applied as translation to all suggestion stroke points

## Reward

- Negative mean Euclidean distance between corresponding point pairs after translation
- Episode is single-step: one action, one reward, done

## Training

- Runs on Linux box w/ GPU over SSH
- REINFORCE with baseline (running mean of rewards)
- Hyperparams to start: lr=1e-3, hidden_size=128, 2 hidden layers, episodes=10k
- Random offset range: ±200px on a 800x600 canvas
- Log reward curve, render every K episodes to gif/video for debugging

## Data

- PoC: one hardcoded "Hello World" stroke set (captured or synthesized from font)
- Later: real Apple Pencil stroke data from app usage (data flywheel)

## Export

- Strip value baseline, export policy net forward pass only
- PyTorch → ONNX → CoreML (or torch → coremltools direct)
- Input: flattened point vector, Output: (dx, dy)
- Runs on-device in Swift app

## Future (not in PoC)

- Context type flag input (math vs english)
- Horizontal append: place "World" right of "Hello" with spacing
- Vertical align: place equation line below, aligned at `=` sign
- Online RL from real usage data flywheel


## End goal

- Ability to align suggestions to where I desire
- Will enable things like autosuggestions being placed live as the user is writing to contiue their thought
- Once the user writes a math line, the autosuggestion can be placed below it in a acceptable location