#!/usr/bin/env python3
"""Language retries use only selected languages and keep text/timings together.

Runs the real helper functions with a fake decoder; no MLX/model load required.
"""
import ast
import contextlib
import copy
import math
from pathlib import Path
import sys
import types
import unittest


def result(language, score, text=None, ratio=1.2):
    return {"language": language, "text": text or language,
            "segments": [{"avg_logprob": score, "tokens": [1, 2],
                          "compression_ratio": ratio,
                          "words": [{"word": language, "start": 0, "end": 1}]}]}


class RecognitionLanguageTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.answers = {"fr": result("fr", -1.14), "en": result("en", -0.2)}
        tree = ast.parse((Path(__file__).resolve().parents[1] /
                          "helpers/whisper_helper.py").read_text())
        names = {"language_score", "transcribe", "_worst_ratio"}
        definitions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
        self.ns = dict(math=math, sys=sys, WORDS=False, LANGUAGES=("fr", "en"),
                       MODEL="test", LOOP_CEILING=2.4, VOCABULARY="English terms",
                       VOCABULARY_RO="Romanian terms", quiet=contextlib.nullcontext,
                       A=types.SimpleNamespace(SAMPLE_RATE=16000),
                       pick_language=lambda samples, languages: languages[0] if languages else None,
                       cut_loops=lambda res: None,
                       mlx_whisper=types.SimpleNamespace(transcribe=self.decode))
        exec(compile(ast.Module(body=definitions, type_ignores=[]), "whisper_helper.py", "exec"), self.ns)

    def decode(self, samples, **kwargs):
        self.calls.append(kwargs)
        answer = self.answers[kwargs["language"]]
        if isinstance(answer, Exception):
            raise answer
        return copy.deepcopy(answer)

    def transcribe(self, languages=("fr", "en")):
        return self.ns["transcribe"]("unused", samples=[0] * 16000, words=True, languages=languages)

    def test_wrong_french_guess_recovers_english_and_its_timings(self):
        answer = self.transcribe()
        self.assertEqual(answer["language"], "en")
        self.assertEqual(answer["text"], "en")
        self.assertEqual(answer["segments"][0]["words"][0]["word"], "en")
        self.assertEqual([c["language"] for c in self.calls], ["fr", "en"])
        self.assertEqual([c["initial_prompt"] for c in self.calls], [None, "English terms"])
        self.assertTrue(all(c["task"] == "transcribe" and c["word_timestamps"] for c in self.calls))

    def test_confident_french_needs_no_extra_decode(self):
        self.answers["fr"] = result("fr", -0.2)
        self.assertEqual(self.transcribe()["language"], "fr")
        self.assertEqual(len(self.calls), 1)

    def test_single_language_does_not_switch_even_if_uncertain(self):
        self.assertEqual(self.transcribe(("fr",))["language"], "fr")
        self.assertEqual(len(self.calls), 1)

    def test_automatic_mode_does_not_restrict_language(self):
        self.answers[None] = result("de", -1)
        self.assertEqual(self.transcribe(())["language"], "de")
        self.assertEqual(len(self.calls), 1)

    def test_small_improvement_keeps_first_language(self):
        self.answers["en"] = result("en", -1.1)
        self.assertEqual(self.transcribe()["language"], "fr")

    def test_failed_retry_keeps_original(self):
        self.answers["en"] = RuntimeError("decoder failed")
        self.assertEqual(self.transcribe()["language"], "fr")

    def test_empty_nonfinite_and_looped_candidates_cannot_win(self):
        for candidate in (result("en", -0.1, " "), result("en", math.nan),
                          result("en", -0.1, ratio=3)):
            with self.subTest(candidate=candidate):
                self.answers["en"] = candidate
                self.assertEqual(self.transcribe()["language"], "fr")


if __name__ == "__main__":
    unittest.main(verbosity=2)
