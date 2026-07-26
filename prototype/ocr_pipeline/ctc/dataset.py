"""Dataset + DataLoader for CTC training on MathWriting."""

import os
import re
import glob
import json
import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader
from torch.nn.utils.rnn import pad_sequence
from typing import Dict, List, Tuple, Optional


# Special tokens
BLANK_TOKEN = 0  # CTC blank
PAD_TOKEN = 1
UNK_TOKEN = 2
BOS_TOKEN = 3
EOS_TOKEN = 4
RESERVED = 5  # vocab starts at this index

# Google MathWriting tokenizer regex — groups LaTeX commands as single tokens
_COMMAND_RE = re.compile(
    r'\\(mathbb{[a-zA-Z]}|begin{[a-z]+}|end{[a-z]+}|operatorname\*|[a-zA-Z]+|.)')


def tokenize_latex(s: str) -> List[str]:
    """Tokenize LaTeX string: commands as single tokens, else char-by-char."""
    tokens = []
    while s:
        if s[0] == '\\':
            m = _COMMAND_RE.match(s)
            if m:
                tokens.append(m.group(0))
                s = s[m.end():]
            else:
                tokens.append(s[0])
                s = s[1:]
        else:
            tokens.append(s[0])
            s = s[1:]
    return tokens


class Vocabulary:
    """Token-level vocabulary for LaTeX labels (Google MathWriting style)."""

    def __init__(self):
        self.tok2idx: Dict[str, int] = {}
        self.idx2tok: Dict[int, str] = {}
        self.size = RESERVED  # blank=0, pad=1, unk=2

    def build(self, labels: List[str]):
        """Build vocab from all labels."""
        tokens = set()
        for label in labels:
            tokens.update(tokenize_latex(label))
        for tok in sorted(tokens):
            self.tok2idx[tok] = self.size
            self.idx2tok[self.size] = tok
            self.size += 1

    def encode(self, text: str) -> List[int]:
        return [self.tok2idx.get(tok, UNK_TOKEN) for tok in tokenize_latex(text)]

    def decode(self, indices: List[int]) -> str:
        return ''.join(self.idx2tok.get(idx, '?') for idx in indices
                       if idx not in (BLANK_TOKEN, PAD_TOKEN))

    def save(self, path: str):
        with open(path, 'w') as f:
            json.dump({'tok2idx': self.tok2idx, 'size': self.size}, f)

    def load(self, path: str):
        with open(path) as f:
            data = json.load(f)
        self.tok2idx = data['tok2idx']
        self.size = data['size']
        self.idx2tok = {int(v): k for k, v in self.tok2idx.items()}


class ShardedDataset(Dataset):
    """Dataset backed by npz shards. All data loaded into RAM at init."""

    def __init__(self, shard_dir: str, vocab: Vocabulary, max_seq_len: int = 2048,
                 augment: bool = False):
        self.vocab = vocab
        self.max_seq_len = max_seq_len
        self.augment = augment
        self.features = []
        self.labels = []

        shard_files = sorted(glob.glob(os.path.join(shard_dir, 'shard_*.npz')))
        print(f"Loading {len(shard_files)} shards from {shard_dir}...")
        for sf in shard_files:
            data = np.load(sf, allow_pickle=True)
            lengths = data['lengths']
            all_feat = data['features']
            labels = data['labels']

            offset = 0
            for i, l in enumerate(lengths):
                self.features.append(all_feat[offset:offset+l])
                self.labels.append(str(labels[i]))
                offset += l

        print(f"Loaded {len(self.features)} samples")

    def __len__(self):
        return len(self.features)

    def _augment_features(self, features: np.ndarray) -> np.ndarray:
        """Random augmentation: Gaussian noise + random affine on spatial dims."""
        feat = features.copy()
        # Gaussian noise on all features
        feat += np.random.normal(0, 0.01, feat.shape).astype(np.float32)
        # Random scale on spatial dims (chord vector)
        scale = np.random.uniform(0.9, 1.1, size=2).astype(np.float32)
        feat[:, 0:2] *= scale
        return feat

    def __getitem__(self, idx):
        features = self.features[idx]
        if len(features) > self.max_seq_len:
            features = features[:self.max_seq_len]

        if self.augment:
            features = self._augment_features(features)

        target = self.vocab.encode(self.labels[idx])
        if len(target) == 0:
            target = [UNK_TOKEN]

        return (
            torch.from_numpy(np.asarray(features)).float(),
            torch.tensor(target, dtype=torch.long),
            len(features),
            len(target),
        )


def ctc_collate_fn(batch):
    """Collation for pure CTC: pad features, concat targets."""
    features, targets, feat_lens, target_lens = zip(*batch)

    features_padded = pad_sequence(features, batch_first=True)
    targets_cat = torch.cat(targets)
    feat_lens = torch.tensor(feat_lens, dtype=torch.long)
    target_lens = torch.tensor(target_lens, dtype=torch.long)

    return features_padded, targets_cat, feat_lens, target_lens


def build_vocab_from_shards(shard_dir: str, save_path: Optional[str] = None) -> Vocabulary:
    """Build vocab from shard labels without loading features."""
    labels = []
    for sf in sorted(glob.glob(os.path.join(shard_dir, 'shard_*.npz'))):
        data = np.load(sf, allow_pickle=True)
        labels.extend([str(l) for l in data['labels']])
    vocab = Vocabulary()
    vocab.build(labels)
    if save_path:
        vocab.save(save_path)
    return vocab
